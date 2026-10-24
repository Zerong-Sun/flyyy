#!/usr/bin/env python3
"""Fetch OurAirports + OpenFlights + BTS + AeroSCOPE source CSVs (best-effort; offline fallbacks exist)."""
from __future__ import annotations

import argparse
import shutil
import tempfile
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


def _fetch(name: str, url: str) -> bool:
    dest = RAW / (BTS_EXTRACTED_NAME if name.endswith('.zip') else name)
    print(f"Fetching {name} ...", flush=True)
    try:
        # Stage on the same filesystem: incomplete downloads never replace a
        # working local snapshot. Stream large BTS data instead of holding it in RAM.
        with tempfile.TemporaryDirectory(prefix='.fetch-', dir=RAW) as directory:
            downloaded = Path(directory) / 'download'
            with urllib.request.urlopen(url, timeout=60) as response, downloaded.open('wb') as output:
                shutil.copyfileobj(response, output, length=1024 * 1024)
            payload = downloaded
            if name.endswith('.zip'):
                payload = Path(directory) / 'schedule.csv'
                with zipfile.ZipFile(downloaded) as zf:
                    csv_members = [n for n in zf.namelist() if n.lower().endswith('.csv')]
                    if len(csv_members) != 1:
                        raise ValueError(f'Expected one CSV inside {name}, found {len(csv_members)}')
                    # Read the member directly; nested/untrusted member names
                    # cannot decide the output path.
                    with zf.open(csv_members[0]) as source, payload.open('wb') as output:
                        shutil.copyfileobj(source, output, length=1024 * 1024)
            if not payload.stat().st_size:
                raise ValueError(f'Empty source: {name}')
            payload.replace(dest)
        print(f"  OK -> {dest} ({dest.stat().st_size} bytes)", flush=True)
        return True
    except Exception as exc:  # noqa: BLE001
        print(f"  WARN: {exc}", flush=True)
        if not dest.exists():
            print("  No local copy; pipeline will use embedded fallbacks.")
        return False


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--strict', action='store_true', help='Fail if any source cannot be downloaded (CI)')
    args = parser.parse_args(argv)
    RAW.mkdir(parents=True, exist_ok=True)
    failed = []
    for name, url in SOURCES.items():
        if not _fetch(name, url):
            failed.append(name)
    if failed:
        print('Unavailable sources: ' + ', '.join(failed), flush=True)
    return int(args.strict and bool(failed))


if __name__ == "__main__":
    raise SystemExit(main())
