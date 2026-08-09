#!/usr/bin/env python3
"""Fetch OurAirports + OpenFlights + BTS + AeroSCOPE source CSVs (best-effort; offline fallbacks exist)."""
from __future__ import annotations

import io
import urllib.request
import zipfile
from pathlib import Path

RAW = Path(__file__).resolve().parents[1] / "raw"
SOURCES = {
    "airports.csv": "https://davidmegginson.github.io/ourairports-data/airports.csv",
    "countries.csv": "https://davidmegginson.github.io/ourairports-data/countries.csv",
    "routes.dat": "https://raw.githubusercontent.com/jpatokal/openflights/master/data/routes.dat",
    "airlines.dat": "https://raw.githubusercontent.com/jpatokal/openflights/master/data/airlines.dat",
    # BTS 2025-03 Marketing Carrier On-Time (US domestic real flight numbers + CRS times).
    "bts_on_time_2025_3.zip": (
        "https://transtats.bts.gov/PREZIP/On_Time_Marketing_Carrier_On_Time_Performance_"
        "Beginning_January_2018_2025_3.zip"
    ),
    # AeroSCOPE 2019 global traffic (route annual n_flights for relative frequency).
    "AeroSCOPE_2019.csv": (
        "https://zenodo.org/records/10143773/files/AeroSCOPE_global_aviation_traffic_dataset_16_11.csv"
        "?download=1"
    ),
}

# BTS zip filename pattern: On_Time_Marketing_Carrier_On_Time_Performance_2025_3.csv
BTS_EXTRACTED_NAME = "bts_on_time_2025_3.csv"


def _fetch(name: str, url: str) -> None:
    dest = RAW / name
    print(f"Fetching {name} ...")
    try:
        if name.endswith(".zip"):
            raw = urllib.request.urlopen(url, timeout=600).read()
            with zipfile.ZipFile(io.BytesIO(raw)) as zf:
                csv_members = [n for n in zf.namelist() if n.lower().endswith(".csv")]
                if not csv_members:
                    print(f"  WARN: no CSV inside {name}; skipping")
                    return
                zf.extract(csv_members[0], RAW)
                extracted = RAW / Path(csv_members[0]).name
                if extracted != dest:
                    extracted.replace(dest)
            print(f"  OK -> {dest} ({dest.stat().st_size} bytes)")
        else:
            urllib.request.urlretrieve(url, dest)
            print(f"  OK -> {dest} ({dest.stat().st_size} bytes)")
    except Exception as exc:  # noqa: BLE001
        print(f"  WARN: {exc}")
        if not dest.exists():
            print("  No local copy; pipeline will use embedded fallbacks.")


def main() -> None:
    RAW.mkdir(parents=True, exist_ok=True)
    for name, url in SOURCES.items():
        _fetch(name, url)


if __name__ == "__main__":
    main()
