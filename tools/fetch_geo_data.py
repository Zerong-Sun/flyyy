#!/usr/bin/env python3
"""Download Natural Earth 1:50m GeoJSON for the stylized earth generator.

Caches raw data under tools/geo/ (gitignored). Regenerating the earth
albedo texture with real coastlines + faint admin borders requires
running this first (or falling back to the embedded simplified data).

Sources (public domain, Natural Earth):
  - ne_50m_admin_0_countries.geojson          ~3.0 MB
  - ne_50m_admin_1_states_provinces.geojson   ~2.3 MB

Usage:
  python3 tools/fetch_geo_data.py
"""

from __future__ import annotations

import json
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GEO_DIR = ROOT / "tools" / "geo"

BASE = "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson"

FILES = {
    "ne_50m_admin_0_countries.geojson": f"{BASE}/ne_50m_admin_0_countries.geojson",
    "ne_50m_admin_1_states_provinces.geojson": f"{BASE}/ne_50m_admin_1_states_provinces.geojson",
}


def _download(url: str, dest: Path) -> None:
    print(f"Downloading {url} …")
    with urllib.request.urlopen(url, timeout=120) as resp:
        data = resp.read()
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_bytes(data)
    print(f"  saved {dest} ({len(data) // 1024} KB)")


def _validate(path: Path) -> None:
    with open(path, encoding="utf-8") as f:
        gj = json.load(f)
    feats = gj.get("features", [])
    if not feats:
        raise ValueError(f"{path.name}: no features")
    print(f"  {path.name}: {len(feats)} features")
    # Spot-check a property so downstream tools can rely on the schema.
    props = feats[0].get("properties", {})
    for key in ("ADM0_A3", "NAME"):
        if key not in props:
            print(f"  note: feature 0 lacks '{key}'")


def main() -> None:
    for name, url in FILES.items():
        dest = GEO_DIR / name
        if dest.exists():
            print(f"Exists, skipping: {dest}")
            try:
                _validate(dest)
            except Exception as exc:  # noqa: BLE001 - rebuild on corrupt cache
                print(f"  cache invalid ({exc}); re-downloading")
                _download(url, dest)
            continue
        _download(url, dest)
        _validate(dest)
    print("Done.")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:  # noqa: BLE001
        print(f"fetch_geo_data failed: {exc}", file=sys.stderr)
        sys.exit(1)
