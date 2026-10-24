# ETL for Wanli Trader Demo

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
python scripts/01_fetch_sources.py --strict

# build SQLite + Godot JSON
python scripts/run_pipeline.py
```

Outputs:

- `etl/out/world.sqlite`, `etl/out/flights_2025_03.sqlite`
- `game/data/world.json`, split `flights/`, `markets/`, `transfers/` (+ SQLite copies)
- `game/data/achievements.json`, `news_events.json`, `steam_achievements.json`

Small authored catalogs live in versioned `etl/config/runtime/`. The pipeline exports
them on every build and derives Steam names from the achievement IDs. Keep edits in
those source catalogs rather than the ignored `game/data/` output directory.

Godot reads the JSON exports at runtime (generated from the validated SQLite snapshot).
