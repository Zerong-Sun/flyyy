"""Generate the two sell-feedback merchant portraits as 64x64 PNGs.

Assets (REQ §3.4.2):
  portrait_worried_64.png      — 担忧/扶额，L2 大亏
  portrait_celebrating_64.png  — 欢呼，W2 大满贯

Style: flat travel-merchant bust (broad-brim hat + scarf), warm poster
palette consistent with the city plates, emoji-like readability at 64px.
Deterministic seed so re-runs are byte-identical.
"""

from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
OUT_DIR = ROOT / "game" / "assets" / "portraits"

SIZE = 64
BG_KEYS = ((0, 0, 0, 0), (0, 0, 0, 0))  # transparent outside the bust

SKIN = (226, 190, 152, 255)
SKIN_SHADE = (198, 160, 122, 255)
HAIR = (70, 52, 38, 255)
HAT = (66, 92, 120, 255)  # travel-blue beret-ish
HAT_BAND = (232, 154, 60, 255)
SCARF = (200, 96, 78, 255)  # warm red
SHIRT = (58, 74, 92, 255)
OUTLINE = (42, 38, 44, 255)


def _base() -> Image.Image:
    return Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))


def _draw_merchant(im: Image.Image, mood: str) -> None:
    d = ImageDraw.Draw(im)
    # --- scarf / shoulders band (bottom third) ---
    d.rectangle([0, 46, 63, 63], fill=SCARF)
    d.polygon([(22, 42), (42, 42), (48, 63), (16, 63)], fill=SCARF)
    # --- neck ---
    d.rectangle([26, 38, 38, 48], fill=SKIN_SHADE)
    # --- head ---
    d.ellipse([18, 14, 46, 42], fill=SKIN)
    # --- hair fringe under hat ---
    d.arc([18, 14, 46, 42], 180, 360, fill=HAIR, width=4)
    # --- hat (wide-brim travel cap) ---
    d.ellipse([12, 8, 52, 22], fill=HAT)
    d.ellipse([20, 2, 44, 14], fill=HAT)
    d.rectangle([20, 12, 44, 14], fill=HAT_BAND)
    # --- face details ---
    if mood == "worried":
        # Furrowed brows angled inward + drooping mouth + sweat drop
        d.line([24, 24, 30, 26], fill=OUTLINE, width=2)
        d.line([40, 24, 34, 26], fill=OUTLINE, width=2)
        d.ellipse([26, 28, 30, 31], fill=OUTLINE)  # eyes
        d.ellipse([34, 28, 38, 31], fill=OUTLINE)
        d.arc([28, 34, 36, 40], 20, 160, fill=OUTLINE, width=2)  # frown
        d.ellipse([43, 10, 48, 16], fill=(140, 190, 220, 255))  # sweat
    else:
        # Raised brows + bright eyes + open smiling mouth
        d.arc([24, 20, 30, 24], 180, 360, fill=OUTLINE, width=2)
        d.arc([34, 20, 40, 24], 180, 360, fill=OUTLINE, width=2)
        d.ellipse([26, 27, 30, 31], fill=OUTLINE)
        d.ellipse([34, 27, 38, 31], fill=OUTLINE)
        d.pieslice([27, 32, 37, 42], 180, 360, fill=OUTLINE)  # open smile
        # celebration sparkle
        d.polygon([(6, 6), (8, 11), (13, 12), (8, 13), (7, 18), (6, 13),
                   (1, 12), (6, 11)], fill=HAT_BAND)
        d.polygon([(52, 4), (54, 8), (58, 9), (54, 10), (53, 14), (52, 10),
                   (48, 9), (52, 8)], fill=HAT_BAND)


def render(mood: str) -> Image.Image:
    im = _base()
    _draw_merchant(im, mood)
    # Light antialias soften (keeps 64px readable but less pixel-jagged)
    return im.filter(ImageFilter.SMOOTH)


def main() -> int:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for mood, name in (("worried", "portrait_worried_64.png"),
                       ("celebrating", "portrait_celebrating_64.png")):
        out = OUT_DIR / name
        render(mood).save(out, "PNG")
        print("wrote", out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
