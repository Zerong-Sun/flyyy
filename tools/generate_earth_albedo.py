#!/usr/bin/env python3
"""Generate a realistic Earth albedo texture at 2048×1024 for the GlobeController.

Uses embedded simplified continent polygons rendered in the game palette:
  ocean #1A4A6E, land #3D6B4F, ice #D9E6F0.
Output: game/assets/earth/earth_albedo_day_2k.png
"""

from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
OUT_PATH = ROOT / "game" / "assets" / "earth" / "earth_albedo_day_2k.png"

WIDTH = 2048
HEIGHT = 1024

# ── Game palette ──────────────────────────────────────────────────────
OCEAN = (0x1A, 0x4A, 0x6E, 0xFF)       # #1A4A6E
LAND = (0x3D, 0x6B, 0x4F, 0xFF)        # #3D6B4F
ICE = (0xD9, 0xE6, 0xF0, 0xFF)         # #D9E6F0
COAST = (0x2A, 0x58, 0x3A, 0xFF)       # slightly darker coast
BORDER = (0x5A, 0x7A, 0x8A, 0x60)      # subtle country border
GRATICULE = (0x40, 0x60, 0x78, 0x30)   # grid lines

# ============ Simplified world continent polygons (lon, lat) ============
# Order: draw outlines then fill. Points in normalized [-180,180],[-90,90].


def _px(lon: float, lat: float) -> tuple[int, int]:
    """Convert lon/lat to pixel coords."""
    x = int((lon + 180.0) / 360.0 * WIDTH)
    y = int((90.0 - lat) / 180.0 * HEIGHT)
    return (x, y)


# Simplified polygons — just enough coastline points to look recognisable.
CONTINENTS = [
    # North America
    [
        (-170, 65), (-165, 70), (-140, 75), (-120, 72), (-105, 70), (-90, 75),
        (-80, 72), (-70, 75), (-60, 70), (-55, 60), (-65, 45), (-75, 40),
        (-85, 30), (-82, 25), (-80, 28), (-90, 20), (-95, 18), (-100, 20),
        (-105, 22), (-110, 30), (-120, 35), (-125, 40), (-125, 50), (-130, 55),
        (-140, 60), (-150, 60), (-160, 58), (-170, 65),
    ],
    # Greenland
    [
        (-55, 82), (-45, 83), (-20, 82), (-15, 78), (-20, 72), (-30, 68),
        (-35, 65), (-40, 60), (-50, 62), (-55, 68), (-52, 72), (-50, 78),
        (-55, 82),
    ],
    # South America
    [
        (-80, 10), (-75, 12), (-70, 8), (-60, 5), (-50, 0), (-45, -5),
        (-38, -10), (-35, -18), (-38, -22), (-42, -23), (-48, -28), (-55, -35),
        (-58, -40), (-65, -50), (-68, -55), (-72, -50), (-75, -45), (-74, -38),
        (-72, -30), (-70, -20), (-68, -12), (-65, -5), (-60, 2), (-70, 5),
        (-75, 10), (-80, 10),
    ],
    # Europe
    [
        (-10, 36), (0, 38), (5, 44), (3, 48), (8, 52), (5, 55), (10, 58),
        (12, 56), (15, 54), (20, 56), (25, 58), (30, 60), (28, 65), (32, 70),
        (25, 70), (20, 68), (15, 65), (10, 62), (5, 62), (0, 58), (-5, 55),
        (-8, 60), (-5, 65), (-10, 68), (-8, 72), (-5, 70), (0, 72), (5, 70),
        (8, 65), (10, 58), (5, 55), (-2, 50), (-5, 48), (-8, 44), (-5, 40),
        (-3, 38), (0, 42), (5, 38), (8, 36), (5, 40), (2, 44), (-2, 46),
        (-10, 36),
    ],
    # UK
    [
        (-6, 58), (-5, 60), (-2, 58), (0, 55), (-3, 52), (-5, 50), (-6, 55),
        (-6, 58),
    ],
    # Africa
    [
        (-17, 15), (-15, 18), (-5, 20), (0, 18), (5, 10), (8, 5), (10, 8),
        (12, 5), (15, 2), (20, 0), (25, -5), (30, -10), (35, -15),
        (40, -15), (45, -5), (50, 5), (50, 10), (45, 12), (40, 15),
        (38, 22), (35, 30), (32, 35), (25, 35), (20, 32), (15, 30), (10, 32),
        (10, 36), (12, 38), (8, 38), (5, 35), (-5, 35), (-8, 32), (-12, 30),
        (-15, 28), (-17, 22), (-17, 15),
    ],
    # Asia
    [
        (30, 40), (35, 42), (40, 42), (45, 40), (50, 40), (55, 42),
        (60, 45), (65, 48), (70, 50), (75, 52), (80, 50), (85, 52), (90, 55),
        (100, 58), (105, 60), (110, 55), (115, 50), (120, 45), (125, 42),
        (130, 38), (135, 35), (140, 35), (145, 42), (150, 45), (155, 50),
        (160, 55), (162, 60), (165, 62), (170, 65), (175, 62), (178, 58),
        (170, 55), (160, 52), (150, 48), (140, 42), (135, 38), (130, 35),
        (128, 35), (125, 38), (120, 35), (115, 30), (110, 22), (105, 10),
        (100, 12), (98, 8), (95, 16), (90, 22), (88, 25), (80, 28), (75, 25),
        (70, 22), (65, 25), (62, 28), (58, 28), (55, 30), (50, 30), (45, 32),
        (40, 30), (35, 28), (30, 30), (28, 32), (30, 40),
    ],
    # Japan
    [
        (130, 45), (135, 44), (140, 45), (145, 44), (145, 40), (143, 38),
        (140, 36), (137, 34), (130, 33), (130, 35), (128, 38), (130, 45),
    ],
    # Australian continent
    [
        (115, -15), (120, -12), (125, -12), (130, -12), (135, -15),
        (138, -18), (142, -20), (145, -22), (148, -25), (150, -30),
        (152, -32), (150, -35), (148, -38), (145, -38), (140, -35),
        (135, -35), (130, -32), (125, -30), (120, -28), (115, -20),
        (115, -15),
    ],
    # New Zealand (North + South Islands)
    [
        (172, -35), (174, -36), (176, -38), (178, -39), (176, -41),
        (174, -43), (172, -45), (170, -44), (168, -42), (170, -40),
        (172, -35),
    ],
    # Iceland
    [
        (-22, 66), (-18, 66), (-14, 65), (-14, 64), (-16, 63),
        (-20, 63), (-24, 64), (-24, 65), (-22, 66),
    ],
    # Madagascar
    [
        (44, -12), (48, -14), (50, -18), (50, -22), (48, -25), (45, -22),
        (44, -18), (44, -12),
    ],
    # Indonesia / SE Asia islands
    [
        (96, 6), (98, 5), (100, 2), (102, 0), (104, -2), (106, -5),
        (108, -6), (110, -6), (112, -4), (114, -2), (116, 0), (118, 1),
        (120, 0), (122, -2), (124, -4), (126, -3), (128, -3), (130, -2),
        (132, 0), (134, 2), (136, 4), (138, 6), (140, 5), (136, 2),
        (132, -2), (128, -1), (124, -2), (120, -1), (116, 0), (112, 1),
        (108, 0), (104, 2), (100, 4), (96, 6),
    ],
    # Antarctica
    [
        (-180, -90), (-150, -70), (-120, -72), (-90, -72), (-60, -75),
        (-30, -70), (0, -72), (30, -70), (60, -72), (90, -70), (120, -72),
        (150, -68), (180, -90), (-180, -90),
    ],
]

# Simplified country borders (optional overlay lines)
BORDERS = [
    # US-Canada
    [(-125, 49), (-95, 49), (-90, 50), (-85, 47), (-82, 45), (-80, 43), (-75, 45), (-67, 45)],
    # US-Mexico
    [(-117, 32), (-110, 31), (-105, 30), (-100, 26), (-97, 26)],
]


def _draw_polygon(draw: ImageDraw.ImageDraw, points: list[tuple[int, int]],
                  fill: tuple, outline: tuple, outline_width: int = 2) -> None:
    """Draw a filled polygon with outline."""
    draw.polygon(points, fill=fill, outline=outline, width=outline_width)


def generate() -> None:
    img = Image.new("RGBA", (WIDTH, HEIGHT), OCEAN)
    draw = ImageDraw.Draw(img)

    # Draw graticule (thin lat/lon lines)
    for lat in range(-90, 91, 15):
        y = _px(0, lat)[1]
        draw.line([(0, y), (WIDTH - 1, y)], fill=GRATICULE, width=1)
    for lon in range(-180, 181, 15):
        x = _px(lon, 0)[0]
        draw.line([(x, 0), (x, HEIGHT - 1)], fill=GRATICULE, width=1)

    # Draw continents
    for polygon in CONTINENTS:
        px_points = [_px(lon, lat) for lon, lat in polygon]
        _draw_polygon(draw, px_points, fill=LAND, outline=COAST, outline_width=2)

    # Draw country borders
    for border in BORDERS:
        px_points = [_px(lon, lat) for lon, lat in border]
        draw.line(px_points, fill=BORDER, width=1)

    # Ensure directory exists
    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    img.save(OUT_PATH, "PNG")
    print(f"Earth albedo saved: {OUT_PATH} ({WIDTH}×{HEIGHT})")


if __name__ == "__main__":
    generate()
