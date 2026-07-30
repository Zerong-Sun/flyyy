#!/usr/bin/env python3
"""
Simple batch art generator — one batch at a time.
Usage: .venv/bin/python gen_batches.py --port 9222 --start I2
"""
from __future__ import annotations

import argparse
import asyncio
import sys
import time
from pathlib import Path

from batch_art_utils import (
    ART_DIR,
    parse_batch_prompts_md,
    split_contact_sheet,
    save_cell_webp,
)
from chatgpt_gen_art import (
    build_batch_message,
    connect_browser,
    ensure_logged_in,
    fetch_image_bytes,
    get_chatgpt_page,
    new_images_dom_order,
    collect_image_srcs,
    safe_detect_rate_limit,
    submit_prompt,
)
from resume_dual_decks import ensure_chat, generation_busy

SHEETS_DIR = ART_DIR / "_sheets"


async def harvest_one_batch(page, job) -> bool:
    """Download the latest images and save/crop them. Returns True on success."""
    prev = await collect_image_srcs(page)
    print("  waiting for generation to finish...", flush=True)
    deadline = time.monotonic() + 600
    while time.monotonic() < deadline:
        busy = await generation_busy(page)
        if not busy:
            print("  generation complete", flush=True)
            break
        await asyncio.sleep(10)

    found = await new_images_dom_order(page, prev)
    if not found:
        found = await new_images_dom_order(page, set())
    if not found:
        print("  no images found!", flush=True)
        return False

    print(f"  found {len(found)} image(s)", flush=True)

    raws = []
    for i, src in enumerate(found):
        print(f"  downloading [{i}]...", flush=True)
        raw = await fetch_image_bytes(page, src)
        raws.append(raw)

    out_dir = job.output_dir
    if job.mode == "sheet" and job.cols and job.rows:
        sheet_raw = raws[0]
        print(f"  cropping {job.cols}x{job.rows} contact sheet...", flush=True)
        cells = split_contact_sheet(sheet_raw, job, gutter_trim=True)
        print(f"  got {len(cells)} cells", flush=True)
        out_dir.mkdir(parents=True, exist_ok=True)
        for i, cell in enumerate(cells):
            bf = job.files[i]
            out_path = out_dir / bf.filename
            save_cell_webp(cell, out_path, transparent=job.transparent)
            print(f"    saved {bf.filename} ({cell.size[0]}x{cell.size[1]})", flush=True)
        return len(cells) > 0
    else:
        out_dir.mkdir(parents=True, exist_ok=True)
        saved = 0
        for i, raw in enumerate(raws):
            if i >= len(job.files):
                break
            bf = job.files[i]
            out_path = out_dir / bf.filename
            out_path.write_bytes(raw)
            print(f"    saved {bf.filename} ({len(raw)} bytes)", flush=True)
            saved += 1
        return saved > 0


async def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=9222)
    parser.add_argument("--prompts-file", default="ART_PROMPTS_REQ.md")
    parser.add_argument("--start", default="", help="Start from batch prefix e.g. I2, F1")
    parser.add_argument("--rate-limit-ms", type=int, default=120_000)
    args = parser.parse_args()

    text = Path("../../game/assets/art/ART_PROMPTS_REQ.md").read_text()
    all_jobs = parse_batch_prompts_md(text, "ART_PROMPTS_REQ.md")

    if args.start:
        skip = True
        jobs = []
        for j in all_jobs:
            if args.start in j.name:
                skip = False
            if not skip:
                jobs.append(j)
    else:
        jobs = all_jobs

    window_order = {"I": 0, "F": 1, "P": 2, "C": 3, "B": 4, "A": 5}
    jobs.sort(key=lambda j: (window_order.get(j.name[0], 99), j.name))

    print(f"Total batches: {len(jobs)}")
    for j in jobs:
        n = len(j.files)
        mode = f"{j.cols}x{j.rows} sheet" if j.mode == "sheet" else "separate"
        print(f"  {j.name}: {n} files, {mode}, -> {j.output_dir}")

    browser = await connect_browser(args.port)
    try:
        page = await get_chatgpt_page(browser)
        await ensure_logged_in(page, wait=True, wait_ms=30_000)
        # Don't wait for rate-limit at startup — handle per-batch

        ok = 0
        fail = 0
        for idx, job in enumerate(jobs, 1):
            all_exist = True
            missing = []
            for bf in job.files:
                if not (job.output_dir / bf.filename).exists():
                    all_exist = False
                    missing.append(bf.filename)

            if all_exist:
                print(f"\n[{idx}/{len(jobs)}] {job.name}: all {len(job.files)} exist, skip")
                ok += 1
                continue

            print(f"\n[{idx}/{len(jobs)}] {job.name}: {len(missing)}/{len(job.files)} missing")
            print(f"  first missing: {missing[0] if missing else 'none'}")

            # Rate-limit check before each batch
            try:
                limited = await safe_detect_rate_limit(page)
                if limited:
                    print(f"  rate-limit: {limited}; cooldown 300s...", flush=True)
                    await asyncio.sleep(300)
            except Exception:
                pass

            new_page = await browser.contexts[0].new_page()
            try:
                await ensure_chat(new_page, "https://chatgpt.com/")

                message = build_batch_message(job)
                print(f"  submitting prompt ({len(message)} chars)...", flush=True)
                await submit_prompt(new_page, message, new_chat=False)

                success = await harvest_one_batch(new_page, job)
                if success:
                    print(f"  OK", flush=True)
                    ok += 1
                else:
                    print(f"  FAIL - no images harvested", flush=True)
                    fail += 1

            except Exception as e:
                print(f"  ERROR: {e}", flush=True)
                fail += 1
            finally:
                try:
                    await new_page.close()
                except Exception:
                    pass

            # Brief cooldown between batches to avoid rate-limit
            if idx < len(jobs):
                print(f"  cooldown 60s...", flush=True)
                await asyncio.sleep(60)

        print(f"\n=== Done: {ok} ok, {fail} fail ===")
        return 0 if fail == 0 else 1
    finally:
        pass


if __name__ == "__main__":
    asyncio.run(main())
