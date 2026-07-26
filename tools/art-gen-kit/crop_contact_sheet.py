#!/usr/bin/env python3
"""
Crop saved contact-sheet images into named assets with per-cell output sizes.

Usage:
  .venv/bin/python crop_contact_sheet.py --list
  .venv/bin/python crop_contact_sheet.py --prompts ART_PROMPTS_UI.md --batch 2
  .venv/bin/python crop_contact_sheet.py --sheet assets/art/_sheets/...webp --prompts ART_PROMPTS_CARDS.md --batch 1
  .venv/bin/python crop_contact_sheet.py --all-sheets --embed-descriptions
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from batch_art_utils import (
    ART_DIR,
    SHEETS_DIR,
    collect_catalog,
    embed_catalog_descriptions,
    parse_batch_prompts_md,
    sheet_path_for,
    slug_batch,
    split_contact_sheet,
    save_cell_webp,
    write_catalog,
)
from PIL import Image


from kit_paths import ROOT


def find_job(jobs, batch_filter: str):
    bf = batch_filter.lower()
    for j in jobs:
        if bf in j.name.lower() or slug_batch(j.name).startswith(bf):
            return j
    return None


def crop_job(job, sheet: Path, art_dir: Path, quality: int, force: bool) -> int:
    raw = sheet.read_bytes()
    cells = split_contact_sheet(raw, job)
    saved = 0
    for bf, cell in zip(job.files, cells):
        target = art_dir / bf.filename
        if target.exists() and not force:
            print(f"  skip existing {target.name}")
            continue
        save_cell_webp(cell, target, job.transparent, bf.description, quality)
        print(f"  saved {target.name} ({bf.out_w}×{bf.out_h}) — {bf.description[:60]}")
        saved += 1
    return saved


def main() -> int:
    ap = argparse.ArgumentParser(description="Crop contact sheets → named art assets")
    ap.add_argument("--prompts-file", default="ART_PROMPTS_UI.md")
    ap.add_argument("--batch", help="Batch title substring, e.g. '2' or 'Background'")
    ap.add_argument("--sheet", help="Explicit sheet image path")
    ap.add_argument("--all-sheets", action="store_true", help="Process every sheet in _sheets/")
    ap.add_argument("--list", action="store_true", help="List batches and sheet paths")
    ap.add_argument("--force", action="store_true", help="Overwrite existing outputs")
    ap.add_argument("--quality", type=int, default=90)
    ap.add_argument("--embed-descriptions", action="store_true", help="Write EXIF + ART_CATALOG.json")
    args = ap.parse_args()

    prompts_path = ART_DIR / Path(args.prompts_file).name
    if not prompts_path.exists():
        print(f"Not found: {prompts_path}", file=sys.stderr)
        return 1

    jobs = parse_batch_prompts_md(prompts_path.read_text(encoding="utf-8"), source=prompts_path.name)
    stem = prompts_path.stem

    if args.list:
        for j in jobs:
            sp = sheet_path_for(j, stem)
            print(f"{j.name}")
            print(f"  sheet: {sp} {'✓' if sp.exists() else '(missing)'}")
            for i, bf in enumerate(j.files, 1):
                print(f"  {i:2}. {bf.filename} ({bf.out_w}×{bf.out_h}) — {bf.description[:70]}")
        return 0

    SHEETS_DIR.mkdir(parents=True, exist_ok=True)
    total = 0

    if args.all_sheets:
        for sheet in sorted(SHEETS_DIR.glob("*.webp")):
            # match stem--batchslug.webp
            parts = sheet.stem.split("--", 1)
            if len(parts) != 2:
                print(f"[skip] {sheet.name}: unexpected name", file=sys.stderr)
                continue
            pstem, bslug = parts
            if pstem != stem:
                continue
            job = next((j for j in jobs if slug_batch(j.name) == bslug), None)
            if not job:
                print(f"[skip] {sheet.name}: batch not in {prompts_path.name}", file=sys.stderr)
                continue
            print(f"Cropping {sheet.name} → {job.name}")
            total += crop_job(job, sheet, ART_DIR, args.quality, args.force)
    else:
        if not args.batch:
            print("Provide --batch N or --all-sheets", file=sys.stderr)
            return 1
        job = find_job(jobs, args.batch)
        if not job:
            print(f"Batch not found: {args.batch}", file=sys.stderr)
            return 1
        sheet = Path(args.sheet) if args.sheet else sheet_path_for(job, stem)
        if not sheet.exists():
            print(f"Sheet missing: {sheet}", file=sys.stderr)
            print("Generate with chatgpt_gen_art.py --batch (saves to _sheets/)", file=sys.stderr)
            return 1
        print(f"Cropping {sheet.name} → {job.name}")
        total += crop_job(job, sheet, ART_DIR, args.quality, args.force)

    print(f"Saved {total} file(s).")

    if args.embed_descriptions or total > 0:
        catalog = collect_catalog(ART_DIR)
        write_catalog(catalog)
        n = embed_catalog_descriptions(catalog, ART_DIR)
        print(f"ART_CATALOG.json ({catalog['count']} assets); EXIF embedded in {n} file(s).")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
