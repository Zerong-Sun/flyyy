#!/usr/bin/env python3
"""
Harvest generated images from ChatGPT conversations (CDP attach).
Walks sidebar chats, maps images chronologically onto deck filenames,
saves .webp with EXIF descriptions.

Usage:
  .venv/bin/python harvest_chat_images.py --tarot-only --dry-run
  .venv/bin/python harvest_chat_images.py --tarot-only
  .venv/bin/python harvest_chat_images.py --iching-only
"""

from __future__ import annotations

import argparse
import asyncio
import hashlib
import json
import re
import sys
from pathlib import Path

from batch_art_utils import (
    ART_DIR,
    collect_catalog,
    embed_catalog_descriptions,
    image_to_webp_bytes,
    parse_batch_prompts_md,
    write_catalog,
)

sys.path.insert(0, str(Path(__file__).resolve().parent))
from chatgpt_gen_art import batch_out_dir, connect_browser, fetch_image_bytes, get_chatgpt_page, resize_to_spec


async def collect_images_on_page(page) -> list[dict]:
    return await page.evaluate(
        """() => {
          const main = document.querySelector('main') || document.body;
          const out = [];
          const seen = new Set();
          const isGen = (src) => src && (
            src.includes('estuary/content') || src.includes('oaiusercontent.com') ||
            src.includes('oaidalle') || src.includes('/backend-api/') || src.startsWith('blob:'));
          for (const img of main.querySelectorAll('img')) {
            const src = img.currentSrc || img.src || '';
            if (!src || seen.has(src) || src.startsWith('data:image/svg')) continue;
            if (src.includes('avatar') || src.includes('/icon')) continue;
            const w = Math.max(img.naturalWidth || 0, img.getBoundingClientRect().width || 0);
            const h = Math.max(img.naturalHeight || 0, img.getBoundingClientRect().height || 0);
            if (!isGen(src) && (w < 120 || h < 120)) continue;
            if (w < 80 || h < 80) continue;
            seen.add(src);
            out.push({ src, w, h });
          }
          return out;
        }"""
    )


async def list_chat_urls(page) -> list[str]:
    urls = await page.evaluate(
        """() => [...document.querySelectorAll('a[href*="/c/"]')]
          .map(a => a.href.split('?')[0])
          .filter((v, i, a) => a.indexOf(v) === i)"""
    )
    return urls or []


async def ensure_home(page) -> None:
    if "chatgpt.com" not in (page.url or ""):
        await page.goto("https://chatgpt.com/", wait_until="domcontentloaded", timeout=90_000)
        await page.wait_for_timeout(2000)


async def scan_chats(page, title_filter: re.Pattern | None, min_images: int = 2) -> list[dict]:
    """Return multi-image chats, newest-first (sidebar order)."""
    await ensure_home(page)
    urls = await list_chat_urls(page)
    if not urls:
        await page.goto("https://chatgpt.com/", wait_until="domcontentloaded", timeout=90_000)
        await page.wait_for_timeout(2500)
        urls = await list_chat_urls(page)
    print(f"  {len(urls)} chat URLs in sidebar", flush=True)

    chats: list[dict] = []
    for url in urls:
        try:
            await page.goto(url, wait_until="domcontentloaded", timeout=90_000)
            await page.wait_for_timeout(1800)
            for _ in range(5):
                await page.evaluate(
                    "() => { window.scrollTo(0,0); const m=document.querySelector('main'); if(m)m.scrollTop=0; }"
                )
                await page.wait_for_timeout(350)
            title = await page.title()
            if title_filter and not title_filter.search(title):
                continue
            imgs = await collect_images_on_page(page)
            if len(imgs) < min_images:
                print(f"  skip {len(imgs):2d} img | {title[:45]}", flush=True)
                continue
            chats.append({"url": url, "title": title, "images": imgs})
            print(f"  keep {len(imgs):2d} img | {title[:45]}", flush=True)
        except Exception as e:
            print(f"  skip {url}: {e}", file=sys.stderr, flush=True)
    return chats


def deck_file_slots(batches) -> list[tuple]:
    """Flatten batches → [(batch, BatchFile), ...] in deck order."""
    slots = []
    for batch in batches:
        for bf in batch.files:
            slots.append((batch, bf))
    return slots


async def download_assignments(page, assignments, force: bool, quality: int) -> int:
    saved = 0
    known: dict[str, str] = {}
    manifests: dict[str, list] = {}

    # Group by chat URL so we navigate once per chat
    by_url: dict[str, list] = {}
    for item in assignments:
        by_url.setdefault(item["url"], []).append(item)

    for url, items in by_url.items():
        print(f"Downloading from {items[0]['chat'][:40]}…", flush=True)
        try:
            await page.goto(url, wait_until="domcontentloaded", timeout=90_000)
            await page.wait_for_timeout(1500)
        except Exception as e:
            print(f"  navigate fail: {e}", file=sys.stderr)
            continue

        for item in items:
            batch, bf = item["batch"], item["bf"]
            out_dir = batch_out_dir(batch)
            out_dir.mkdir(parents=True, exist_ok=True)
            target = out_dir / bf.filename
            if not force and target.exists() and target.stat().st_size > 0:
                print(f"  skip {target.name}", flush=True)
                continue
            try:
                raw = await fetch_image_bytes(page, item["src"])
                cell = resize_to_spec(raw, bf, batch.transparent)
                data = image_to_webp_bytes(cell, batch.transparent, quality, bf.description)
                digest = hashlib.md5(data).hexdigest()
                if digest in known and known[digest] != bf.filename:
                    print(f"  WARN duplicate of {known[digest]} → {bf.filename}", file=sys.stderr)
                known[digest] = bf.filename
                target.write_bytes(data)
                print(f"  saved {target.name} ({bf.out_w}×{bf.out_h}, {len(data)}b)", flush=True)
                saved += 1
                key = str(out_dir)
                manifests.setdefault(key, []).append(
                    {
                        "file": bf.filename,
                        "batch": batch.name,
                        "description": bf.description,
                        "chat": item["chat"],
                        "source_url": item["src"][:120],
                    }
                )
            except Exception as e:
                print(f"  FAIL {bf.filename}: {e}", file=sys.stderr)

    for deck_path, entries in manifests.items():
        man = Path(deck_path) / "DECK_MANIFEST.json"
        existing = []
        if man.exists():
            try:
                existing = json.loads(man.read_text(encoding="utf-8"))
            except Exception:
                existing = []
        by_file = {e["file"]: e for e in existing}
        by_file.update({e["file"]: e for e in entries})
        man.write_text(
            json.dumps(sorted(by_file.values(), key=lambda x: x["file"]), ensure_ascii=False, indent=2)
            + "\n",
            encoding="utf-8",
        )
    return saved


async def run(args: argparse.Namespace) -> int:
    if args.iching_only:
        prompt_files = ["ART_PROMPTS_ICHING_DECK.md"]
        title_re = re.compile(r"i\s*ching|iching|hexagram", re.I)
    elif args.tarot_only or args.prompts_file.endswith("TAROT_DECK.md"):
        prompt_files = ["ART_PROMPTS_TAROT_DECK.md"]
        title_re = re.compile(r"tarot", re.I)
    elif args.all_decks:
        # run sequentially in caller; here default tarot then note
        prompt_files = ["ART_PROMPTS_TAROT_DECK.md"]
        title_re = re.compile(r"tarot", re.I)
    else:
        prompt_files = [args.prompts_file]
        title_re = None

    all_batches = []
    for pf in prompt_files:
        p = ART_DIR / Path(pf).name
        if not p.exists():
            print(f"Missing {p}", file=sys.stderr)
            return 1
        all_batches.extend(parse_batch_prompts_md(p.read_text(encoding="utf-8"), source=p.name))

    slots = deck_file_slots(all_batches)
    print(f"Deck slots: {len(slots)}", flush=True)

    browser = await connect_browser(args.port)
    try:
        page = await get_chatgpt_page(browser)
        print("Scanning sidebar chats…", flush=True)
        chats_newest_first = await scan_chats(page, title_re, min_images=args.min_images)
        # Chronological: oldest first = first batches of the deck
        chats = list(reversed(chats_newest_first))
        flat_imgs = []
        for c in chats:
            for img in c["images"]:
                flat_imgs.append({**img, "url": c["url"], "chat": c["title"]})

        print(f"Chronological pool: {len(flat_imgs)} images from {len(chats)} chats", flush=True)

        # Map image[i] → slot[i] (full deck order)
        n = min(len(flat_imgs), len(slots))
        assignments = []
        for i in range(n):
            batch, bf = slots[i]
            img = flat_imgs[i]
            assignments.append(
                {
                    "batch": batch,
                    "bf": bf,
                    "src": img["src"],
                    "url": img["url"],
                    "chat": img["chat"],
                    "w": img["w"],
                    "h": img["h"],
                    "index": i,
                }
            )

        # Report what would be new
        new = []
        for a in assignments:
            target = batch_out_dir(a["batch"]) / a["bf"].filename
            exists = target.exists() and target.stat().st_size > 0
            if args.force or not exists:
                new.append(a)
            status = "overwrite" if exists and args.force else ("new" if not exists else "exists")
            print(
                f"  [{a['index']+1:02d}] {a['bf'].filename} ← {a['w']}×{a['h']} ({status}) [{a['chat'][:28]}]",
                flush=True,
            )

        print(f"To download: {len(new)} / mapped {len(assignments)} / deck {len(slots)}", flush=True)
        if args.dry_run:
            return 0

        saved = await download_assignments(page, new if not args.force else assignments, args.force, args.quality)
        catalog = collect_catalog(ART_DIR)
        write_catalog(catalog)
        exif_n = embed_catalog_descriptions(catalog, ART_DIR)
        print(json.dumps({"saved": saved, "mapped": len(assignments), "deck": len(slots), "exif": exif_n}))
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
    ap = argparse.ArgumentParser(description="Harvest ChatGPT conversation images → deck files")
    ap.add_argument("--port", type=int, default=9222)
    ap.add_argument("--prompts-file", default="ART_PROMPTS_TAROT_DECK.md")
    ap.add_argument("--all-decks", action="store_true")
    ap.add_argument("--tarot-only", action="store_true")
    ap.add_argument("--iching-only", action="store_true")
    ap.add_argument("--min-images", type=int, default=2, help="Ignore chats with fewer images (contact sheets)")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--quality", type=int, default=90)
    args = ap.parse_args()
    raise SystemExit(asyncio.run(run(args)))


if __name__ == "__main__":
    main()
