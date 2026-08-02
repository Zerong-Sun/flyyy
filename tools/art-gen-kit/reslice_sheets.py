#!/usr/bin/env python3
"""Re-slice contact sheets along their true gutter lines and overwrite the
sliced assets in place.

The previous generic crop (crop_contact_sheet.py) cuts at the declared uniform
grid, which often lands inside neighbouring cells (the generated sheets are NOT
aligned to that grid). This script instead detects each sheet's actual gutter
lines — thin divider lines (or transparent gaps) that run the full height /
width of a cell band — and crops exactly between them, so cells contain no
gutter border and no content bleeding from an adjacent cell.

Usage:
  .venv/bin/python reslice_sheets.py              # re-slice all _sheets
  .venv/bin/python reslice_sheets.py --dry-run    # print plan, write nothing
  .venv/bin/python reslice_sheets.py --quality 92
"""

from __future__ import annotations

import argparse
import glob
import os
import re
import sys
from pathlib import Path

from PIL import Image

KIT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(KIT_DIR))

from batch_art_utils import (  # noqa: E402
    parse_batch_prompts_md,
    save_cell_webp,
    slug_batch,
)
from kit_paths import ROOT  # noqa: E402

ART_DIR = ROOT / "game" / "assets" / "art"
SHEETS_DIR = ART_DIR / "_sheets"
PROMPTS_FILE = ART_DIR / "ART_PROMPTS_REQ.md"


def _longest_run(vals, pred):
    best = 0
    cur = 0
    for v in vals:
        if pred(v):
            cur += 1
            best = max(best, cur)
        else:
            cur = 0
    return best


def detect_gutter_lines(im: Image.Image, line_frac: float = 0.7):
    """Return (v_lines, h_lines, content_bounds).

    v_lines/h_lines are [(start, end), ...] pixel ranges of the thin divider
    lines (or near-content edge bands). Content bounds are (x0, x1, y0, y1).

    A divider column/row is one whose longest consecutive run of "ink" pixels
    across the content extent fills most of that extent. Ink is opaque alpha
    for transparent sheets or dark luminance for opaque sheets. Content (e.g.
    emblem panels, skylines) only sustains runs of ~0.5 of the span, while the
    thin gutter lines run the full span, so the two are cleanly separated.
    """
    w, h = im.size
    transparent = im.mode in ("RGBA", "LA")
    dark = im.split()[-1].load() if transparent else im.convert("L").load()

    def is_ink(v):
        return v > 30 if transparent else v < 80

    def col_has(x):
        return any(is_ink(dark[x, y]) for y in range(0, h, 3))

    def row_has(y):
        return any(is_ink(dark[x, y]) for x in range(0, w, 3))

    xs = [x for x in range(w) if col_has(x)]
    ys = [y for y in range(h) if row_has(y)]
    x0, x1, y0, y1 = xs[0], xs[-1], ys[0], ys[-1]
    vspan = y1 - y0 + 1
    hspan = x1 - x0 + 1

    vfrac = []
    for x in range(w):
        vfrac.append(
            _longest_run([dark[x, y] for y in range(y0, y1 + 1)], is_ink) / vspan
        )
    hfrac = []
    for y in range(h):
        hfrac.append(
            _longest_run([dark[x, y] for x in range(x0, x1 + 1)], is_ink) / hspan
        )

    def _runs(frac, thr):
        out = []
        in_run = False
        for i, v in enumerate(frac):
            if v >= thr and not in_run:
                s = i
                in_run = True
            elif v < thr and in_run:
                out.append((s, i - 1))
                in_run = False
        if in_run:
            out.append((s, len(frac) - 1))
        # Extend each run while the adjacent pixel is still essentially a full
        # divider (crisp lines only, so genuine content is never absorbed).
        refined = []
        for s, e in out:
            while s - 1 >= 0 and frac[s - 1] >= thr:
                s -= 1
            while e + 1 < len(frac) and frac[e + 1] >= thr:
                e += 1
            if not refined or s > refined[-1][1] + 1:
                refined.append((s, e))
            else:
                refined[-1] = (refined[-1][0], max(refined[-1][1], e))
        return refined

    return _runs(vfrac, line_frac), _runs(hfrac, line_frac), (x0, x1, y0, y1)


def build_cells(lines, lo, hi, expected: int):
    """Map detected gutter lines to `expected` cell ranges along one axis.

    A full grid contributes expected+1 lines (left/right edges included). When
    edge lines are missing (content just fades out), the content bounds stand
    in for them.
    """
    n = len(lines)
    if n == expected + 1:
        return [(lines[i][1] + 1, lines[i + 1][0] - 1) for i in range(expected)]
    if n == expected - 1:
        cells = [(lo, lines[0][0] - 1)]
        for i in range(1, expected - 1):
            cells.append((lines[i - 1][1] + 1, lines[i][0] - 1))
        cells.append((lines[-1][1] + 1, hi))
        return cells
    if n == expected:
        # Exactly one edge line is missing. Figure out which by checking
        # whether the outermost detected line hugs the content bound.
        if lines[0][0] - lo <= 2:
            return [(lines[i][1] + 1, lines[i + 1][0] - 1) for i in range(expected - 1)] + [
                (lines[-1][1] + 1, hi)
            ]
        return [(lo, lines[0][0] - 1)] + [
            (lines[i - 1][1] + 1, lines[i][0] - 1) for i in range(1, expected)
        ]
    # Degenerate: fall back to an even split of the content extent.
    span = hi - lo + 1
    return [(lo + i * span // expected, lo + (i + 1) * span // expected - 1) for i in range(expected)]


def _clean_alpha(cell: Image.Image) -> Image.Image:
    """Zero out near-invisible alpha so gutter residue never shows."""
    if cell.mode not in ("RGBA", "LA"):
        return cell
    if cell.mode == "LA":
        cell = cell.convert("RGBA")
    a = cell.split()[-1]
    if a.getextrema()[0] >= 10:
        return cell
    rgba = cell.load()
    for y in range(cell.height):
        for x in range(cell.width):
            if rgba[x, y][3] < 10:
                rgba[x, y] = (rgba[x, y][0], rgba[x, y][1], rgba[x, y][2], 0)
    return cell


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--dry-run", action="store_true", help="print the plan, write nothing")
    ap.add_argument("--quality", type=int, default=90)
    args = ap.parse_args()

    jobs = parse_batch_prompts_md(PROMPTS_FILE.read_text(encoding="utf-8"), source=PROMPTS_FILE.name)
    jobs_by_slug = {slug_batch(j.name): j for j in jobs}

    total = 0
    for sheet in sorted(SHEETS_DIR.glob("*.webp")):
        parts = sheet.stem.split("--", 1)
        if len(parts) != 2:
            print(f"[skip] {sheet.name}: unexpected name")
            continue
        _prompt_stem, batch_slug = parts
        matches = [slug for slug in jobs_by_slug if batch_slug.startswith(slug)]
        if not matches:
            print(f"[skip] {sheet.name}: no matching batch")
            continue
        job = jobs_by_slug[max(matches, key=len)]

        im = Image.open(sheet)
        v_lines, h_lines, (x0, x1, y0, y1) = detect_gutter_lines(im)
        vx = build_cells(v_lines, x0, x1, job.cols)
        hy = build_cells(h_lines, y0, y1, job.rows)

        print(f"== {sheet.name}")
        print(f"   grid {job.cols}x{job.rows}  content=({x0},{x1},{y0},{y1})  vx={vx}  hy={hy}")

        for r in range(job.rows):
            for c in range(job.cols):
                idx = r * job.cols + c
                if idx >= len(job.files):
                    continue
                bf = job.files[idx]
                cell = im.crop((vx[c][0], hy[r][0], vx[c][1] + 1, hy[r][1] + 1))
                if cell.width <= 0 or cell.height <= 0:
                    print(f"   [warn] bad cell for {bf.filename}")
                    continue
                if cell.width != bf.out_w or cell.height != bf.out_h:
                    cell = cell.resize((bf.out_w, bf.out_h), Image.Resampling.LANCZOS)
                cell = _clean_alpha(cell)
                target = (job.output_dir or ART_DIR) / bf.filename
                if args.dry_run:
                    print(f"   would save {target.relative_to(ROOT)}")
                else:
                    target.parent.mkdir(parents=True, exist_ok=True)
                    save_cell_webp(cell, target, job.transparent, bf.description, args.quality)
                    print(f"   saved {target.relative_to(ROOT)} ({cell.width}x{cell.height})")
                total += 1

    print(f"{'[dry-run] would save' if args.dry_run else 'Saved'} {total} asset(s).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
