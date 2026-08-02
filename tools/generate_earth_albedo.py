#!/usr/bin/env python3
"""Generate a stylized Earth albedo texture for the GlobeController.

Uses the game palette (ocean #1A4A6E, land greens/tans, ice #D9E6F0)
with real Natural Earth 1:50m coastlines (when cached in tools/geo/),
FBM terrain shading, subtle ocean depth, and faint administrative
borders (countries + large-country states/provinces).

  python3 tools/generate_earth_albedo.py
  python3 tools/generate_earth_albedo.py --size 4096 --out game/assets/earth/earth_albedo_day_4k.png

Run tools/fetch_geo_data.py first for real geography; the tool falls back
to embedded simplified outlines when the cache is absent.
"""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUT = ROOT / "game" / "assets" / "earth" / "earth_albedo_day_2k.png"
GEO_DIR = ROOT / "tools" / "geo"

WIDTH = 2048
HEIGHT = 1024

# ── Game palette ──────────────────────────────────────────────────────
OCEAN_DEEP = (0x12, 0x38, 0x58)
OCEAN = (0x1A, 0x4A, 0x6E)
OCEAN_SHALLOW = (0x2A, 0x62, 0x82)
LAND_LOW = (0x3A, 0x6E, 0x4A)
LAND = (0x3D, 0x6B, 0x4F)
LAND_MID = (0x5A, 0x72, 0x48)
LAND_HIGH = (0x7A, 0x6E, 0x4A)
LAND_PEAK = (0x8A, 0x7A, 0x68)
ICE = (0xD9, 0xE6, 0xF0)
COAST = (0x2A, 0x58, 0x3A)
BORDER = (0x5A, 0x7A, 0x8A, 0x70)
GRATICULE = (0x40, 0x60, 0x78, 0x18)

# Administrative-division border colors (drawn inside countries only).
BORDER_ADMIN0 = (0x6A, 0x86, 0x96, 0x60)
BORDER_ADMIN1 = (0x6A, 0x86, 0x96, 0x34)

# Large countries for which to render state/province borders.
ADMIN1_COUNTRIES = {"RUS", "USA", "IND", "IDN", "CHN", "BRA", "CAN", "AUS", "ZAF"}


def _px(lon: float, lat: float, width: int | None = None, height: int | None = None) -> tuple[int, int]:
    # Read WIDTH/HEIGHT at call time (defaults are bound at import and would stale on --size).
    w = WIDTH if width is None else width
    h = HEIGHT if height is None else height
    x = int((lon + 180.0) / 360.0 * w)
    y = int((90.0 - lat) / 180.0 * h)
    return (x, y)


# ── Offline fallback geography ────────────────────────────────────────
# Denser continent outlines (lon, lat), used only when Natural Earth
# GeoJSON is not cached in tools/geo/.
CONTINENTS = [
    # North America
    [
        (-168, 65), (-165, 68), (-160, 66), (-155, 64), (-150, 61), (-145, 60),
        (-140, 60), (-135, 58), (-130, 55), (-125, 50), (-124, 48), (-124, 42),
        (-122, 38), (-120, 35), (-117, 33), (-115, 30), (-112, 28), (-110, 26),
        (-106, 24), (-102, 22), (-97, 20), (-95, 18), (-92, 18), (-90, 20),
        (-88, 22), (-86, 24), (-84, 26), (-82, 26), (-80, 28), (-82, 30),
        (-85, 30), (-88, 32), (-90, 35), (-88, 38), (-85, 40), (-82, 42),
        (-80, 44), (-76, 42), (-74, 40), (-72, 42), (-70, 44), (-68, 46),
        (-66, 48), (-64, 50), (-62, 52), (-60, 55), (-58, 58), (-56, 60),
        (-55, 62), (-58, 65), (-62, 68), (-68, 70), (-75, 72), (-82, 74),
        (-90, 75), (-100, 74), (-110, 72), (-120, 72), (-130, 70), (-140, 70),
        (-150, 70), (-160, 68), (-168, 65),
    ],
    # Greenland
    [
        (-55, 83), (-48, 83), (-40, 82), (-30, 80), (-22, 78), (-18, 75),
        (-20, 72), (-25, 70), (-30, 68), (-35, 66), (-40, 64), (-45, 62),
        (-50, 63), (-54, 66), (-55, 70), (-53, 74), (-52, 78), (-54, 81),
        (-55, 83),
    ],
    # South America
    [
        (-80, 10), (-78, 11), (-75, 11), (-72, 10), (-70, 8), (-68, 6),
        (-65, 4), (-62, 2), (-58, 0), (-54, -2), (-50, -4), (-46, -6),
        (-42, -8), (-38, -12), (-36, -16), (-35, -20), (-38, -24), (-42, -26),
        (-46, -28), (-50, -30), (-54, -34), (-58, -38), (-62, -42), (-66, -46),
        (-68, -50), (-70, -54), (-72, -52), (-74, -48), (-74, -44), (-73, -40),
        (-72, -36), (-71, -32), (-70, -28), (-70, -24), (-72, -20), (-74, -16),
        (-76, -12), (-78, -8), (-79, -4), (-80, 0), (-80, 4), (-80, 8),
        (-80, 10),
    ],
    # Europe (simple non-self-intersecting outline)
    [
        (-9, 36), (-5, 36), (0, 38), (5, 40), (10, 40), (15, 42),
        (20, 44), (25, 46), (30, 50), (32, 55), (30, 60), (28, 65),
        (25, 70), (20, 71), (15, 70), (10, 68), (5, 65), (0, 62),
        (-5, 60), (-8, 58), (-9, 55), (-8, 50), (-6, 46), (-8, 42),
        (-9, 38), (-9, 36),
    ],
    # UK + Ireland
    [
        (-8, 55), (-7, 57), (-5, 58), (-3, 58), (-1, 57), (0, 55),
        (-1, 53), (-3, 51), (-5, 50), (-6, 51), (-7, 53), (-8, 55),
    ],
    # Africa
    [
        (-17, 15), (-16, 18), (-14, 20), (-10, 22), (-6, 22), (-2, 20),
        (2, 18), (6, 14), (8, 10), (10, 8), (12, 6), (14, 4),
        (16, 2), (20, 0), (24, -2), (28, -6), (32, -10), (36, -14),
        (40, -16), (44, -14), (48, -10), (50, -4), (50, 2), (48, 8),
        (46, 12), (42, 14), (38, 18), (36, 24), (34, 28), (32, 32),
        (30, 34), (26, 34), (22, 32), (18, 30), (14, 30), (12, 32),
        (10, 34), (10, 36), (8, 37), (4, 36), (0, 34), (-4, 34),
        (-8, 32), (-12, 30), (-15, 28), (-17, 24), (-17, 20), (-17, 15),
    ],
    # Asia
    [
        (30, 40), (34, 42), (40, 42), (46, 40), (52, 42), (58, 44),
        (64, 48), (70, 50), (76, 52), (82, 52), (88, 54), (94, 56),
        (100, 58), (106, 58), (112, 54), (118, 48), (122, 44), (126, 40),
        (130, 38), (134, 36), (138, 36), (142, 40), (146, 44), (150, 48),
        (154, 52), (158, 56), (162, 60), (166, 64), (170, 66), (174, 64),
        (176, 60), (172, 56), (166, 54), (160, 52), (154, 50), (148, 46),
        (142, 42), (138, 38), (134, 36), (130, 34), (126, 36), (122, 34),
        (118, 32), (114, 28), (110, 24), (106, 18), (102, 12), (100, 10),
        (98, 8), (96, 12), (94, 16), (90, 20), (86, 24), (80, 26),
        (74, 24), (68, 22), (64, 24), (60, 28), (56, 28), (52, 30),
        (48, 32), (44, 32), (40, 30), (36, 28), (32, 30), (30, 34),
        (30, 40),
    ],
    # Japan
    [
        (130, 45), (133, 44), (136, 44), (140, 45), (144, 44), (145, 42),
        (144, 40), (142, 38), (140, 36), (138, 34), (136, 33), (132, 33),
        (130, 34), (129, 36), (129, 40), (130, 45),
    ],
    # Australia
    [
        (114, -22), (116, -18), (118, -14), (122, -12), (126, -12), (130, -12),
        (134, -14), (138, -16), (142, -18), (145, -20), (148, -22), (150, -26),
        (152, -30), (153, -34), (151, -36), (148, -38), (144, -38), (140, -36),
        (136, -35), (132, -34), (128, -32), (124, -30), (120, -28), (116, -26),
        (114, -24), (114, -22),
    ],
    # New Zealand
    [
        (172, -35), (174, -36), (176, -38), (177, -40), (176, -42),
        (174, -44), (172, -46), (170, -45), (168, -43), (169, -40),
        (171, -37), (172, -35),
    ],
    # Iceland
    [
        (-24, 65), (-22, 66), (-18, 66), (-14, 65), (-13, 64),
        (-15, 63), (-18, 63), (-22, 64), (-24, 65),
    ],
    # Madagascar
    [
        (44, -12), (46, -13), (48, -14), (50, -16), (50, -20),
        (49, -24), (47, -25), (45, -22), (44, -18), (44, -12),
    ],
    # SE Asia / Indonesia arc
    [
        (95, 6), (98, 5), (100, 3), (102, 1), (104, -1), (106, -4),
        (108, -6), (110, -7), (112, -6), (114, -4), (116, -2), (118, 0),
        (120, -1), (122, -3), (124, -4), (126, -3), (128, -2), (130, -1),
        (132, 1), (134, 3), (136, 4), (138, 5), (140, 4), (138, 2),
        (134, 0), (130, -1), (126, -2), (122, -1), (118, 0), (114, 1),
        (110, 0), (106, 1), (102, 3), (98, 5), (95, 6),
    ],
    # Antarctica
    [
        (-180, -90), (-150, -72), (-120, -74), (-90, -74), (-60, -76),
        (-30, -72), (0, -74), (30, -72), (60, -74), (90, -72),
        (120, -74), (150, -70), (180, -90), (-180, -90),
    ],
]

BORDERS = [
    [(-125, 49), (-110, 49), (-95, 49), (-90, 49), (-85, 47), (-82, 45), (-75, 45), (-68, 45)],
    [(-117, 32), (-112, 31), (-108, 31), (-104, 30), (-100, 28), (-97, 26)],
]


# ── GeoJSON loading ───────────────────────────────────────────────────
def _load_geojson_features(path: Path) -> list[dict] | None:
    if not path.exists():
        return None
    try:
        with open(path, encoding="utf-8") as f:
            gj = json.load(f)
        feats = gj.get("features", [])
        if not feats:
            return None
        return feats
    except Exception:  # noqa: BLE001 - corrupt/partial cache → fallback
        return None


def _iter_rings(geometry: dict):
    """Yield (lon, lat) ring point lists from a Polygon/MultiPolygon geometry."""
    if geometry is None:
        return
    gtype = geometry.get("type")
    coords = geometry.get("coordinates", [])
    if gtype == "Polygon":
        for ring in coords:
            yield ring
    elif gtype == "MultiPolygon":
        for poly in coords:
            for ring in poly:
                yield ring


def _split_ring_at_seam(ring, width: int):
    """Split a ring at the ±180° seam so ImageDraw doesn't draw a cross-map slash."""
    xs = [_px(pt[0], pt[1], width=width)[0] for pt in ring]
    out: list[list] = []
    cur: list = []
    for i, (pt, x) in enumerate(zip(ring, xs)):
        if cur and abs(x - xs[i - 1]) > width // 2:
            out.append(cur)
            cur = []
        cur.append((pt[0], pt[1]))
    if len(cur) >= 3:
        out.append(cur)
    # Drop degenerate pieces that would draw a seam line.
    return [seg for seg in out if len(seg) >= 3]


def _build_land_mask(features: list[dict] | None, width: int, height: int) -> Image.Image:
    """Rasterize land polygons into a soft-edged land mask."""
    mask_img = Image.new("L", (width, height), 0)
    mask_draw = ImageDraw.Draw(mask_img)
    if features:
        for feat in features:
            geom = feat.get("geometry")
            for ring in _iter_rings(geom):
                for seg in _split_ring_at_seam(ring, width):
                    if len(seg) < 3:
                        continue
                    seg_pts = [_px(pt[0], pt[1], width=width, height=height) for pt in seg]
                    mask_draw.polygon(seg_pts, fill=255)
    else:
        for polygon in CONTINENTS:
            px_points = [_px(lon, lat, width=width, height=height) for lon, lat in polygon]
            mask_draw.polygon(px_points, fill=255)
    mask_img = mask_img.filter(ImageFilter.GaussianBlur(radius=max(0.6, width / 2048.0)))
    return mask_img


def _border_layer(features, width: int, height: int, color) -> Image.Image:
    """Draw ring outlines as polylines onto an RGBA layer."""
    layer = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    for feat in features:
        geom = feat.get("geometry")
        for ring in _iter_rings(geom):
            for seg in _split_ring_at_seam(ring, width):
                if len(seg) < 3:
                    continue
                pts = [_px(pt[0], pt[1], width=width, height=height) for pt in seg]
                draw.line(pts + [pts[0]], fill=color, width=max(1, width // 2048))
    return layer


def _interior_border_mask(mask_img: Image.Image) -> Image.Image:
    """Land pixels whose 3x3 neighborhood is fully land (borders stay inland)."""
    land = mask_img.point(lambda v: 255 if v > 128 else 0)
    return land.filter(ImageFilter.MinFilter(3))


def _hash2(x: int, y: int) -> float:
    n = x * 374761393 + y * 668265263
    n = (n ^ (n >> 13)) * 1274126177
    n = n ^ (n >> 16)
    return (n & 0x7FFFFFFF) / 0x7FFFFFFF


def _noise2(x: float, y: float) -> float:
    x0 = math.floor(x)
    y0 = math.floor(y)
    fx = x - x0
    fy = y - y0
    u = fx * fx * (3.0 - 2.0 * fx)
    v = fy * fy * (3.0 - 2.0 * fy)
    a = _hash2(x0, y0)
    b = _hash2(x0 + 1, y0)
    c = _hash2(x0, y0 + 1)
    d = _hash2(x0 + 1, y0 + 1)
    return a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v


def _fbm(x: float, y: float, octaves: int = 5) -> float:
    amp = 0.5
    freq = 1.0
    total = 0.0
    norm = 0.0
    for _ in range(octaves):
        total += _noise2(x * freq, y * freq) * amp
        norm += amp
        amp *= 0.5
        freq *= 2.0
    return total / norm if norm > 0 else 0.0


def _lerp_rgb(a: tuple[int, int, int], b: tuple[int, int, int], t: float) -> tuple[int, int, int]:
    t = max(0.0, min(1.0, t))
    return (
        int(a[0] + (b[0] - a[0]) * t),
        int(a[1] + (b[1] - a[1]) * t),
        int(a[2] + (b[2] - a[2]) * t),
    )


def _land_color(elev: float, lat: float) -> tuple[int, int, int]:
    """Map elevation + latitude into stylized land tones."""
    abs_lat = abs(lat)
    if abs_lat > 72:
        return ICE
    if abs_lat > 65:
        t = (abs_lat - 65) / 7.0
        base = _lerp_rgb(LAND_LOW, ICE, t)
    elif elev < 0.35:
        base = _lerp_rgb(LAND_LOW, LAND, elev / 0.35)
    elif elev < 0.6:
        base = _lerp_rgb(LAND, LAND_MID, (elev - 0.35) / 0.25)
    elif elev < 0.82:
        base = _lerp_rgb(LAND_MID, LAND_HIGH, (elev - 0.6) / 0.22)
    else:
        base = _lerp_rgb(LAND_HIGH, LAND_PEAK, (elev - 0.82) / 0.18)
    # Slight desert tint in subtropical belts
    if 15 < abs_lat < 35 and elev < 0.45:
        desert = (0x8A, 0x7A, 0x52)
        base = _lerp_rgb(base, desert, 0.35)
    return base


def _ocean_color(depth: float, lat: float) -> tuple[int, int, int]:
    if abs(lat) > 75:
        return _lerp_rgb(OCEAN, ICE, 0.35)
    if depth < 0.25:
        return _lerp_rgb(OCEAN_SHALLOW, OCEAN, depth / 0.25)
    if depth < 0.7:
        return _lerp_rgb(OCEAN, OCEAN_DEEP, (depth - 0.25) / 0.45)
    return OCEAN_DEEP


def generate(width: int = 2048, out_path: Path | None = None) -> None:
    global WIDTH, HEIGHT
    WIDTH = int(width)
    HEIGHT = int(width) // 2
    out = out_path or DEFAULT_OUT

    admin0 = _load_geojson_features(GEO_DIR / "ne_50m_admin_0_countries.geojson")
    admin1 = _load_geojson_features(GEO_DIR / "ne_50m_admin_1_states_provinces.geojson")
    if admin0:
        print(f"Natural Earth: {len(admin0)} countries loaded")
    else:
        print("Natural Earth cache missing → using embedded fallback outlines")

    # Land mask from polygons
    mask_img = _build_land_mask(admin0, WIDTH, HEIGHT)

    img = Image.new("RGBA", (WIDTH, HEIGHT), OCEAN + (255,))
    pixels = img.load()
    mask = mask_img.load()

    inv_w = 1.0 / float(WIDTH)
    inv_h = 1.0 / float(HEIGHT)
    scale = WIDTH / 512.0

    for y in range(HEIGHT):
        lat = 90.0 - (y + 0.5) * inv_h * 180.0
        for x in range(WIDTH):
            lon = -180.0 + (x + 0.5) * inv_w * 360.0
            land_a = mask[x, y] / 255.0
            nx = x * inv_w * 8.0 * scale
            ny = y * inv_h * 4.0 * scale
            n = _fbm(nx, ny, octaves=5)
            if land_a > 0.08:
                elev = n * 0.75 + land_a * 0.25
                # Boost elevation inland (distance from soft edge)
                elev = min(1.0, elev + max(0.0, land_a - 0.55) * 0.35)
                col = _land_color(elev, lat)
                if land_a < 0.85:
                    # Blend toward coast / shallow water at edges
                    coast_blend = 1.0 - land_a
                    shallow = _ocean_color(0.15, lat)
                    col = _lerp_rgb(col, shallow, coast_blend * 0.55)
                pixels[x, y] = col
            else:
                depth = 0.35 + n * 0.55
                # Continental shelf near land
                depth *= 1.0 - land_a * 0.8
                pixels[x, y] = _ocean_color(depth, lat)

    draw = ImageDraw.Draw(img, "RGBA")

    # Very faint graticule
    for lat in range(-75, 76, 15):
        y = _px(0, lat)[1]
        draw.line([(0, y), (WIDTH - 1, y)], fill=GRATICULE, width=1)
    for lon in range(-180, 181, 30):
        x = _px(lon, 0)[0]
        draw.line([(x, 0), (x, HEIGHT - 1)], fill=GRATICULE, width=1)

    if admin0:
        # Coastline: soft edge of the blurred land mask, slightly stronger than borders.
        edge = mask_img.filter(ImageFilter.FIND_EDGES).point(lambda v: 255 if v > 32 else 0)
        coast = Image.new("RGBA", (WIDTH, HEIGHT), (0, 0, 0, 0))
        ImageDraw.Draw(coast).bitmap((0, 0), edge, fill=COAST)
        img.alpha_composite(coast)

        # Keep borders inland: exclude any line pixel whose 3x3 neighbourhood
        # touches ocean, so coastlines don't get re-drawn as country borders.
        interior = _interior_border_mask(mask_img)

        def _masked(layer: Image.Image) -> Image.Image:
            masked = layer.copy()
            alpha = masked.getchannel("A").point(lambda a: 255 if a > 0 else 0)
            masked.putalpha(Image.composite(alpha, Image.new("L", alpha.size, 0), interior))
            return masked

        # Admin-0 country borders (subtle).
        if admin0:
            img.alpha_composite(_masked(_border_layer(admin0, WIDTH, HEIGHT, BORDER_ADMIN0)))

        # Admin-1 state/province borders for large countries (fainter still).
        if admin1:
            big = [f for f in admin1 if f.get("properties", {}).get("adm0_a3") in ADMIN1_COUNTRIES]
            img.alpha_composite(_masked(_border_layer(big, WIDTH, HEIGHT, BORDER_ADMIN1)))
    else:
        # Fallback: legacy border segments only.
        for border in BORDERS:
            px_points = [_px(lon, lat) for lon, lat in border]
            draw.line(px_points, fill=BORDER, width=max(1, WIDTH // 2048))

    out.parent.mkdir(parents=True, exist_ok=True)
    img.convert("RGB").save(out, "PNG", optimize=True)
    print(f"Earth albedo saved: {out} ({WIDTH}×{HEIGHT})")


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description="Generate stylized Earth albedo PNG for Godot globe")
    ap.add_argument("--size", type=int, default=2048, help="Width in pixels (height = size/2)")
    ap.add_argument("--out", type=Path, default=None, help="Output PNG path")
    args = ap.parse_args()
    out = args.out
    if out is None and args.size >= 4096:
        out = ROOT / "game" / "assets" / "earth" / "earth_albedo_day_4k.png"
    generate(width=args.size, out_path=out)
