#!/usr/bin/env python3
"""Generate a splash.webp (1920x1080) from available brand assets."""

from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
BRAND_DIR = ROOT / "game" / "assets" / "brand"
OUT = BRAND_DIR / "splash.webp"

W, H = 1920, 1080
BG_COLOR = (11, 28, 44, 255)       # --bg-deep #0B1C2C
OCEAN_COLOR = (26, 74, 110, 255)    # --ocean #1A4A6E
TEXT_COLOR = (242, 246, 250, 255)   # --text-primary #F2F6FA


def main() -> None:
    img = Image.new("RGBA", (W, H), BG_COLOR)

    # Draw a subtle curved horizon band near the top
    draw = ImageDraw.Draw(img, "RGBA")
    r = W
    for y in range(0, H // 2):
        # arc: half-circle centered at (W/2, 0) with varying radius
        chord = int((1 - (y / (H // 2)) ** 0.4) * W // 2)
        x0 = W // 2 - chord
        x1 = W // 2 + chord
        shade = int(20 + 15 * (y / (H // 2)))
        draw.line([(x0, y), (x1, y)], fill=(shade, 50, 80, 255))
    # Ocean band below
    for y in range(H // 2, H):
        draw.line([(0, y), (W, y)], fill=OCEAN_COLOR)

    # Place logo_mark (centered, upper portion)
    logo_path = BRAND_DIR / "logo_mark.webp"
    word_path = BRAND_DIR / "logo_wordmark_zh.webp"

    cx, cy = W // 2, H // 2 - 60

    if logo_path.exists():
        logo = Image.open(logo_path).convert("RGBA")
        logo = logo.resize((160, 160), Image.Resampling.LANCZOS)
        lx = cx - logo.width // 2
        ly = cy - 120
        img.paste(logo, (lx, ly), logo)

    if word_path.exists():
        word = Image.open(word_path).convert("RGBA")
        target_w = 500
        ratio = target_w / word.width
        target_h = int(word.height * ratio)
        word = word.resize((target_w, target_h), Image.Resampling.LANCZOS)
        wx = cx - word.width // 2
        wy = cy + 60
        img.paste(word, (wx, wy), word)
    else:
        # Fallback text would go here
        pass

    OUT.parent.mkdir(parents=True, exist_ok=True)
    img.save(OUT, "WEBP", quality=90)
    print(f"Saved {OUT} ({OUT.stat().st_size // 1024} KB)")


if __name__ == "__main__":
    main()
