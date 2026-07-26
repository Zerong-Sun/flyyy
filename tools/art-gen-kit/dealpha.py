#!/usr/bin/env python3
"""Give cut-out art a real alpha channel.

Several batches came back as flat RGB with the studio's white sweep baked
in, so every icon sat in a pale box. This flood-fills inward from the
border and turns that sweep transparent, leaving full-bleed plates
(backgrounds, buttons, scenes, card faces) untouched.

    python3 scripts/dealpha.py            # report only
    python3 scripts/dealpha.py --apply    # rewrite in place (git is the backup)
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

from kit_paths import ART_DIR as ART
SENTINEL = (255, 0, 255)
THRESH = 32          # how far a pixel may drift from the corner and still be "sweep"
LIGHT = 228          # a border is a sweep only if every channel is at least this bright

# these are meant to bleed to their own edges — never touch them
KEEP_OPAQUE = (
    "bg-nocturne", "map-vellum", "map-sea", "map-orn-",
    "ui-bg-", "ui-btn-", "scene-",
)


def is_full_bleed(name: str) -> bool:
    return any(k in name for k in KEEP_OPAQUE) or name.endswith("-full.webp")


def border_is_sweep(im: Image.Image) -> bool:
    w, h = im.size
    corners = [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)]
    px = im.load()
    return all(min(px[x, y][:3]) >= LIGHT for x, y in corners)


def strip(path: Path, apply: bool) -> str:
    im = Image.open(path)
    if im.mode in ("RGBA", "LA"):
        return "has-alpha"
    if is_full_bleed(path.name):
        return "full-bleed"
    rgb = im.convert("RGB")
    if not border_is_sweep(rgb):
        return "edge-to-edge art"

    work = rgb.copy()
    w, h = work.size
    seeds = [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1),
             (w // 2, 0), (w // 2, h - 1), (0, h // 2), (w - 1, h // 2)]
    for seed in seeds:
        if work.getpixel(seed) != SENTINEL:
            ImageDraw.floodfill(work, seed, SENTINEL, thresh=THRESH)

    swept = work.getdata()
    alpha = Image.new("L", (w, h))
    alpha.putdata([0 if p == SENTINEL else 255 for p in swept])
    covered = sum(1 for p in swept if p == SENTINEL) / (w * h)
    if covered < 0.02:
        return "nothing to strip"
    if covered > 0.94:
        return "SKIPPED (would erase the art)"

    # a hair of blur keeps the cut from looking chipped
    alpha = alpha.filter(ImageFilter.GaussianBlur(0.6))
    out = rgb.convert("RGBA")
    out.putalpha(alpha)
    if apply:
        out.save(path, "WEBP", quality=92, method=6)
    return f"stripped {covered:.0%}"


def main() -> None:
    apply = "--apply" in sys.argv
    done = 0
    for path in sorted(ART.glob("*.webp")):
        result = strip(path, apply)
        if result.startswith("stripped"):
            done += 1
            print(f"  {path.name:34s} {result}")
        elif result.startswith("SKIPPED"):
            print(f"! {path.name:34s} {result}")
    print(f"\n{'rewrote' if apply else 'would rewrite'} {done} files")


if __name__ == "__main__":
    main()
