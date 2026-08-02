"""Generate procedural "regional base plate + tint variant" city hero images.

Fills the 480 cities in game/data/world.json that lack a real hero image with a
deterministic, per-city tinted variant of their region's travel-poster plate.

Outputs:  game/assets/cities/city_{city_id}_hero_720.webp  (1280x720 WebP, RGB)
License:  original-procedural (see game/assets/i18n/attribution_zh.txt)

Determinism: every random choice derives from sha256(city_id), so re-runs are
byte-identical. Skipped cities (already present) are never touched unless --force.
"""

from __future__ import annotations

import argparse
import colorsys
import hashlib
import json
import random
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
WORLD_PATH = ROOT / "game" / "data" / "world.json"
OUT_DIR = ROOT / "game" / "assets" / "cities"
SHEETS_DIR = ROOT / "game" / "assets" / "cities" / "_sheets"

W, H = 1280, 720

# Demo 20 hubs ship real AI-authored hero art (REQ §3.1: 不得用于 Demo 20 城).
# Never overwrite these, even with --force.
PROTECTED_CITY_IDS = {
    "atlanta", "dubai", "dallas", "denver", "london", "chicago", "istanbul",
    "los_angeles", "tokyo", "shanghai", "paris", "amsterdam", "guangzhou",
    "frankfurt", "beijing", "singapore", "seoul", "hong_kong", "bangkok",
    "miami",
}

# Generated plates are always rendered at this exact size. Any hero file with a
# different size is treated as real human/AI art and is never overwritten, even
# under --force. This makes the protection data-driven instead of a hard-coded
# allowlist: if a real art asset lands in a non-Demo city later, --force keeps
# it intact.
PLATE_SIZE = (1280, 720)


def _looks_generated(path: Path) -> bool:
    """True if an existing hero file matches this tool's output signature."""
    if not path.is_file():
        return False
    try:
        from PIL import Image

        with Image.open(path) as im:
            return im.size == PLATE_SIZE
    except Exception:
        return False

# ---------------------------------------------------------------------------
# Country code -> region (art-only; superset of run_pipeline.COUNTRY_REGION)
# ---------------------------------------------------------------------------
REGION_BY_COUNTRY: dict[str, str] = {
    # === pipeline 9 regions (run_pipeline.py COUNTRY_REGION) ===
    "CN": "east_asia", "JP": "east_asia", "KR": "east_asia", "TW": "east_asia",
    "HK": "east_asia", "MN": "east_asia",
    "TH": "southeast_asia", "VN": "southeast_asia", "MY": "southeast_asia",
    "SG": "southeast_asia", "ID": "southeast_asia", "PH": "southeast_asia",
    "MM": "southeast_asia", "KH": "southeast_asia", "LA": "southeast_asia",
    "IN": "south_asia", "PK": "south_asia", "BD": "south_asia", "LK": "south_asia",
    "NP": "south_asia",
    "AE": "middle_east", "SA": "middle_east", "QA": "middle_east",
    "KW": "middle_east", "OM": "middle_east", "BH": "middle_east",
    "IL": "middle_east", "JO": "middle_east", "LB": "middle_east", "TR": "middle_east",
    "GB": "europe", "FR": "europe", "DE": "europe", "NL": "europe",
    "IT": "europe", "ES": "europe", "RU": "europe", "CH": "europe",
    "SE": "europe", "NO": "europe", "DK": "europe", "FI": "europe",
    "PL": "europe", "AT": "europe", "BE": "europe", "IE": "europe",
    "PT": "europe", "GR": "europe", "CZ": "europe", "HU": "europe",
    "US": "north_america", "CA": "north_america", "MX": "north_america",
    "BR": "south_america", "AR": "south_america", "CL": "south_america",
    "CO": "south_america", "PE": "south_america", "VE": "south_america",
    "ZA": "africa", "EG": "africa", "NG": "africa", "KE": "africa",
    "MA": "africa", "ET": "africa", "GH": "africa", "TZ": "africa",
    "AU": "oceania", "NZ": "oceania",
    # === extended mapping for world.json countries outside the pipeline map ===
    "AF": "central_asia", "GE": "central_asia", "AM": "central_asia",
    "AZ": "central_asia", "TJ": "central_asia", "TM": "central_asia",
    "UZ": "central_asia", "KZ": "central_asia",
    "CU": "caribbean", "JM": "caribbean", "HT": "caribbean", "BS": "caribbean",
    "BB": "caribbean", "BM": "caribbean", "GD": "caribbean", "AG": "caribbean",
    "AW": "caribbean", "BQ": "caribbean", "CW": "caribbean", "KY": "caribbean",
    "VG": "caribbean",
    "GT": "central_america", "BZ": "central_america", "HN": "central_america",
    "NI": "central_america", "CR": "central_america", "SV": "central_america",
    "BG": "europe", "HR": "europe", "RO": "europe", "RS": "europe",
    "SK": "europe", "SI": "europe", "BA": "europe", "CY": "europe",
    "IS": "europe", "FO": "europe", "GI": "europe", "IM": "europe",
    "UA": "europe", "AL": "europe", "MK": "europe", "ME": "europe",
    "KP": "east_asia",
    "BN": "southeast_asia", "TL": "southeast_asia",
    "BO": "south_america", "EC": "south_america", "PY": "south_america",
    "GY": "south_america", "GF": "south_america", "UY": "south_america",
    "DZ": "africa", "TN": "africa", "CI": "africa", "CM": "africa",
    "MW": "africa", "MZ": "africa", "ZW": "africa", "RW": "africa",
    "UG": "africa", "SO": "africa", "SS": "africa", "CD": "africa",
    "BW": "africa",
    "CG": "africa", "CF": "africa", "BJ": "africa", "BF": "africa",
    "ML": "africa", "GM": "africa", "GN": "africa", "GQ": "africa",
    "SL": "africa", "SN": "africa", "DJ": "africa", "LY": "africa",
    "EH": "africa", "BI": "africa", "CV": "africa", "KM": "africa",
    "MG": "africa", "MR": "africa", "NE": "africa", "TD": "africa",
    "TG": "africa", "LS": "africa", "NA": "africa", "SZ": "africa",
    "SC": "africa", "ST": "africa", "ER": "africa", "GW": "africa",
    "IR": "middle_east", "IQ": "middle_east", "YE": "middle_east",
    "SY": "middle_east", "PS": "middle_east",
    "KI": "pacific_islands", "SB": "pacific_islands", "VU": "pacific_islands",
    "WS": "pacific_islands", "PG": "pacific_islands", "FJ": "pacific_islands",
    "TO": "pacific_islands", "FM": "pacific_islands", "MH": "pacific_islands",
    "PW": "pacific_islands", "NR": "pacific_islands", "TV": "pacific_islands",
    "CC": "pacific_islands", "YT": "pacific_islands", "MV": "south_asia",
    "MQ": "caribbean", "GL": "north_america", "GU": "pacific_islands",
}

DEFAULT_REGION = "global"

# ---------------------------------------------------------------------------
# Region base plate palettes (sky_top, sky_bottom, sun, far, mid, near)
# Travel-poster muted natural tones sampled from existing hero art.
# ---------------------------------------------------------------------------
RegionSpec = dict[str, tuple[int, int, int]]

REGIONS: dict[str, RegionSpec] = {
    "europe": {
        "sky_top": (46, 64, 94), "sky_bottom": (198, 164, 124),
        "sun": (238, 202, 138), "far": (110, 96, 96), "mid": (74, 66, 70),
        "near": (42, 38, 44),
    },
    "east_asia": {
        "sky_top": (52, 70, 92), "sky_bottom": (168, 176, 166),
        "sun": (226, 178, 120), "far": (96, 106, 108), "mid": (58, 66, 70),
        "near": (30, 36, 40),
    },
    "southeast_asia": {
        "sky_top": (38, 82, 92), "sky_bottom": (196, 172, 132),
        "sun": (240, 196, 140), "far": (84, 106, 98), "mid": (50, 72, 66),
        "near": (28, 40, 38),
    },
    "south_asia": {
        "sky_top": (70, 56, 86), "sky_bottom": (214, 158, 118),
        "sun": (246, 178, 116), "far": (108, 82, 88), "mid": (70, 52, 58),
        "near": (38, 30, 34),
    },
    "middle_east": {
        "sky_top": (66, 62, 92), "sky_bottom": (214, 164, 122),
        "sun": (244, 186, 122), "far": (124, 96, 82), "mid": (82, 62, 52),
        "near": (48, 36, 30),
    },
    "north_america": {
        "sky_top": (44, 66, 96), "sky_bottom": (188, 168, 150),
        "sun": (232, 184, 132), "far": (96, 102, 110), "mid": (62, 66, 74),
        "near": (36, 38, 44),
    },
    "south_america": {
        "sky_top": (40, 76, 84), "sky_bottom": (204, 158, 112),
        "sun": (238, 182, 112), "far": (78, 98, 84), "mid": (48, 66, 56),
        "near": (28, 38, 32),
    },
    "africa": {
        "sky_top": (74, 58, 66), "sky_bottom": (220, 164, 108),
        "sun": (248, 186, 110), "far": (126, 96, 66), "mid": (86, 64, 46),
        "near": (52, 38, 28),
    },
    "oceania": {
        "sky_top": (40, 78, 104), "sky_bottom": (178, 176, 156),
        "sun": (232, 196, 142), "far": (78, 104, 104), "mid": (48, 70, 72),
        "near": (28, 42, 44),
    },
    "central_asia": {
        "sky_top": (60, 68, 84), "sky_bottom": (206, 168, 124),
        "sun": (242, 190, 130), "far": (122, 100, 78), "mid": (80, 64, 50),
        "near": (46, 36, 30),
    },
    "caribbean": {
        "sky_top": (38, 92, 104), "sky_bottom": (210, 172, 132),
        "sun": (240, 196, 138), "far": (80, 116, 104), "mid": (46, 78, 68),
        "near": (26, 44, 40),
    },
    "central_america": {
        "sky_top": (40, 82, 88), "sky_bottom": (206, 162, 116),
        "sun": (238, 184, 116), "far": (76, 102, 88), "mid": (46, 68, 58),
        "near": (28, 40, 34),
    },
    "pacific_islands": {
        "sky_top": (38, 84, 112), "sky_bottom": (188, 184, 160),
        "sun": (236, 200, 148), "far": (70, 102, 104), "mid": (42, 70, 72),
        "near": (26, 44, 46),
    },
    "global": {
        "sky_top": (52, 68, 88), "sky_bottom": (196, 168, 128),
        "sun": (238, 192, 132), "far": (104, 100, 96), "mid": (66, 62, 60),
        "near": (40, 36, 36),
    },
}

# Building silhouette flavour per region (roof style distribution)
ROOF_FLAVOUR: dict[str, list[str]] = {
    "europe": ["flat", "gable", "spire", "dome"],
    "east_asia": ["flat", "pagoda", "gable", "tower"],
    "southeast_asia": ["gable", "flat", "spire", "stilt"],
    "south_asia": ["dome", "flat", "spire", "gable"],
    "middle_east": ["dome", "spire", "flat", "gable"],
    "north_america": ["flat", "tower", "flat", "spire"],
    "south_america": ["flat", "gable", "dome", "flat"],
    "africa": ["flat", "dome", "gable", "flat"],
    "oceania": ["flat", "gable", "tower", "flat"],
    "central_asia": ["dome", "flat", "spire", "gable"],
    "caribbean": ["gable", "flat", "dome", "stilt"],
    "central_america": ["flat", "gable", "dome", "stilt"],
    "pacific_islands": ["gable", "stilt", "flat", "tower"],
    "global": ["flat", "gable", "dome", "spire"],
}


def _shift_color(c: tuple[int, int, int], hue: float, light: float) -> tuple[int, int, int]:
    """Small deterministic hue rotation + lightness shift (HSI-ish)."""
    r, g, b = (v / 255.0 for v in c)
    h, s, v = colorsys.rgb_to_hsv(r, g, b)
    h = (h + hue) % 1.0
    v = min(1.0, max(0.08, v * light))
    r, g, b = colorsys.hsv_to_rgb(h, s, v)
    return (int(r * 255), int(g * 255), int(b * 255))


def _city_seed(city_id: str) -> int:
    return int.from_bytes(hashlib.sha256(city_id.encode("utf-8")).digest()[:4], "big")


# ---------------------------------------------------------------------------
# Drawing helpers
# ---------------------------------------------------------------------------
def _vgradient(w: int, h: int, top: tuple[int, int, int],
               bottom: tuple[int, int, int]) -> Image.Image:
    g = np.zeros((h, w, 3), dtype=np.uint8)
    t = np.linspace(0, 1, h, dtype=np.float32)[:, None, None]
    c_top = np.array(top, dtype=np.float32)
    c_bot = np.array(bottom, dtype=np.float32)
    g[:] = (c_top * (1 - t) + c_bot * t).astype(np.uint8)
    return Image.fromarray(g, "RGB")


def _sun(img: Image.Image, cx: float, cy: float, radius: int,
         color: tuple[int, int, int], alpha: float = 1.0) -> None:
    """Soft sun disc with halo via a blurred white-ish gradient ellipse."""
    layer = Image.new("RGB", img.size, (0, 0, 0))
    d = ImageDraw.Draw(layer)
    halo = max(radius * 2, 8)
    d.ellipse([cx - halo, cy - halo, cx + halo, cy + halo],
              fill=tuple(int(v + (255 - v) * 0.35) for v in color))
    layer = layer.filter(ImageFilter.GaussianBlur(radius * 0.6))
    d2 = ImageDraw.Draw(layer)
    d2.ellipse([cx - radius, cy - radius, cx + radius, cy + radius], fill=color)
    mask = layer.convert("L")
    if alpha < 1.0:
        mask = mask.point(lambda p: int(p * alpha))
    img.paste(layer, (0, 0), mask)


def _silhouette(img: Image.Image, y_base: int, color: tuple[int, int, int],
                rng: random.Random, roofs: list[str], y_top: int | None = None,
                gap: int = 2) -> None:
    """Draw a rectilinear skyline band ending at y_base with varied roofs."""
    d = ImageDraw.Draw(img)
    y_top = y_top or (y_base - rng.randint(70, 180))
    x = 0
    while x < W:
        bw = rng.randint(24, 64)
        bh = int((y_base - y_top) * rng.uniform(0.45, 1.0))
        top = y_base - bh
        roof = rng.choice(roofs)
        body = [x, top, x + bw, y_base]
        d.rectangle(body, fill=color)
        if roof == "gable":
            d.polygon([(x, top), (x + bw // 2, top - bw * 0.45),
                       (x + bw, top)], fill=color)
        elif roof == "spire":
            d.polygon([(x + bw * 0.25, top), (x + bw // 2, top - bw * 0.9),
                       (x + bw * 0.75, top)], fill=color)
        elif roof == "dome":
            d.ellipse([x, top - bw * 0.6, x + bw, top + bw * 0.2], fill=color)
        elif roof == "pagoda":
            layers = rng.randint(2, 3)
            for i in range(layers):
                lw = bw * (0.9 - i * 0.2)
                lx = x + (bw - lw) / 2
                ly = top + i * bw * 0.18
                d.polygon([(lx, ly + bw * 0.18), (lx + lw, ly + bw * 0.18),
                           (lx + lw + bw * 0.08, ly), (lx - bw * 0.08, ly)],
                          fill=color)
        elif roof == "stilt":
            d.polygon([(x + bw * 0.1, top), (x + bw * 0.9, top),
                       (x + bw, top + bw * 0.4), (x, top + bw * 0.4)],
                      fill=color)
        # tower variant: thin tall block with setback
        if roof == "tower":
            d.rectangle([x + bw * 0.2, top - bh * 0.5, x + bw * 0.8, top],
                        fill=color)
        x += bw + gap


def _ground(img: Image.Image, y: int, near: tuple[int, int, int],
            far: tuple[int, int, int]) -> None:
    arr = np.asarray(img).astype(np.float32)
    c_far = np.array(far, dtype=np.float32)
    c_near = np.array(near, dtype=np.float32)
    band = np.clip((arr.shape[0] - y), 1, None)
    t = np.linspace(0, 1, band, dtype=np.float32)[:, None, None]
    arr[y:, :, :] = (c_far * (1 - t) + c_near * t).astype(np.uint8)
    img.paste(Image.fromarray(arr.astype(np.uint8), "RGB"), (0, 0))


def _grain(img: Image.Image, strength: int, seed: int) -> None:
    rng = np.random.default_rng(seed)
    noise = rng.integers(-strength, strength + 1, (H, W, 1), dtype=np.int16)
    arr = np.asarray(img).astype(np.int16) + noise
    img.paste(Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGB"), (0, 0))


def _safe_zone_darken(img: Image.Image, top_y: float = 0.8) -> None:
    """Gently darken the bottom ~20% so overlaid city name stays legible."""
    arr = np.asarray(img).astype(np.float32)
    n = int(H * (1 - top_y))
    t = np.linspace(0, 0.32, n, dtype=np.float32)[:, None, None]
    arr[-n:, :, :] = (arr[-n:, :, :] * (1 - t)).astype(np.uint8)
    img.paste(Image.fromarray(arr.astype(np.uint8), "RGB"), (0, 0))


# ---------------------------------------------------------------------------
# Public renderers
# ---------------------------------------------------------------------------
def render_city_plate(city_id: str, region: str,
                      spec: RegionSpec | None = None) -> Image.Image:
    """Render one city plate from its region spec + deterministic tint."""
    spec = spec or REGIONS[region]
    seed = _city_seed(city_id)
    rng = random.Random(seed)
    rng2 = random.Random(seed ^ 0x9E3779B9)

    hue_jitter = rng.uniform(-0.03, 0.03)
    light_jitter = rng.uniform(0.9, 1.1)
    # Sky top/bottom tint independently within a slightly wider band so cities
    # in the same region stay distinguishable beyond the silhouette layout.
    sky_top = _shift_color(spec["sky_top"], rng.uniform(-0.05, 0.05),
                           rng.uniform(0.9, 1.1))
    sky_bot = _shift_color(spec["sky_bottom"], rng.uniform(-0.05, 0.05),
                           rng.uniform(0.88, 1.08))
    sun = _shift_color(spec["sun"], hue_jitter, rng.uniform(0.95, 1.08))
    far = _shift_color(spec["far"], rng.uniform(-0.02, 0.02), rng.uniform(0.92, 1.08))
    mid = _shift_color(spec["mid"], rng.uniform(-0.02, 0.02), rng.uniform(0.92, 1.08))
    near = _shift_color(spec["near"], rng.uniform(-0.02, 0.02), rng.uniform(0.9, 1.06))

    img = _vgradient(W, H, sky_top, sky_bot)

    sun_x = W * rng.uniform(0.28, 0.72)
    sun_y = H * rng.uniform(0.26, 0.44)
    _sun(img, sun_x, sun_y, rng.randint(28, 44), sun)

    # far layer: low rolling silhouette band
    far_y = int(H * rng.uniform(0.62, 0.68))
    _silhouette(img, far_y, far, random.Random(seed ^ 0x1111),
                ["flat"] * 6, y_top=int(H * rng.uniform(0.5, 0.56)), gap=3)

    # mid layer: region-flavoured skyline
    mid_y = int(H * rng.uniform(0.7, 0.78))
    roofs = ROOF_FLAVOUR.get(region, ROOF_FLAVOUR["global"])
    _silhouette(img, mid_y, mid, rng2, roofs,
                y_top=int(H * rng.uniform(0.56, 0.66)), gap=rng.randint(1, 3))

    _ground(img, int(H * rng.uniform(0.84, 0.9)), near, far)
    _grain(img, 6, seed ^ 0xFFFF)
    _safe_zone_darken(img)
    return img


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--force", action="store_true",
                    help="regenerate existing files too")
    ap.add_argument("--dry-run", action="store_true",
                    help="print plan without writing files")
    ap.add_argument("--contact-sheet", type=int, default=0, metavar="N",
                    help="also write a sampling contact sheet with N random cities")
    args = ap.parse_args()

    world = json.loads(WORLD_PATH.read_text(encoding="utf-8"))
    cities = world["cities"] if isinstance(world, dict) else world
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    plan: list[dict] = []
    skipped_foreign: list[str] = []
    for c in cities:
        cid = c["city_id"]
        if cid in PROTECTED_CITY_IDS:
            continue
        out = OUT_DIR / f"city_{cid}_hero_720.webp"
        if out.exists() and not args.force:
            continue
        if out.exists() and not _looks_generated(out):
            skipped_foreign.append(cid)
            continue
        region = REGION_BY_COUNTRY.get(c["country_id"], DEFAULT_REGION)
        plan.append({"city_id": cid, "region": region, "out": out})

    plan.sort(key=lambda p: p["city_id"])
    if args.dry_run:
        by_region: dict[str, int] = {}
        for p in plan:
            by_region[p["region"]] = by_region.get(p["region"], 0) + 1
        print(f"plan: {len(plan)} cities missing hero images")
        for r in sorted(by_region):
            print(f"  {r:18s} {by_region[r]:4d}")
        if skipped_foreign:
            print(f"skipped non-generated heroes: {len(skipped_foreign)}")
            for cid in sorted(skipped_foreign):
                print(f"  {cid}")
        return 0

    for i, p in enumerate(plan, 1):
        img = render_city_plate(p["city_id"], p["region"])
        img.save(p["out"], "WEBP", quality=82, method=6)
        print(f"[{i}/{len(plan)}] {p['city_id']} ({p['region']})")

    if args.contact_sheet > 0:
        SHEETS_DIR.mkdir(parents=True, exist_ok=True)
        rng = random.Random(20260802)
        candidates = [
            c for c in cities
            if c["city_id"] not in PROTECTED_CITY_IDS
            and (OUT_DIR / f"city_{c['city_id']}_hero_720.webp").exists()
        ]
        picks = rng.sample(candidates, min(args.contact_sheet, len(candidates)))
        cells, cell = 5, 5
        thumb = (W // cells, H // cells)
        sheet = Image.new("RGB", (thumb[0] * cells, thumb[1] * cell),
                          (30, 34, 40))
        for idx, p in enumerate(picks):
            # Read the already-rendered asset instead of re-rendering: identical
            # output, but a fraction of the cost.
            t = (Image.open(OUT_DIR / f"city_{p['city_id']}_hero_720.webp")
                 .resize(thumb))
            x = (idx % cells) * thumb[0]
            y = (idx // cells) * thumb[1]
            sheet.paste(t, (x, y))
        sheet_path = SHEETS_DIR / "hero_plates_contact.png"
        sheet.save(sheet_path)
        print(f"contact sheet -> {sheet_path}")

    # Self-verify: every non-protected city must have a 1280x720 WebP hero.
    failures = []
    for c in cities:
        if c["city_id"] in PROTECTED_CITY_IDS:
            continue
        p = OUT_DIR / f"city_{c['city_id']}_hero_720.webp"
        if not p.is_file():
            failures.append(f"{c['city_id']}: missing")
        elif not _looks_generated(p):
            failures.append(f"{c['city_id']}: wrong size/mode")
    if failures:
        print(f"SELF-CHECK FAILED: {len(failures)} problems")
        for f in failures[:20]:
            print(f"  {f}")
        return 1
    print(f"self-check OK: {len(cities) - len(PROTECTED_CITY_IDS)} cities covered")
    return 0


if __name__ == "__main__":
    sys.exit(main())
