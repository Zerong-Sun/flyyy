# ETL for Airborne Trader Demo

## Setup

```bash
cd etl
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

## Run

```bash
# optional: refresh OurAirports / OpenFlights
python scripts/01_fetch_sources.py

# build SQLite + Godot JSON
python scripts/run_pipeline.py
```

Outputs:

- `etl/out/world.sqlite`, `etl/out/flights_2025_03.sqlite`
- `game/data/world.json`, `game/data/flights.json` (+ sqlite copies)

Godot reads the JSON exports at runtime (generated from the validated SQLite snapshot).
