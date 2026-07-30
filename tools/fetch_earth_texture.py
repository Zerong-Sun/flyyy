#!/usr/bin/env python3
"""Download NASA Blue Marble equirectangular texture for GlobeController.

Source (public domain, NASA):
  https://eoimages.gsfc.nasa.gov/images/imagerecords/57000/57752/land_ocean_ice_cloud_2048.jpg

Output:
  game/assets/earth/earth_albedo_day_2k.png  (2048×1024)
"""

from __future__ import annotations

import sys
import urllib.request
from io import BytesIO
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
OUT_PATH = ROOT / "game" / "assets" / "earth" / "earth_albedo_day_2k.png"
SOURCE_URL = (
    "https://eoimages.gsfc.nasa.gov/images/imagerecords/57000/57752/"
    "land_ocean_ice_cloud_2048.jpg"
)
TARGET_SIZE = (2048, 1024)


def fetch_and_convert() -> None:
    print(f"Downloading {SOURCE_URL} …")
    with urllib.request.urlopen(SOURCE_URL, timeout=120) as resp:
        data = resp.read()
    img = Image.open(BytesIO(data)).convert("RGB")
    if img.size != TARGET_SIZE:
        print(f"Resizing {img.size[0]}×{img.size[1]} → {TARGET_SIZE[0]}×{TARGET_SIZE[1]}")
        img = img.resize(TARGET_SIZE, Image.Resampling.LANCZOS)
    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    img.save(OUT_PATH, "PNG", optimize=True)
    print(f"Saved {OUT_PATH} ({OUT_PATH.stat().st_size // 1024} KB)")


if __name__ == "__main__":
    try:
        fetch_and_convert()
    except Exception as exc:
        print(f"Error: {exc}", file=sys.stderr)
        sys.exit(1)
