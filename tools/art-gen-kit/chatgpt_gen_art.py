#!/usr/bin/env python3
"""
Attach to a Chrome instance started with --remote-debugging-port, submit
ART_PROMPTS.md Prompt 1 entries to ChatGPT image generation, download results,
convert to .webp, and save under fatequest/assets/art/ with Brief filenames.

Prereq:
  ./launch_chrome_debug.sh
  Log in to chatgpt.com in that Chrome window.

Examples:
  .venv/bin/python chatgpt_gen_art.py --dry-run
  .venv/bin/python chatgpt_gen_art.py --skip-existing --limit 1
  .venv/bin/python chatgpt_gen_art.py --section P0 --prompt-index 1
"""

from __future__ import annotations

import argparse
import asyncio
import hashlib
import io
import json
import re
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable
from urllib.parse import urlparse

from PIL import Image
from playwright.async_api import Browser, Page, async_playwright

from batch_art_utils import (
    SHEETS_DIR,
    BatchJob,
    collect_catalog,
    embed_catalog_descriptions,
    image_to_webp_bytes,
    parse_batch_prompts_md,
    sheet_path_for,
    split_contact_sheet,
    write_catalog,
)

from kit_paths import ART_DIR, PROMPTS_DIR, ROOT

PROMPTS_PATH = PROMPTS_DIR / "ART_PROMPTS.md"

SECTION_MARKERS = {
    "P0": (r"# 一、P0", r"# 二、P1"),
    "P1": (r"# 二、P1", r"# 三、P2"),
    "P2": (r"# 三、P2", r"# 附录"),
    "ALL": (r"# 一、P0", r"# 附录"),
}

STYLE_LOCK = (
    "Cloud-ridge Twilight style: medieval manuscript illumination crossed with dusk mountain wilderness. "
    "Muted low-saturation palette — forest ink #0D1411, parchment cream #F0E4D0, antique gold #BDA476, "
    "rubric crimson #B3402E as rare accent only, mist blue #7FA3BD, cloud-peach #E8B28A. "
    "Flat mineral-paint look, thick gold contours where needed, subtle paper grain and gold-leaf flecks; "
    "candlelight or dusk glow only — never neon. No photorealism, no 3D render, no glossy AI highlights, "
    "no anthropomorphic deity figures."
)

IMAGE_PREFIX = (
    "Generate exactly one image. Do not write an explanation. "
    "Follow the style and technical constraints in the prompt strictly. "
    "If the prompt asks for a transparent background, keep the subject on a "
    "clean transparent (or pure checker-ready flat) field.\n\n"
)

BATCH_PREFIX = (
    "Generate exactly ONE contact-sheet image. Do not write an explanation. "
    "Follow the grid layout and style strictly. Use thin dark gutters between cells. "
    "Do not add text labels, filenames, or watermarks on the sheet.\n\n"
)

SEPARATE_PREFIX = (
    "Generate exactly the requested number of SEPARATE images in ONE response. "
    "Do not write an explanation. Each image must be its own standalone output "
    "(NOT a contact sheet, NOT a grid collage). "
    "Output images in numbered order matching the list below. "
    "Do not add text labels, filenames, or watermarks on the images.\n\n"
)

_CJK_RE = re.compile(r"[\u4e00-\u9fff]")


def build_batch_message(job: BatchJob) -> str:
    listing = "\n".join(
        f"{i + 1}. {bf.filename}: {bf.description}" if bf.description else f"{i + 1}. {bf.filename}"
        for i, bf in enumerate(job.files)
    )
    if job.mode == "separate":
        n = len(job.files)
        alpha = "Transparent background." if job.transparent else "Opaque full-bleed background."
        message = (
            SEPARATE_PREFIX
            + STYLE_LOCK
            + f" Produce exactly {n} separate images. Each roughly {job.files[0].out_w}×{job.files[0].out_h} logical pixels, vertical 2:3 where applicable. {alpha}\n\n"
            + f"Image order 1→{n}:\n{listing}\n\n"
            + job.prompt
            + "\n\nNegative: photorealistic, 3D render, neon glow, anime, cluttered, watermark, "
            "signature, text labels, filenames on image, contact sheet, grid collage."
        )
    else:
        alpha = "Transparent background cells." if job.transparent else "Opaque cells."
        message = (
            BATCH_PREFIX
            + STYLE_LOCK
            + f" Grid: {job.cols} columns × {job.rows} rows. "
            f"Each cell roughly {job.cell_w}×{job.cell_h} logical pixels. {alpha}\n\n"
            + f"Cell order left-to-right, top-to-bottom:\n{listing}\n\n"
            + job.prompt
            + "\n\nNegative: photorealistic, 3D render, neon glow, anime, cluttered, watermark, "
            "signature, text labels, filenames on image."
        )
    if _CJK_RE.search(message):
        raise RuntimeError(f"Chinese characters found in batch {job.name}; refusing to submit.")
    return message


def batch_out_dir(job: BatchJob) -> Path:
    return job.output_dir if job.output_dir else ART_DIR


def resize_to_spec(raw: bytes, bf, transparent: bool) -> Image.Image:
    im = Image.open(io.BytesIO(raw))
    im = im.convert("RGBA" if transparent else "RGB")
    if bf.out_w and bf.out_h and (im.width != bf.out_w or im.height != bf.out_h):
        im = im.resize((bf.out_w, bf.out_h), Image.Resampling.LANCZOS)
    return im


async def wait_for_new_images(page: Page, prev_srcs: set[str], timeout_ms: int, max_n: int = 10, min_n: int = 1) -> list[str]:
    """Return up to max_n new image URLs in DOM order (assistant message, top to bottom)."""
    deadline = time.monotonic() + timeout_ms / 1000
    found: list[str] = []
    stable_hits = 0
    while time.monotonic() < deadline:
        limited = await detect_rate_limit(page)
        if limited:
            raise RuntimeError(f"rate-limited: {limited}")
        ordered = await new_images_dom_order(page, prev_srcs)
        if len(ordered) >= min_n:
            found = ordered[:max_n]
            busy = await generation_in_progress(page)
            if not busy:
                stable_hits += 1
                if stable_hits >= 2 and len(found) >= min_n:
                    await page.wait_for_timeout(2000)
                    ordered = await new_images_dom_order(page, prev_srcs)
                    return ordered[:max_n]
            else:
                stable_hits = 0
        await page.wait_for_timeout(2000)
    if found and len(found) >= min_n:
        return found
    raise TimeoutError(f"Timed out waiting for {min_n} generated image(s); got {len(found)}")


async def new_images_dom_order(page: Page, prev_srcs: set[str]) -> list[str]:
    """New assistant images in document order (oldest→newest within latest turn)."""
    raw = await page.evaluate(
        """(prevList) => {
          const prev = new Set(prevList);
          const main = document.querySelector('main') || document.body;
          const articles = [...main.querySelectorAll('[data-message-author-role="assistant"], article')];
          const roots = articles.length ? articles : [main];
          const root = roots[roots.length - 1] || main;
          const out = [];
          const seen = new Set();
          for (const img of root.querySelectorAll('img')) {
            const src = img.currentSrc || img.src || '';
            if (!src || prev.has(src) || src.startsWith('data:image/svg')) continue;
            if (src.includes('avatar') || src.includes('/icon')) continue;
            const w = Math.max(img.naturalWidth || 0, img.getBoundingClientRect().width || 0);
            const h = Math.max(img.naturalHeight || 0, img.getBoundingClientRect().height || 0);
            const looksGen = src.includes('estuary/content')
              || src.includes('oaiusercontent.com')
              || src.includes('oaidalle')
              || src.includes('/backend-api/')
              || src.startsWith('blob:');
            if (!looksGen && (w < 120 || h < 120)) continue;
            if (seen.has(src)) continue;
            seen.add(src);
            out.push(src);
          }
          return out;
        }""",
        list(prev_srcs),
    )
    return raw or []


async def run_batch_jobs(args: argparse.Namespace) -> int:
    prompts_path = Path(args.prompts_file)
    if not prompts_path.is_absolute():
        prompts_path = ART_DIR / prompts_path.name if prompts_path.name == args.prompts_file else prompts_path
    if not prompts_path.exists():
        prompts_path = ROOT / "assets" / "art" / Path(args.prompts_file).name
    text = prompts_path.read_text(encoding="utf-8")
    batches = parse_batch_prompts_md(text, source=prompts_path.name)
    if args.only:
        only = set(args.only)
        batches = [
            b
            for b in batches
            if b.name in only
            or any(Path(f.filename).stem in only or f.filename in only for f in b.files)
        ]
    if args.limit is not None:
        batches = batches[: args.limit]

    if not batches:
        print("No batch jobs matched.", file=sys.stderr)
        return 1

    total_files = sum(len(b.files) for b in batches)
    print(f"Batches: {len(batches)} ({total_files} files)")
    for b in batches:
        mode_label = b.mode if b.mode == "separate" else f"{b.cols}×{b.rows} sheet"
        print(f"  - {b.name}: {len(b.files)} files ({mode_label})")

    if args.dry_run:
        print("Dry run — not connecting to Chrome.")
        return 0

    ART_DIR.mkdir(parents=True, exist_ok=True)
    SHEETS_DIR.mkdir(parents=True, exist_ok=True)
    prompts_stem = prompts_path.stem
    browser = await connect_browser(args.port)
    try:
        page = await get_chatgpt_page(browser)
        await ensure_logged_in(page, wait=args.wait_login, wait_ms=args.wait_login_ms)
        known_hashes = existing_art_hashes(ART_DIR)
        ok = fail = 0

        for bidx, batch in enumerate(batches, 1):
            out_dir = batch_out_dir(batch)
            out_dir.mkdir(parents=True, exist_ok=True)
            missing = [
                bf.filename
                for bf in batch.files
                if not (out_dir / bf.filename).exists()
                or (out_dir / bf.filename).stat().st_size == 0
            ]
            if args.skip_existing and not missing:
                print(f"[batch {bidx}/{len(batches)}] skip {batch.name} (all exist)")
                ok += len(batch.files)
                continue

            n = len(batch.files)
            kind = "separate images" if batch.mode == "separate" else "cells"
            print(f"[batch {bidx}/{len(batches)}] generating {batch.name} ({n} {kind}) …")
            message = build_batch_message(batch)
            success = False
            last_err: Exception | None = None
            for attempt in range(1, args.retries + 1):
                try:
                    await wait_out_rate_limit(page, pause_ms=args.rate_limit_ms)
                    await open_fresh_chat(page)
                    prev = await collect_image_srcs(page)
                    await submit_prompt(page, message, new_chat=False)
                    batch_timeout = args.timeout_ms
                    if batch.mode == "separate":
                        batch_timeout = max(args.timeout_ms, 90_000 * len(batch.files))
                    if batch.mode == "separate":
                        srcs = await wait_for_new_images(
                            page, prev, timeout_ms=batch_timeout, max_n=n, min_n=n
                        )
                        if len(srcs) < n:
                            raise RuntimeError(f"expected {n} images, got {len(srcs)}")
                        saved = 0
                        for i, (bf, src) in enumerate(zip(batch.files, srcs)):
                            target = out_dir / bf.filename
                            if args.skip_existing and target.exists() and target.stat().st_size > 0:
                                saved += 1
                                continue
                            raw = await fetch_image_bytes(page, src)
                            cell = resize_to_spec(raw, bf, batch.transparent)
                            data = image_to_webp_bytes(
                                cell, batch.transparent, args.quality, bf.description
                            )
                            digest = hashlib.md5(data).hexdigest()
                            other = known_hashes.get(digest)
                            if other and other != target.name:
                                raise RuntimeError(f"duplicate hash of {other} for {target.name}")
                            target.write_bytes(data)
                            known_hashes[digest] = target.name
                            print(
                                f"    [{i+1}/{n}] saved {target.name} ({bf.out_w}×{bf.out_h}, "
                                f"{len(data)} bytes, md5={digest[:8]})"
                            )
                            saved += 1
                    else:
                        srcs = await wait_for_new_images(
                            page, prev, timeout_ms=args.timeout_ms, max_n=3, min_n=1
                        )
                        raw = await fetch_image_bytes(page, srcs[0])
                        sheet_path = sheet_path_for(batch, prompts_stem)
                        sheet_path.write_bytes(raw)
                        print(f"    sheet saved {sheet_path.name}")
                        cells = split_contact_sheet(raw, batch)
                        saved = 0
                        for bf, cell in zip(batch.files, cells):
                            target = out_dir / bf.filename
                            if args.skip_existing and target.exists() and target.stat().st_size > 0:
                                saved += 1
                                continue
                            ext = target.suffix.lower()
                            if ext == ".webp":
                                data = image_to_webp_bytes(
                                    cell, batch.transparent, args.quality, bf.description
                                )
                            else:
                                buf = io.BytesIO()
                                cell.save(buf, format="PNG")
                                data = buf.getvalue()
                            digest = hashlib.md5(data).hexdigest()
                            other = known_hashes.get(digest)
                            if other and other != target.name:
                                raise RuntimeError(f"duplicate hash of {other} for {target.name}")
                            target.write_bytes(data)
                            known_hashes[digest] = target.name
                            print(
                                f"    saved {target.name} ({bf.out_w}×{bf.out_h}, "
                                f"{len(data)} bytes, md5={digest[:8]})"
                            )
                            saved += 1
                    if saved == 0 and args.skip_existing:
                        success = True
                        ok += len(batch.files)
                        break
                    pending = [
                        bf.filename
                        for bf in batch.files
                        if not args.skip_existing or not (out_dir / bf.filename).exists()
                    ]
                    if saved < len(pending):
                        raise RuntimeError(f"only saved {saved}/{len(pending)} cells")
                    success = True
                    ok += saved
                    break
                except Exception as e:
                    last_err = e
                    print(f"    retry {attempt}/{args.retries}: {e}", file=sys.stderr)
                    if "rate-limited" in str(e).lower() or await safe_detect_rate_limit(page):
                        await wait_out_rate_limit(page, pause_ms=args.rate_limit_ms)
                    else:
                        await page.wait_for_timeout(2000)
            if not success:
                fail += len(batch.files)
                print(f"    FAIL batch {batch.name}: {last_err}", file=sys.stderr)
                if args.stop_on_error:
                    break
            await page.wait_for_timeout(args.pause_ms)

        catalog = collect_catalog(ART_DIR)
        write_catalog(catalog)
        n = embed_catalog_descriptions(catalog, ART_DIR)
        print(f"ART_CATALOG.json updated ({catalog['count']} assets); EXIF in {n} file(s).")
        print(json.dumps({"ok": ok, "fail": fail, "batches": len(batches)}))
        return 0 if fail == 0 else 2
    finally:
        pw = getattr(browser, "_fq_pw", None)
        try:
            await browser.close()
        except Exception:
            pass
        if pw:
            await pw.stop()


@dataclass
class ArtJob:
    name: str  # e.g. sym-sun.webp
    where: str
    content: str
    spec: str
    accent: str
    prompt: str
    width: int | None
    height: int | None
    transparent: bool


def parse_size(spec: str) -> tuple[int | None, int | None]:
    m = re.search(r"(\d+)\s*[×x]\s*(\d+)", spec)
    if not m:
        return None, None
    return int(m.group(1)), int(m.group(2))


def parse_prompts_md(
    text: str,
    section: str,
    prompt_index: int,
) -> list[ArtJob]:
    start_pat, end_pat = SECTION_MARKERS[section]
    start = re.search(start_pat, text)
    if not start:
        raise SystemExit(f"Section start not found: {section}")
    end = re.search(end_pat, text[start.end() :])
    chunk = text[start.end() : start.end() + end.start()] if end else text[start.end() :]

    jobs: list[ArtJob] = []
    blocks = re.split(r"\n### `", chunk)
    for raw in blocks:
        raw = raw.strip()
        if not raw or not raw.startswith(("card-", "sym-", "arch-", "mode-", "bg-", "curse-", "comp-", "realm-", "item-", "map-", "region-", "marker-", "icon")):
            # first split piece may be intro prose
            if "`" not in raw[:80]:
                continue
        if not raw.endswith("`") and "\n" in raw:
            # restore name: first line is `name`\n...
            pass
        # normalize: ensure leading name line
        if not raw.startswith("`"):
            raw = "`" + raw
        m_name = re.match(r"`([^`]+)`", raw)
        if not m_name:
            continue
        name = m_name.group(1).strip()
        # only image assets (skip accidental)
        if not re.search(r"\.(webp|png)$", name):
            continue

        def meta(key: str) -> str:
            mm = re.search(rf"-\s+\*\*{key}\*\*：(.+)", raw)
            return mm.group(1).strip() if mm else ""

        where = meta("用在")
        content = meta("内容")
        spec = meta("规格")
        accent = meta("辅色")
        prompts = re.findall(r"\*\*Prompt\s+(\d+)\*\*\s*\n\s*```\n(.*?)```", raw, re.S)
        by_idx = {int(i): body.strip() for i, body in prompts}
        if prompt_index not in by_idx:
            print(f"[skip] {name}: no Prompt {prompt_index}", file=sys.stderr)
            continue
        w, h = parse_size(spec)
        transparent = "透明" in spec
        jobs.append(
            ArtJob(
                name=name,
                where=where,
                content=content,
                spec=spec,
                accent=accent,
                prompt=by_idx[prompt_index],
                width=w,
                height=h,
                transparent=transparent,
            )
        )
    return jobs


def stem_match(name: str, only: Iterable[str] | None) -> bool:
    if not only:
        return True
    stem = Path(name).stem
    return any(stem == o or name == o or stem.startswith(o) for o in only)


async def connect_browser(port: int) -> Browser:
    pw = await async_playwright().start()
    browser = await pw.chromium.connect_over_cdp(f"http://127.0.0.1:{port}")
    # keep playwright on browser object for later stop
    browser._fq_pw = pw  # type: ignore[attr-defined]
    return browser


async def close_browser(browser: Browser) -> None:
    pw = getattr(browser, "_fq_pw", None)
    try:
        await browser.close()
    except Exception:
        pass
    if pw:
        await pw.stop()


async def get_chatgpt_page(browser: Browser) -> Page:
    contexts = browser.contexts
    if not contexts:
        raise SystemExit("No browser contexts. Is Chrome running with --remote-debugging-port?")
    ctx = contexts[0]
    for page in ctx.pages:
        url = page.url or ""
        if "chatgpt.com" in url or "chat.openai.com" in url:
            await page.bring_to_front()
            return page
    page = await ctx.new_page()
    await page.goto("https://chatgpt.com/", wait_until="domcontentloaded", timeout=120_000)
    return page


async def is_login_wall(page: Page) -> bool:
    selectors = [
        "#modal-no-auth-login",
        "[data-testid='modal-no-auth-login']",
        "a[href*='auth.openai.com']",
        "button:has-text('Log in')",
        "button:has-text('登录')",
    ]
    for sel in selectors:
        loc = page.locator(sel)
        try:
            if await loc.count() and await loc.first.is_visible():
                return True
        except Exception:
            continue
    return False


async def ensure_logged_in(page: Page, wait: bool, wait_ms: int) -> None:
    deadline = time.monotonic() + wait_ms / 1000
    while True:
        if await is_login_wall(page):
            if not wait:
                raise SystemExit(
                    "ChatGPT is not logged in (login modal visible).\n"
                    "In the debug Chrome window, log in to https://chatgpt.com/,\n"
                    "then re-run with the same command (or pass --wait-login)."
                )
            left = int(deadline - time.monotonic())
            if left <= 0:
                raise SystemExit("Timed out waiting for ChatGPT login.")
            print(f"Waiting for login in debug Chrome… ({left}s left)", flush=True)
            await page.wait_for_timeout(3000)
            continue

        if await page.locator(
            "#prompt-textarea, [data-testid='composer-text-input'], div[contenteditable='true']"
        ).count():
            # Composer present and no login wall
            if not await is_login_wall(page):
                return

        if not wait:
            raise SystemExit(
                "Could not find ChatGPT composer. UI may have changed or page not ready."
            )
        if time.monotonic() >= deadline:
            raise SystemExit("Timed out waiting for ChatGPT composer / login.")
        await page.wait_for_timeout(1000)


async def find_composer(page: Page):
    selectors = [
        "#prompt-textarea",
        "[data-testid='composer-text-input']",
        "div[contenteditable='true']#prompt-textarea",
        "form div[contenteditable='true']",
        "div[contenteditable='true']",
    ]
    for sel in selectors:
        loc = page.locator(sel).first
        if await loc.count():
            return loc
    raise SystemExit("Composer not found.")


async def click_send(page: Page) -> None:
    candidates = [
        page.locator("[data-testid='send-button']"),
        page.locator("button[aria-label*='Send' i]"),
        page.locator("button[data-testid='composer-send-button']"),
        page.get_by_role("button", name=re.compile(r"^Send$", re.I)),
    ]
    for loc in candidates:
        if await loc.count():
            btn = loc.first
            try:
                if await btn.is_enabled():
                    await btn.click()
                    return
            except Exception:
                continue
    # fallback: Enter in composer
    composer = await find_composer(page)
    await composer.press("Enter")


async def open_fresh_chat(page: Page) -> None:
    """Navigate to a clean chat so we never pick up an older generated image."""
    await page.goto("https://chatgpt.com/", wait_until="domcontentloaded", timeout=120_000)
    await page.wait_for_timeout(1200)
    if await is_login_wall(page):
        raise RuntimeError("Login modal appeared after opening a new chat.")


async def submit_prompt(page: Page, text: str, new_chat: bool) -> None:
    if await is_login_wall(page):
        raise RuntimeError("Login modal still open; cannot submit.")

    if new_chat:
        await open_fresh_chat(page)

    composer = await find_composer(page)
    await composer.click(force=True)
    filled = await page.evaluate(
        """(payload) => {
          const el = document.querySelector('#prompt-textarea') ||
                     document.querySelector('[data-testid="composer-text-input"]') ||
                     document.querySelector('div[contenteditable="true"]');
          if (!el) return false;
          el.focus();
          document.execCommand('selectAll', false, null);
          document.execCommand('delete', false, null);
          const ok = document.execCommand('insertText', false, payload);
          if (!ok) {
            el.textContent = payload;
            el.dispatchEvent(new InputEvent('input', { bubbles: true }));
          }
          return true;
        }""",
        text,
    )
    if not filled:
        try:
            await composer.fill(text)
        except Exception:
            await composer.press_sequentially(text, delay=1)
    await page.wait_for_timeout(400)
    await click_send(page)


RATE_LIMIT_MARKERS = (
    "Too many requests",
    "making requests too quickly",
    "temporarily limited",
    "rate limit",
    "You've reached",
    "Try again later",
    "请稍后再试",
    "次数",
)


async def detect_rate_limit(page: Page) -> str | None:
    """Detect a *visible* rate-limit modal/toast — not historical chat text."""
    # Prefer visible dialog / alert nodes
    hit = await page.evaluate(
        """(markers) => {
          const isVis = (el) => {
            if (!el) return false;
            const s = getComputedStyle(el);
            if (s.display === 'none' || s.visibility === 'hidden' || s.opacity === '0') return false;
            const r = el.getBoundingClientRect();
            return r.width > 40 && r.height > 20;
          };
          const roots = [
            ...document.querySelectorAll('[role="dialog"], [role="alertdialog"], [role="alert"], [data-testid*="modal"], [class*="toast"], [class*="Toast"]'),
            ...document.querySelectorAll('div[class*="modal"], div[class*="Modal"]'),
          ];
          for (const el of roots) {
            if (!isVis(el)) continue;
            const t = (el.innerText || '').trim();
            if (!t) continue;
            const low = t.toLowerCase();
            for (const m of markers) {
              if (low.includes(m.toLowerCase())) return m;
            }
          }
          // Fallback: short scan of fixed/sticky overlays only
          for (const el of document.querySelectorAll('body *')) {
            const s = getComputedStyle(el);
            if (s.position !== 'fixed' && s.position !== 'sticky') continue;
            if (!isVis(el)) continue;
            const t = (el.innerText || '').slice(0, 500).toLowerCase();
            for (const m of markers) {
              if (t.includes(m.toLowerCase())) return m;
            }
          }
          return null;
        }""",
        list(RATE_LIMIT_MARKERS),
    )
    return hit or None


async def safe_detect_rate_limit(page: Page) -> str | None:
    try:
        return await detect_rate_limit(page)
    except Exception:
        return None


async def _cooldown_sleep(page: Page, pause_ms: int) -> None:
    """Sleep in short chunks (CDP dies on multi-minute page.wait_for_timeout)."""
    remaining = max(0, pause_ms) / 1000
    chunk = 30.0
    while remaining > 0:
        wait = min(chunk, remaining)
        await asyncio.sleep(wait)
        remaining -= wait
        try:
            await page.evaluate("() => 1")
        except Exception:
            pass
        if int(remaining) % 120 < chunk:
            print(f"    … cooldown {int(remaining)}s left", flush=True)


async def wait_out_rate_limit(page: Page, pause_ms: int = 300_000) -> None:
    """If ChatGPT shows a rate-limit modal, wait and dismiss, then continue."""
    hit = await detect_rate_limit(page)
    if not hit:
        return
    print(f"    rate-limit detected ({hit!r}); waiting {pause_ms // 1000}s …", flush=True)
    # Try dismiss
    for label in ("Got it", "OK", "Dismiss", "Close", "知道了"):
        loc = page.get_by_role("button", name=label)
        if await loc.count():
            try:
                await loc.first.click(timeout=2000)
            except Exception:
                pass
    await _cooldown_sleep(page, pause_ms)
    # Refresh to a clean chat after cooldown
    try:
        await open_fresh_chat(page)
    except Exception:
        try:
            await page.goto("https://chatgpt.com/", wait_until="domcontentloaded", timeout=120_000)
            await page.wait_for_timeout(2000)
        except Exception as e:
            print(f"    post-cooldown navigation failed: {e}", flush=True)
    # Keep waiting if still limited
    for _ in range(6):
        try:
            hit = await detect_rate_limit(page)
        except Exception:
            hit = "page-error"
        if not hit:
            return
        print(f"    still rate-limited ({hit!r}); waiting another {pause_ms // 1000}s …", flush=True)
        await _cooldown_sleep(page, pause_ms)
        try:
            await open_fresh_chat(page)
        except Exception:
            pass


async def generation_in_progress(page: Page) -> bool:
    return bool(
        await page.locator(
            'button[aria-label*="Stop" i], [data-testid="stop-button"], button:has-text("Stop")'
        ).count()
    )


async def page_image_candidates(page: Page) -> list[tuple[str, float]]:
    """Large generated images anywhere in main (ChatGPT image UI may omit assistant role)."""
    return await page.evaluate(
        """() => {
          const root = document.querySelector('main') || document.body;
          const out = [];
          for (const img of root.querySelectorAll('img')) {
            const src = img.currentSrc || img.src || '';
            if (!src || src.startsWith('data:image/svg')) continue;
            if (src.includes('avatar') || src.includes('/icon')) continue;
            const r = img.getBoundingClientRect();
            const w = Math.max(r.width || 0, img.naturalWidth || 0);
            const h = Math.max(r.height || 0, img.naturalHeight || 0);
            // Prefer estuary/file CDN assets; also accept large bitmaps
            const looksGen = src.includes('estuary/content')
              || src.includes('oaiusercontent.com')
              || src.includes('oaidalle')
              || src.includes('/backend-api/')
              || src.startsWith('blob:');
            if (!looksGen && (w < 200 || h < 200)) continue;
            if (w < 120 || h < 120) continue;
            out.push([src, w * h]);
          }
          out.sort((a, b) => b[1] - a[1]);
          // unique srcs
          const seen = new Set();
          const uniq = [];
          for (const [src, area] of out) {
            if (seen.has(src)) continue;
            seen.add(src);
            uniq.push([src, area]);
          }
          return uniq;
        }"""
    )


async def wait_for_new_image(page: Page, prev_srcs: set[str], timeout_ms: int) -> str:
    deadline = time.monotonic() + timeout_ms / 1000
    last_err = ""
    stable_src: str | None = None
    stable_hits = 0
    while time.monotonic() < deadline:
        limited = await detect_rate_limit(page)
        if limited:
            raise RuntimeError(f"rate-limited: {limited}")

        busy = await generation_in_progress(page)
        cands = await page_image_candidates(page)
        for src, _area in cands:
            if not src or src in prev_srcs:
                continue
            if src == stable_src:
                stable_hits += 1
            else:
                stable_src = src
                stable_hits = 1
            if stable_hits >= 2 and (not busy or stable_hits >= 4):
                return src

        await page.wait_for_timeout(1500)
    raise TimeoutError(last_err or "Timed out waiting for generated image")


async def collect_image_srcs(page: Page) -> set[str]:
    srcs: set[str] = set()
    for src, _ in await page_image_candidates(page):
        srcs.add(src)
    raw = await page.evaluate(
        """() => [...document.querySelectorAll('img')].map(i => i.currentSrc || i.src).filter(Boolean)"""
    )
    srcs.update(raw or [])
    return srcs

async def fetch_image_bytes(page: Page, src: str) -> bytes:
    import base64

    if src.startswith("blob:") or src.startswith("filesystem:"):
        b64 = await page.evaluate(
            """async (url) => {
              const res = await fetch(url);
              const buf = await res.arrayBuffer();
              const bytes = new Uint8Array(buf);
              let binary = '';
              for (let i = 0; i < bytes.length; i++) binary += String.fromCharCode(bytes[i]);
              return btoa(binary);
            }""",
            src,
        )
        return base64.b64decode(b64)

    try:
        resp = await page.context.request.get(src)
        if resp.ok:
            return await resp.body()
    except Exception:
        pass

    b64 = await page.evaluate(
        """async (url) => {
          const res = await fetch(url, { credentials: 'include' });
          const buf = await res.arrayBuffer();
          const bytes = new Uint8Array(buf);
          let binary = '';
          for (let i = 0; i < bytes.length; i++) binary += String.fromCharCode(bytes[i]);
          return btoa(binary);
        }""",
        src,
    )
    return base64.b64decode(b64)


def file_md5(path: Path) -> str:
    return hashlib.md5(path.read_bytes()).hexdigest()


def existing_art_hashes(art_dir: Path) -> dict[str, str]:
    """md5 -> filename for existing assets (detect accidental duplicates)."""
    out: dict[str, str] = {}
    for p in art_dir.glob("*"):
        if p.suffix.lower() not in {".webp", ".png"}:
            continue
        if not p.is_file() or p.stat().st_size == 0:
            continue
        out[file_md5(p)] = p.name
    return out


def to_webp(raw: bytes, job: ArtJob, quality: int = 90) -> bytes:
    im = Image.open(io.BytesIO(raw))
    if job.transparent:
        im = im.convert("RGBA")
    else:
        if im.mode in ("RGBA", "LA"):
            bg = Image.new("RGB", im.size, (13, 20, 17))  # forest ink-ish
            bg.paste(im, mask=im.split()[-1])
            im = bg
        else:
            im = im.convert("RGB")

    if job.width and job.height:
        # Fit inside target, then pad/crop to exact if close; prefer contain+center pad
        im.thumbnail((job.width, job.height), Image.Resampling.LANCZOS)
        canvas_mode = "RGBA" if job.transparent else "RGB"
        canvas_color = (0, 0, 0, 0) if job.transparent else (13, 20, 17)
        canvas = Image.new(canvas_mode, (job.width, job.height), canvas_color)
        x = (job.width - im.width) // 2
        y = (job.height - im.height) // 2
        if im.mode == "RGBA" and canvas_mode == "RGBA":
            canvas.paste(im, (x, y), im)
        else:
            canvas.paste(im, (x, y))
        im = canvas

    out = io.BytesIO()
    save_kw = {"format": "WEBP", "quality": quality, "method": 6}
    if job.transparent:
        save_kw["lossless"] = False
    im.save(out, **save_kw)
    return out.getvalue()


def build_message(job: ArtJob) -> str:
    """Compose the ChatGPT submission. English only — never append Chinese metadata."""
    size_hint = ""
    if job.width and job.height:
        size_hint = f" Target pixel size approximately {job.width}x{job.height}."
    alpha = " Transparent background." if job.transparent else " Opaque full-bleed background."
    # job.prompt from ART_PROMPTS.md is already English; do not append 用在/内容/辅色.
    message = (
        IMAGE_PREFIX
        + f"Asset filename intent: {job.name}."
        + size_hint
        + alpha
        + "\n\n"
        + job.prompt
    )
    if _CJK_RE.search(message):
        raise RuntimeError(
            f"Chinese characters found in prompt for {job.name}; refusing to submit."
        )
    return message


async def run_jobs(args: argparse.Namespace) -> int:
    prompts_path = Path(args.prompts_file)
    if not prompts_path.is_file():
        prompts_path = ART_DIR / Path(args.prompts_file).name
    text = prompts_path.read_text(encoding="utf-8")
    jobs = parse_prompts_md(text, args.section, args.prompt_index)
    only = set(args.only) if args.only else None
    jobs = [j for j in jobs if stem_match(j.name, only)]
    if args.limit is not None:
        jobs = jobs[: args.limit]

    if not jobs:
        print("No jobs matched.", file=sys.stderr)
        return 1

    print(f"Jobs: {len(jobs)} (section={args.section}, prompt={args.prompt_index})")
    for j in jobs:
        print(f"  - {j.name}  [{j.spec}]")

    if args.dry_run:
        print("Dry run — not connecting to Chrome.")
        return 0

    ART_DIR.mkdir(parents=True, exist_ok=True)
    browser = await connect_browser(args.port)
    try:
        page = await get_chatgpt_page(browser)
        await ensure_logged_in(page, wait=args.wait_login, wait_ms=args.wait_login_ms)

        known_hashes = existing_art_hashes(ART_DIR)
        ok = 0
        fail = 0
        for idx, job in enumerate(jobs, 1):
            out_path = ART_DIR / job.name
            if out_path.suffix.lower() == ".png":
                target = out_path
            else:
                target = out_path.with_suffix(".webp")
                if job.name.endswith(".png"):
                    target = ART_DIR / job.name

            if args.skip_existing and target.exists() and target.stat().st_size > 0:
                print(f"[{idx}/{len(jobs)}] skip existing {target.name}")
                ok += 1
                continue

            print(f"[{idx}/{len(jobs)}] generating {job.name} …")
            message = build_message(job)
            success = False
            last_err: Exception | None = None
            for attempt in range(1, args.retries + 1):
                try:
                    await wait_out_rate_limit(page, pause_ms=args.rate_limit_ms)
                    await open_fresh_chat(page)
                    await wait_out_rate_limit(page, pause_ms=args.rate_limit_ms)
                    prev = await collect_image_srcs(page)
                    await submit_prompt(page, message, new_chat=False)
                    src = await wait_for_new_image(page, prev, timeout_ms=args.timeout_ms)
                    raw = await fetch_image_bytes(page, src)
                    if target.suffix.lower() == ".webp":
                        data = to_webp(raw, job, quality=args.quality)
                    else:
                        data = raw
                        if job.width and job.height:
                            im = Image.open(io.BytesIO(raw)).convert("RGBA")
                            im = im.resize((job.width, job.height), Image.Resampling.LANCZOS)
                            buf = io.BytesIO()
                            im.save(buf, format="PNG")
                            data = buf.getvalue()
                    digest = hashlib.md5(data).hexdigest()
                    other = known_hashes.get(digest)
                    if other and other != target.name:
                        raise RuntimeError(
                            f"duplicate image hash of existing {other}; retrying"
                        )
                    target.write_bytes(data)
                    known_hashes[digest] = target.name
                    print(
                        f"    saved {target} ({len(data)} bytes, md5={digest[:8]}) "
                        f"from {urlparse(src).netloc or src[:32]} [try {attempt}]"
                    )
                    success = True
                    ok += 1
                    break
                except Exception as e:
                    last_err = e
                    print(f"    retry {attempt}/{args.retries}: {e}", file=sys.stderr)
                    if "rate-limited" in str(e).lower() or await safe_detect_rate_limit(page):
                        await wait_out_rate_limit(page, pause_ms=args.rate_limit_ms)
                    else:
                        await page.wait_for_timeout(2000)
            if not success:
                fail += 1
                print(f"    FAIL {job.name}: {last_err}", file=sys.stderr)
                if args.stop_on_error:
                    break
            await page.wait_for_timeout(args.pause_ms)

        print(json.dumps({"ok": ok, "fail": fail, "total": len(jobs)}))
        return 0 if fail == 0 else 2
    finally:
        pw = getattr(browser, "_fq_pw", None)
        try:
            await browser.close()
        except Exception:
            pass
        if pw:
            await pw.stop()


def main() -> None:
    ap = argparse.ArgumentParser(description="Generate fatequest art via ChatGPT CDP")
    ap.add_argument("--port", type=int, default=9222)
    ap.add_argument(
        "--prompts-file",
        default="ART_PROMPTS.md",
        help="Prompt markdown under assets/art/ (ART_PROMPTS.md or ART_PROMPTS_UI.md)",
    )
    ap.add_argument(
        "--batch",
        action="store_true",
        help="Batch mode: one contact sheet per ## Batch section (10-up)",
    )
    ap.add_argument("--section", choices=["P0", "P1", "P2", "ALL"], default="P0")
    ap.add_argument("--prompt-index", type=int, default=1)
    ap.add_argument("--only", nargs="*", help="Filter by stem/filename or batch title")
    ap.add_argument("--limit", type=int, default=None)
    ap.add_argument("--skip-existing", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--new-chat", action="store_true", help="(always on) kept for CLI compat")
    ap.add_argument("--timeout-ms", type=int, default=180_000)
    ap.add_argument("--pause-ms", type=int, default=15_000)
    ap.add_argument("--quality", type=int, default=90)
    ap.add_argument("--retries", type=int, default=4)
    ap.add_argument(
        "--rate-limit-ms",
        type=int,
        default=600_000,
        help="Cooldown when ChatGPT shows Too many requests (default 10 min)",
    )
    ap.add_argument("--stop-on-error", action="store_true")
    ap.add_argument(
        "--wait-login",
        action="store_true",
        help="Poll until ChatGPT login modal is gone (log in in the debug Chrome window)",
    )
    ap.add_argument("--wait-login-ms", type=int, default=600_000)
    args = ap.parse_args()
    if args.batch:
        raise SystemExit(asyncio.run(run_batch_jobs(args)))
    raise SystemExit(asyncio.run(run_jobs(args)))


if __name__ == "__main__":
    main()
