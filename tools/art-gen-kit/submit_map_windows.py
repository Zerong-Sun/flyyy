#!/usr/bin/env python3
"""
Submit ART_PROMPTS_MAP.md: one ChatGPT browser tab/window per category (Window A–G).
Within a window, reuse the same chat for sequential batches (no fresh chat per batch).

Usage:
  .venv/bin/python gen_map_prompts.py
  .venv/bin/python submit_map_windows.py --skip-existing --poll-sec 180
  .venv/bin/python submit_map_windows.py --windows A B F1 --skip-existing   # P0 only
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
from collections import OrderedDict
from pathlib import Path

from PIL import Image

from batch_art_utils import (
    ART_DIR,
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
from chatgpt_gen_art import (
    batch_out_dir,
    collect_image_srcs,
    connect_browser,
    ensure_logged_in,
    fetch_image_bytes,
    open_fresh_chat,
    resize_to_spec,
    safe_detect_rate_limit,
    submit_prompt,
    wait_for_new_images,
    wait_out_rate_limit,
)

MAP_STYLE = (
    "13th-century manuscript map (mappa mundi / portolan) hand-drawn feel — "
    "vellum #E9DBB8, iron-gall ink #4A3A1C, ochre #8A6234, rubric #B3402E, "
    "sea-teal #3F5F6B. Visible brush, wash, parchment grain. "
    "NO modern flat vector, NO photorealism, NO neon glow."
)

EMOJI_STYLE = (
    "Cloud-ridge Twilight manuscript UI icons — forest ink #0D1411, parchment #F0E4D0, "
    "antique gold #BDA476, rubric #B3402E accent only, mist blue #7FA3BD. "
    "Flat mineral paint, thick gold contour, single centered subject, readable at 64px. "
    "Transparent background. NO photorealism, NO neon, NO text, NO deities."
)

_CJK_RE = re.compile(r"[\u4e00-\u9fff]")
SKIP_NAMES = {"_pad-blank.webp"}

# Prefer P0 first when submitting all
WINDOW_ORDER = [
    "A", "B", "F1", "C", "D", "E", "F2", "F", "G",
    # emoji icon windows
    "Nav", "Status", "DreamA", "DreamB", "Ritual", "Place",
    "Travel", "Tower", "TrumpA", "TrumpB", "TrumpC", "Misc", "Creature", "Extra", "Extra2",
]


def style_for(prompts_file: str, override: str | None) -> str:
    if override and override != "auto":
        return EMOJI_STYLE if override == "emoji" else MAP_STYLE
    name = Path(prompts_file).name.upper()
    if "EMOJI" in name:
        return EMOJI_STYLE
    return MAP_STYLE


def build_map_message(job: BatchJob, style: str) -> str:
    # Keep pad in sheet grid so cols×rows still matches; only skip on save
    listing_files = job.files
    listing = "\n".join(
        f"{i + 1}. {bf.filename}: {bf.description}"
        if bf.description
        else f"{i + 1}. {bf.filename}"
        for i, bf in enumerate(listing_files)
    )
    alpha = (
        "Transparent background."
        if job.transparent
        else "Opaque full-bleed / parchment background."
    )
    if job.mode == "separate":
        n = len(listing_files)
        message = (
            f"Generate exactly {n} SEPARATE image(s) in ONE response "
            f"(NOT a contact sheet). Do not write an explanation. {alpha}\n\n"
            f"{style}\n\n"
            f"Image order 1→{n}:\n{listing}\n\n"
            f"{job.prompt}\n\n"
            "Negative: photorealistic, 3D, neon, watermark, text labels, filenames on image."
        )
    else:
        message = (
            f"Generate exactly ONE {job.cols}×{job.rows} contact-sheet image. "
            f"Do not write an explanation. Thin dark gutters between cells. {alpha}\n\n"
            f"{style}\n\n"
            f"Each cell roughly {job.cell_w}×{job.cell_h}. "
            f"Cell order left-to-right, top-to-bottom:\n{listing}\n\n"
            f"{job.prompt}\n\n"
            "Negative: photorealistic, 3D, neon, watermark, text labels, filenames on image."
        )
    if _CJK_RE.search(message):
        raise RuntimeError(f"CJK found in batch {job.name}; refusing to submit.")
    return message


def group_by_window(batches: list[BatchJob]) -> OrderedDict[str, list[BatchJob]]:
    groups: OrderedDict[str, list[BatchJob]] = OrderedDict()
    # Sort by WINDOW_ORDER then preserve batch order within
    by_win: dict[str, list[BatchJob]] = {}
    for b in batches:
        w = b.window or "X"
        by_win.setdefault(w, []).append(b)
    for w in WINDOW_ORDER:
        if w in by_win:
            groups[w] = by_win.pop(w)
    for w, jobs in by_win.items():
        groups[w] = jobs
    return groups


def missing_files(batch: BatchJob) -> list:
    out_dir = batch_out_dir(batch)
    miss = []
    for bf in batch.files:
        if bf.filename in SKIP_NAMES:
            continue
        p = out_dir / bf.filename
        if not p.exists() or p.stat().st_size == 0:
            miss.append(bf)
    return miss


async def open_window_page(browser, label: str):
    """Open a dedicated ChatGPT tab for this category window."""
    ctx = browser.contexts[0]
    page = await ctx.new_page()
    await page.goto("https://chatgpt.com/", wait_until="domcontentloaded", timeout=120_000)
    await page.wait_for_timeout(1500)
    print(f"  [window {label}] opened tab {page.url}", flush=True)
    return page


async def save_batch(
    page, batch: BatchJob, prev: set[str], quality: int, known_hashes: dict, prompts_stem: str = "ART_PROMPTS_MAP"
) -> int:
    out_dir = batch_out_dir(batch)
    out_dir.mkdir(parents=True, exist_ok=True)
    SHEETS_DIR.mkdir(parents=True, exist_ok=True)
    n = len(batch.files)

    if batch.mode == "separate":
        timeout = max(300_000, 90_000 * n)
        srcs = await wait_for_new_images(page, prev, timeout_ms=timeout, max_n=n, min_n=1)
        saved = 0
        for i, (bf, src) in enumerate(zip(batch.files, srcs)):
            if bf.filename in SKIP_NAMES:
                continue
            target = out_dir / bf.filename
            if target.exists() and target.stat().st_size > 0:
                saved += 1
                continue
            raw = await fetch_image_bytes(page, src)
            cell = resize_to_spec(raw, bf, batch.transparent)
            data = image_to_webp_bytes(cell, batch.transparent, quality, bf.description)
            digest = hashlib.md5(data).hexdigest()
            other = known_hashes.get(digest)
            if other and other != target.name:
                raise RuntimeError(f"duplicate hash of {other} for {target.name}")
            target.write_bytes(data)
            known_hashes[digest] = target.name
            print(
                f"    [{i+1}/{n}] saved {target.name} ({bf.out_w}×{bf.out_h}, "
                f"{len(data)} bytes)",
                flush=True,
            )
            saved += 1
        return saved

    srcs = await wait_for_new_images(page, prev, timeout_ms=600_000, max_n=3, min_n=1)
    raw = await fetch_image_bytes(page, srcs[0])
    sheet_path = sheet_path_for(batch, prompts_stem)
    sheet_path.write_bytes(raw)
    print(f"    sheet saved {sheet_path.name}", flush=True)
    cells = split_contact_sheet(raw, batch)
    saved = 0
    for bf, cell in zip(batch.files, cells):
        if bf.filename in SKIP_NAMES:
            continue
        target = out_dir / bf.filename
        if target.exists() and target.stat().st_size > 0:
            saved += 1
            continue
        if bf.out_w and bf.out_h and (cell.width != bf.out_w or cell.height != bf.out_h):
            cell = cell.resize((bf.out_w, bf.out_h), Image.Resampling.LANCZOS)
        data = image_to_webp_bytes(cell, batch.transparent, quality, bf.description)
        digest = hashlib.md5(data).hexdigest()
        other = known_hashes.get(digest)
        if other and other != target.name:
            raise RuntimeError(f"duplicate hash of {other} for {target.name}")
        target.write_bytes(data)
        known_hashes[digest] = target.name
        print(
            f"    saved {target.name} ({bf.out_w}×{bf.out_h}, {len(data)} bytes)",
            flush=True,
        )
        saved += 1
    return saved


async def run_window(
    page,
    label: str,
    batches: list[BatchJob],
    *,
    skip_existing: bool,
    retries: int,
    rate_limit_ms: int,
    pause_ms: int,
    poll_sec: int,
    quality: int,
    known_hashes: dict,
    style: str,
    reuse_chat: bool = False,
    prompts_stem: str = "ART_PROMPTS_MAP",
) -> tuple[int, int]:
    ok = fail = 0
    first = not reuse_chat
    for bidx, batch in enumerate(batches, 1):
        miss = missing_files(batch)
        if skip_existing and not miss:
            print(f"  [window {label}] skip {batch.name} (all exist)", flush=True)
            ok += len([f for f in batch.files if f.filename not in SKIP_NAMES])
            continue

        print(
            f"  [window {label}] batch {bidx}/{len(batches)} {batch.name} "
            f"({len(miss) or len(batch.files)} missing) …",
            flush=True,
        )
        message = build_map_message(batch, style)
        success = False
        last_err: Exception | None = None
        for attempt in range(1, retries + 1):
            try:
                await wait_out_rate_limit(page, pause_ms=rate_limit_ms)
                if first:
                    await open_fresh_chat(page)
                    first = False
                # stay in same chat for later batches in this window
                prev = await collect_image_srcs(page)
                await submit_prompt(page, message, new_chat=False)
                # give model time; poll via wait_for_new_images
                await page.wait_for_timeout(min(poll_sec, 30) * 1000)
                saved = await save_batch(
                    page, batch, prev, quality, known_hashes, prompts_stem=prompts_stem
                )
                need = len([f for f in batch.files if f.filename not in SKIP_NAMES])
                if skip_existing:
                    still = missing_files(batch)
                    if still:
                        raise RuntimeError(
                            f"still missing {len(still)}/{need}: "
                            + ", ".join(f.filename for f in still[:5])
                        )
                elif saved < need:
                    raise RuntimeError(f"only saved {saved}/{need}")
                success = True
                ok += need
                break
            except Exception as e:
                last_err = e
                print(f"    retry {attempt}/{retries}: {e}", file=sys.stderr, flush=True)
                if "rate-limited" in str(e).lower() or await safe_detect_rate_limit(page):
                    await wait_out_rate_limit(page, pause_ms=rate_limit_ms)
                    if not reuse_chat:
                        first = True  # new chat after rate limit
                else:
                    await page.wait_for_timeout(3000)
        if not success:
            fail += len(miss) or len(batch.files)
            print(f"    FAIL {batch.name}: {last_err}", file=sys.stderr, flush=True)
            if fail and False:
                pass
        await page.wait_for_timeout(pause_ms)
    return ok, fail


async def main_async(args: argparse.Namespace) -> int:
    prompts_path = ART_DIR / args.prompts_file
    if not prompts_path.exists():
        print(f"Missing {prompts_path}", file=sys.stderr)
        return 1
    batches = parse_batch_prompts_md(prompts_path.read_text(encoding="utf-8"), source=prompts_path.name)
    if args.windows:
        want = {w.upper() for w in args.windows}
        batches = [b for b in batches if (b.window or "").upper() in want]
    groups = group_by_window(batches)
    if not groups:
        print("No batches matched.", file=sys.stderr)
        return 1

    print("Windows to submit:")
    for w, jobs in groups.items():
        print(f"  {w}: {len(jobs)} batches — " + "; ".join(j.name for j in jobs))

    if args.dry_run:
        return 0

    browser = await connect_browser(args.port)
    known_hashes: dict[str, str] = {}
    for p in ART_DIR.glob("*.webp"):
        try:
            known_hashes[hashlib.md5(p.read_bytes()).hexdigest()] = p.name
        except Exception:
            pass

    total_ok = total_fail = 0
    pages = []
    try:
        # login check on first existing chatgpt page
        from chatgpt_gen_art import get_chatgpt_page

        login_page = await get_chatgpt_page(browser)
        await ensure_logged_in(login_page, wait=args.wait_login, wait_ms=args.wait_login_ms)
        await wait_out_rate_limit(login_page, pause_ms=args.rate_limit_ms)

        shared_page = None
        if args.chat_url:
            ctx = browser.contexts[0]
            shared_page = await ctx.new_page()
            print(f"Reusing chat {args.chat_url}", flush=True)
            await shared_page.goto(
                args.chat_url, wait_until="domcontentloaded", timeout=120_000
            )
            await shared_page.wait_for_timeout(2000)
            pages.append(shared_page)

        for label, jobs in groups.items():
            if shared_page is not None:
                page = shared_page
            else:
                page = await open_window_page(browser, label)
                pages.append(page)
            ok, fail = await run_window(
                page,
                label,
                jobs,
                skip_existing=args.skip_existing,
                retries=args.retries,
                rate_limit_ms=args.rate_limit_ms,
                pause_ms=args.pause_ms,
                poll_sec=args.poll_sec,
                quality=args.quality,
                known_hashes=known_hashes,
                style=style_for(args.prompts_file, args.style),
                reuse_chat=bool(args.chat_url),
                prompts_stem=Path(args.prompts_file).stem,
            )
            total_ok += ok
            total_fail += fail
            print(f"  [window {label}] done ok={ok} fail={fail}", flush=True)
            if fail and args.stop_on_error:
                break

        catalog = collect_catalog(ART_DIR)
        write_catalog(catalog)
        n = embed_catalog_descriptions(catalog, ART_DIR)
        print(f"ART_CATALOG.json updated ({catalog['count']} assets); EXIF in {n} file(s).")
        print(json.dumps({"ok": total_ok, "fail": total_fail, "windows": list(groups)}))
        return 0 if total_fail == 0 else 2
    finally:
        # leave tabs open for user inspection; only detach CDP
        pw = getattr(browser, "_fq_pw", None)
        try:
            await browser.close()
        except Exception:
            pass
        if pw:
            await pw.stop()


def main() -> None:
    ap = argparse.ArgumentParser(description="Submit map art prompts, one window per category")
    ap.add_argument("--port", type=int, default=9222)
    ap.add_argument("--prompts-file", default="ART_PROMPTS_MAP.md")
    ap.add_argument(
        "--style",
        choices=["auto", "map", "emoji"],
        default="auto",
        help="Style lock: auto picks from prompts filename",
    )
    ap.add_argument("--windows", nargs="*", help="Subset of window ids, e.g. A B F1")
    ap.add_argument(
        "--chat-url",
        default=None,
        help="Reuse one ChatGPT conversation URL (no fresh chat / no new tab per window)",
    )
    ap.add_argument("--skip-existing", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--retries", type=int, default=3)
    ap.add_argument("--pause-ms", type=int, default=20_000)
    ap.add_argument("--poll-sec", type=int, default=180)
    ap.add_argument("--rate-limit-ms", type=int, default=600_000)
    ap.add_argument("--quality", type=int, default=90)
    ap.add_argument("--stop-on-error", action="store_true")
    ap.add_argument("--wait-login", action="store_true")
    ap.add_argument("--wait-login-ms", type=int, default=600_000)
    args = ap.parse_args()
    raise SystemExit(asyncio.run(main_async(args)))


if __name__ == "__main__":
    main()
