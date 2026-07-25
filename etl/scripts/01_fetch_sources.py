#!/usr/bin/env python3
"""Fetch OurAirports + OpenFlights source CSVs (best-effort; offline fallbacks exist)."""
from __future__ import annotations

import urllib.request
from pathlib import Path

RAW = Path(__file__).resolve().parents[1] / "raw"
SOURCES = {
    "airports.csv": "https://davidmegginson.github.io/ourairports-data/airports.csv",
    "countries.csv": "https://davidmegginson.github.io/ourairports-data/countries.csv",
    "routes.dat": "https://raw.githubusercontent.com/jpatokal/openflights/master/data/routes.dat",
    "airlines.dat": "https://raw.githubusercontent.com/jpatokal/openflights/master/data/airlines.dat",
}


def main() -> None:
    RAW.mkdir(parents=True, exist_ok=True)
    for name, url in SOURCES.items():
        dest = RAW / name
        print(f"Fetching {name} ...")
        try:
            urllib.request.urlretrieve(url, dest)
            print(f"  OK -> {dest} ({dest.stat().st_size} bytes)")
        except Exception as exc:  # noqa: BLE001
            print(f"  WARN: {exc}")
            if not dest.exists():
                print("  No local copy; pipeline will use embedded fallbacks.")


if __name__ == "__main__":
    main()
