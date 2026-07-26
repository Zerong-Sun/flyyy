#!/usr/bin/env python3
"""
Resume tarot + iching deck generation in EXISTING ChatGPT chats.
- One tab per deck (no sidebar scanning, no fresh chat per batch)
- Submit → poll every --poll-sec (default 180s) → download → next batch
- Each batch asks for N SEPARATE images in ONE reply (still 10-up prompts)
- If GPT returns a contact sheet instead, split it

Usage:
  .venv/bin/python resume_dual_decks.py \\
    --iching-url 'https://chatgpt.com/c/6a5e0a7b-c49c-83ee-9b3c-47aa07750ab0' \\
    --tarot-url 'https://chatgpt.com/c/...'  # reuse existing chat URL
"""

from __future__ import annotations

import argparse
import asyncio
import hashlib
import json
import re
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path

from batch_art_utils import (
    ART_DIR,
    BatchFile,
    BatchJob,
    image_to_webp_bytes,
    parse_batch_prompts_md,
    split_contact_sheet,
)
from chatgpt_gen_art import (
    batch_out_dir,
    click_send,
    connect_browser,
    fetch_image_bytes,
    find_composer,
    resize_to_spec,
    submit_prompt,
    safe_detect_rate_limit,
)

STYLE_TAROT = (
    "Cloud-ridge Twilight manuscript tarot. Identical ornate cloud-thunder gold border "
    "#BDA476, blank nameplate at bottom, parchment cream #F0E4D0, forest-ink #0D1411. "
    "Mauve #9A6B84 accents. Flat mineral paint. No readable titles/numerals/watermarks on art "
    "(blank nameplate only)."
)
STYLE_ICHING = (
    "Cloud-ridge Twilight I Ching manuscript cards. Verdigris #55806D + gold #BDA476 border, "
    "parchment #F0E4D0, forest-ink #0D1411. Each cell: hexagram lines top, scene center, "
    "Chinese name + English subtitle on nameplate. Flat mineral paint."
)


@dataclass
class DeckState:
    name: str
    prompts_file: str
    chat_url: str
    page: object = None
    waiting: bool = False
    pending_files: list = field(default_factory=list)
    pending_batch_name: str = ""
    baseline_srcs: set = field(default_factory=set)
    submitted_at: float = 0.0
    done: bool = False


def load_batches(prompts_file: str) -> list:
    p = ART_DIR / prompts_file
    return parse_batch_prompts_md(p.read_text(encoding="utf-8"), source=prompts_file)


def missing_jobs(batches) -> list[tuple]:
    """Return [(batch, [missing BatchFile]), ...] for incomplete batches in order."""
    out = []
    for b in batches:
        out_dir = batch_out_dir(b)
        miss = [
            bf
            for bf in b.files
            if not (out_dir / bf.filename).exists() or (out_dir / bf.filename).stat().st_size == 0
        ]
        if miss:
            out.append((b, miss))
    return out


def build_batch_message(files: list[BatchFile], style: str, n: int, kind: str) -> str:
    """Ask for N SEPARATE images in one response (same chat, no new window)."""
    listing = "\n".join(
        f"{i+1}. {bf.filename}: {bf.description}" for i, bf in enumerate(files)
    )
    if n == 1:
        return (
            f"Generate exactly ONE vertical {kind} card face image (2:3, opaque ~512×768). "
            f"Do not write an explanation.\n\n{style}\n\n"
            f"1. {files[0].filename}: {files[0].description}\n"
        )
    return (
        f"Generate exactly {n} SEPARATE {kind} card face images in this single response "
        f"(NOT a contact sheet, NOT a grid — {n} individual images). "
        f"Each vertical 2:3, opaque, ~512×768. Do not write an explanation. "
        f"No text labels, filenames, or watermarks on the images. "
        f"Output images in numbered order 1→{n}.\n\n"
        f"{style}\n\nImage order 1→{n}:\n{listing}\n"
    )


async def collect_imgs(page) -> list[dict]:
    return await page.evaluate(
        """() => {
          const main = document.querySelector('main') || document.body;
          const out = []; const seen = new Set();
          const isGen = s => s && (s.includes('estuary')||s.includes('oaiusercontent')||
            s.includes('backend-api/')||s.startsWith('blob:'));
          for (const img of main.querySelectorAll('img')) {
            const src = img.currentSrc || img.src || '';
            if (!src || seen.has(src) || src.includes('avatar')) continue;
            const w = Math.max(img.naturalWidth||0, img.getBoundingClientRect().width||0);
            const h = Math.max(img.naturalHeight||0, img.getBoundingClientRect().height||0);
            if (!isGen(src) && (w < 120 || h < 120)) continue;
            if (w < 80 || h < 80) continue;
            seen.add(src);
            out.push({ src, w, h });
          }
          return out;
        }"""
    )


async def generation_busy(page) -> bool:
    return bool(
        await page.locator(
            'button[aria-label*="Stop" i], [data-testid="stop-button"], button:has-text("Stop")'
        ).count()
    )


async def dismiss_rate_limit(page, cooldown_sec: int = 300) -> bool:
    hit = await safe_detect_rate_limit(page)
    if not hit:
        try:
            text = await page.evaluate("() => (document.body&&document.body.innerText)||''")
        except Exception:
            return False
        if not re.search(r"too many requests|temporarily limited", text or "", re.I):
            return False
        hit = "rate limit"
    print(f"  [{(page.url or '')[-12:]}] rate-limit ({hit}); cooldown {cooldown_sec}s…", flush=True)
    for label in ("Got it", "OK", "Dismiss", "Close", "知道了"):
        loc = page.get_by_role("button", name=label)
        if await loc.count():
            try:
                await loc.first.click(timeout=2000)
            except Exception:
                pass
    await page.wait_for_timeout(cooldown_sec * 1000)
    return True


async def ensure_chat(page, url: str) -> None:
    """Navigate once to chat URL; if homepage, click New chat once."""
    cur = page.url or ""
    if url.rstrip("/") in cur.rstrip("/") and "/c/" in cur:
        return
    await page.goto(url, wait_until="domcontentloaded", timeout=120_000)
    await page.wait_for_timeout(2000)
    if await dismiss_rate_limit(page):
        await page.wait_for_timeout(60_000)
    # If landed on home without a conversation, start one new chat
    if "/c/" not in (page.url or ""):
        for sel in [
            'a[href="/"]',
            'button:has-text("New chat")',
            '[data-testid="create-new-chat-button"]',
        ]:
            loc = page.locator(sel)
            if await loc.count():
                try:
                    await loc.first.click(timeout=3000)
                    await page.wait_for_timeout(1500)
                    break
                except Exception:
                    pass


async def submit_in_place(page, message: str) -> None:
    await dismiss_rate_limit(page)
    await submit_prompt(page, message, new_chat=False)


def sheet_job_for(files: list[BatchFile], batch: BatchJob) -> BatchJob:
    n = len(files)
    if n == 10:
        cols, rows = 5, 2
    elif n == 8:
        cols, rows = 4, 2
    elif n == 4:
        cols, rows = 4, 1
    elif n == 2:
        cols, rows = 2, 1
    else:
        cols, rows = n, 1
    return BatchJob(
        name=batch.name,
        files=[BatchFile(f.filename, f.description, 512, 768) for f in files],
        prompt=batch.prompt,
        cols=cols,
        rows=rows,
        cell_w=200,
        cell_h=300,
        transparent=False,
        source=batch.source,
        mode="sheet",
        output_dir=batch.output_dir,
    )


async def save_new_images(page, deck: DeckState) -> int:
    imgs = await collect_imgs(page)
    new = [im for im in imgs if im["src"] not in deck.baseline_srcs]
    if not new:
        return 0
    files = deck.pending_files
    out_dir = batch_out_dir(
        BatchJob(
            name=deck.pending_batch_name,
            files=files,
            prompt="",
            cols=1,
            rows=1,
            cell_w=512,
            cell_h=768,
            transparent=False,
            output_dir=ART_DIR.parent / ("decks/tarot" if deck.name == "tarot" else "decks/iching"),
        )
    )
    # fake batch for out dir
    out_dir = ART_DIR.parent / ("decks/tarot" if deck.name == "tarot" else "decks/iching")
    out_dir.mkdir(parents=True, exist_ok=True)
    saved = 0

    n = len(files)
    # Prefer landscape contact sheet (w > h); never treat a portrait card as a grid
    landscapes = [im for im in new if im["w"] > im["h"] and im["w"] >= 900]
    looks_like_sheet = n >= 4 and bool(landscapes)
    if n == 1:
        looks_like_sheet = False

    if looks_like_sheet:
        top = landscapes[-1]
        print(f"  [{deck.name}] got grid {top['w']}×{top['h']} — splitting", flush=True)
        raw = await fetch_image_bytes(page, top["src"])
        batch_stub = BatchJob(
            name=deck.pending_batch_name,
            files=files,
            prompt="",
            cols=5,
            rows=2,
            cell_w=200,
            cell_h=300,
            transparent=False,
        )
        if n == 10:
            batch_stub.cols, batch_stub.rows = 5, 2
        elif n == 8:
            batch_stub.cols, batch_stub.rows = 4, 2
        elif n == 4:
            batch_stub.cols, batch_stub.rows = 4, 1
        elif n == 2:
            batch_stub.cols, batch_stub.rows = 2, 1
        cells = split_contact_sheet(raw, batch_stub, gutter_trim=True)
        for bf, cell in zip(files, cells):
            dest = out_dir / bf.filename
            if dest.exists() and dest.stat().st_size > 0:
                print(f"    skip existing {bf.filename}", flush=True)
                continue
            data = image_to_webp_bytes(cell, False, 90, bf.description)
            dest.write_bytes(data)
            print(f"    saved {bf.filename} ({len(data)}b)", flush=True)
            saved += 1
    else:
        ordered = [im for im in imgs if im["src"] not in deck.baseline_srcs]
        # Prefer portrait card faces
        portraits = [im for im in ordered if im["h"] >= im["w"] * 0.85 and im["w"] >= 200]
        pool = portraits if len(portraits) >= n else ordered
        if len(pool) < n:
            print(f"  [{deck.name}] have {len(pool)}/{n} new images — keep waiting", flush=True)
            return 0
        use = pool[-n:]
        for bf, img in zip(files, use):
            dest = out_dir / bf.filename
            if dest.exists() and dest.stat().st_size > 0:
                print(f"    skip existing {bf.filename}", flush=True)
                continue
            raw = await fetch_image_bytes(page, img["src"])
            cell = resize_to_spec(raw, bf, False)
            data = image_to_webp_bytes(cell, False, 90, bf.description)
            dest.write_bytes(data)
            print(f"    saved {bf.filename} ({len(data)}b)", flush=True)
            saved += 1
    return saved


async def try_submit_next(deck: DeckState, batches) -> bool:
    if deck.waiting or deck.done:
        return False
    miss = missing_jobs(batches)
    if not miss:
        deck.done = True
        print(f"  [{deck.name}] ALL DONE", flush=True)
        return False
    batch, files = miss[0]
    # Cap at 10; if leftover singles from earlier batches, files is already just missing
    n = len(files)
    style = STYLE_TAROT if deck.name == "tarot" else STYLE_ICHING
    kind = "tarot" if deck.name == "tarot" else "I Ching"
    # Ask for N separate images in ONE reply; stay in the same chat window
    msg = build_batch_message(files, style, n, kind)
    print(f"  [{deck.name}] submit {batch.name} ({n} files) …", flush=True)
    before = await collect_imgs(deck.page)
    deck.baseline_srcs = {im["src"] for im in before}
    try:
        await submit_in_place(deck.page, msg)
    except Exception as e:
        print(f"  [{deck.name}] submit failed: {e}", flush=True)
        if await dismiss_rate_limit(deck.page):
            return False
        return False
    deck.waiting = True
    deck.pending_files = files
    deck.pending_batch_name = batch.name
    deck.submitted_at = time.time()
    return True


async def try_harvest(deck: DeckState) -> bool:
    if not deck.waiting:
        return False
    if await generation_busy(deck.page):
        print(f"  [{deck.name}] still generating…", flush=True)
        return False
    if await dismiss_rate_limit(deck.page):
        return False
    saved = await save_new_images(deck.page, deck)
    if saved <= 0:
        elapsed = time.time() - deck.submitted_at
        print(f"  [{deck.name}] no complete result yet ({int(elapsed)}s)", flush=True)
        return False
    print(f"  [{deck.name}] harvested {saved} files", flush=True)
    deck.waiting = False
    deck.pending_files = []
    deck.pending_batch_name = ""
    return True


async def run(args: argparse.Namespace) -> int:
    tarot_batches = load_batches("ART_PROMPTS_TAROT_DECK.md")
    iching_batches = load_batches("ART_PROMPTS_ICHING_DECK.md")

    browser = await connect_browser(args.port)
    try:
        ctx = browser.contexts[0]
        # Reuse existing pages if possible
        iching_page = None
        tarot_page = None
        for p in ctx.pages:
            u = p.url or ""
            if args.iching_url and args.iching_url.split("?")[0] in u:
                iching_page = p
            if args.tarot_url and "/c/" in u and "tarot" in (await p.title()).lower():
                tarot_page = p
        if iching_page is None:
            iching_page = ctx.pages[0] if ctx.pages else await ctx.new_page()
        if tarot_page is None or tarot_page is iching_page:
            tarot_page = await ctx.new_page()

        decks = [
            DeckState("tarot", "ART_PROMPTS_TAROT_DECK.md", args.tarot_url or "https://chatgpt.com/", tarot_page),
            DeckState(
                "iching",
                "ART_PROMPTS_ICHING_DECK.md",
                args.iching_url or "https://chatgpt.com/c/6a5e0a7b-c49c-83ee-9b3c-47aa07750ab0",
                iching_page,
            ),
        ]

        print("Opening deck chats (once each)…", flush=True)
        await ensure_chat(decks[0].page, decks[0].chat_url)
        await ensure_chat(decks[1].page, decks[1].chat_url)
        # update URLs if new chats created
        for d in decks:
            if "/c/" in (d.page.url or ""):
                d.chat_url = d.page.url.split("?")[0]
                print(f"  {d.name} chat: {d.chat_url}", flush=True)

        batches_map = {"tarot": tarot_batches, "iching": iching_batches}

        # Initial submit only for still-missing batches (skip-existing via missing_jobs)
        for d in decks:
            miss = missing_jobs(batches_map[d.name])
            left = sum(len(f) for _, f in miss)
            print(f"  [{d.name}] {left} files still missing across {len(miss)} batches", flush=True)
            await try_submit_next(d, batches_map[d.name])
            await asyncio.sleep(5)  # small stagger

        poll = args.poll_sec
        while not all(d.done for d in decks):
            print(f"\n— poll @ {time.strftime('%H:%M:%S')} (next in {poll}s) —", flush=True)
            for d in decks:
                if d.done:
                    continue
                await d.page.bring_to_front()
                await asyncio.sleep(0.5)
                harvested = await try_harvest(d)
                if harvested or not d.waiting:
                    await try_submit_next(d, batches_map[d.name])
            if all(d.done for d in decks):
                break
            await asyncio.sleep(poll)

        print(json.dumps({"tarot_done": decks[0].done, "iching_done": decks[1].done}))
        return 0
    finally:
        pw = getattr(browser, "_fq_pw", None)
        try:
            await browser.close()
        except Exception:
            pass
        if pw:
            await pw.stop()


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=9222)
    ap.add_argument("--iching-url", default="https://chatgpt.com/c/6a5e0a7b-c49c-83ee-9b3c-47aa07750ab0")
    ap.add_argument("--tarot-url", default="https://chatgpt.com/")
    ap.add_argument("--poll-sec", type=int, default=180)
    args = ap.parse_args()
    raise SystemExit(asyncio.run(run(args)))


if __name__ == "__main__":
    main()
