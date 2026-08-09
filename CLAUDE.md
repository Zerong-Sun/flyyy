# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

《环球航商》Airborne Trader — an offline, single-player travel-and-trade simulation game. Players fly a real-world-style airline network between cities, buy local products, and arbitrage price differences. Content is Chinese-first (game UI/text is zh-authored; English fields are generated); code comments are English.

Three deliverables in this repo:

- `etl/` — Python pipeline that generates **all** game data (SQLite for validation, JSON for runtime)
- `game/` — Godot 4.x main client (reads only `game/data/*.json`)
- `ios/expo/` — Expo Go (React Native, SDK 54) mobile demo re-implementing the game logic

Requirements and process docs: `PRD_01.md`, `docs/` (`v0.2_REQUIREMENTS.md`, `v0.3_REQUIREMENTS.md`, `v1.0_GATE.md`, `CONTENT_ASSET_SPEC.md`), and per-feature plans/acceptance docs under `docs/superpowers/plans/`.

## Commands

Setup ETL venv once:

```bash
cd etl && python3 -m venv .venv && source .venv/bin/activate && pip install -r requirements.txt
```

Generate game data (required before running the game or data-dependent tests):

```bash
source etl/.venv/bin/activate
python etl/scripts/run_pipeline.py         # default: 20 authored hubs + 30 auto cities (dev iteration)
python etl/scripts/run_pipeline.py --full  # 500+ cities
```

Run the game:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --path game
```

Tests (pytest needs generated data in `game/data/`):

```bash
source etl/.venv/bin/activate
pytest tests/etl tests/game -q
pytest tests/etl/test_v3_aviation.py -q    # single file
```

Godot headless smoke regressions (`game/scripts/dev/Smoke*.gd`):

```bash
GODOT=/Applications/Godot.app/Contents/MacOS/Godot
$GODOT --headless --path game -s res://scripts/dev/SmokeV3Loop.gd      # full trade loop
$GODOT --headless --path game -s res://scripts/dev/SmokeChallenge.gd   # 30-day challenge
$GODOT --headless --path game -s res://scripts/dev/SmokeCollector.gd
$GODOT --headless --path game -s res://scripts/dev/SmokeCodex.gd
$GODOT --headless --path game -s res://scripts/dev/SmokeReputation.gd
$GODOT --headless --path game -s res://scripts/dev/SmokeContent.gd
$GODOT --headless --path game -s res://scripts/dev/SmokeAudio.gd
$GODOT --headless --path game -s res://scripts/dev/SmokePerf.gd
python tools/demo_smoke_logic.py
```

Godot integration verification scenes (`game/tests/verify_*.tscn` + `.gd`): each prints `VERIFY_*_OK` and exits 0 on success:

```bash
$GODOT --headless --path game res://tests/verify_news_events.tscn
```

Expo demo:

```bash
python tools/export_expo_data.py   # ETL → ios/expo/data/ios-data.json
cd ios/expo && npm test            # node --test src/__tests__/gameLogic.test.mjs
npx expo start
```

## Architecture

### Data pipeline (`etl/`)

Flow: raw public sources → validated SQLite (`etl/out/`) → split runtime JSON (`game/data/`).

- `scripts/01_fetch_sources.py` downloads raw sources (OurAirports, OpenFlights, BTS 2025-03, AeroSCOPE 2019) into `etl/raw/` (gitignored). The numbered 02–07 scripts are legacy; **`scripts/run_pipeline.py` is the single monolithic entry point** — every stage is a function in it (airports → routes → flights → cities/products/markets → validate → write SQLite → export JSON).
- **Determinism is a hard requirement**: every stochastic choice uses `stable_rand(*parts)` (sha256-seeded `random.Random`) and `_remote_demand` uses `zlib.crc32` — never Python's builtin `hash()` (salted per process, would break reproducible outputs). Add new randomness through these helpers, keyed by stable parts.
- Real-schedule layers merged into the synthetic schedule: BTS 2025-03 US-domestic flights (real flight numbers + CRS times, `data_confidence: "A"`), AeroSCOPE 2019 per-route frequencies (relative-normalized), and real OpenFlights airlines/routes — flight synthesis never fabricates an airline–route pair. Every flight carries `data_source` + `data_confidence`.
- Content authorship: per-city blurb in `etl/content/cities/{city_id}.json` and products in `etl/content/products/{city_id}.yaml`; cities without files fall back to country/region template inheritance. English `*_en` fields come from `etl/content/city_content_en.py` (hooked into the pipeline via `apply_en_fields`).
- Config: `etl/config/*.yaml` — `hubs_20.yaml` (20 authored hubs), `economy.yaml` (pricing + flight-synthesis parameters: schedule window 2025-03, delays, MCT, baggage), `airlines.yaml`, `dangerous_goods.yaml`.
- `game/data/` output is split for lazy loading: `world.json` (core), `markets/{city_id}.json`, `flights/{origin_iata}.json` + `_manifest.json`, `transfers/`, `product_market_tags.json`, `news_events.json`, `achievements.json`. **All of `game/data/` is gitignored** — it exists only after the pipeline runs.

### Godot client (`game/`)

Autoloads (registered in `project.godot`): `EventBus` (global signal bus), `DataService` (loads all JSON; lazily loads per-city markets and per-origin flights), `GameClock` (world time: 1 real s = 6 game min, baseline 2025-03-01 UTC), `AppState` (current city, inventory, cash), `SaveSystem`, `I18nService`, `AudioService`, plus autoloaded systems `AchievementSystem`, `ChallengeSystem`, `ReputationSystem`.

The other systems (`EconomySystem`, `FlightSearch`, `FlightOps`, `TicketService`, `InventorySystem`, `MarketEvents`, `NewsEvents`) are plain scripts that scenes instantiate — they resolve autoloads as globals. Smoke tests load them dynamically via `load("res://scripts/systems/X.gd")` and call `_process`/methods directly.

`main.tscn` = `Globe` (3D earth, `scripts/render/GlobeController.gd`) + `FlightOps` + `UI` (`MainHUD` and panels). Engine is locked to Godot 4.x Forward+; strict GDScript warnings are enabled in `project.godot` (`gdscript/warnings/unsafe_*` = 1) — new code should avoid dynamic-access warnings.

### Test pyramid

1. `pytest tests/etl/` — pipeline-rule tests over the generated JSON/SQLite (fail if data wasn't generated; `tests/helpers.py` loads the split files)
2. `pytest tests/game/` — data-surface checks (achievements, transfer edges, art sheets)
3. `game/tests/verify_*.gd` — Godot integration verification scenes (each a bare node scene; run headless or in the editor; quit code 0/1)
4. `game/scripts/dev/Smoke*.gd` — headless end-to-end regressions, the automated equivalents of manual test scripts
5. `tools/demo_smoke_logic.py` — pure-logic smoke test

### Content-generation tools (`tools/`)

`art-gen-kit/` and `audio-gen-kit/` are self-contained venvs (`tools/*-gen-kit/.venv`, each with its own README and requirements) for generating art sheets and CC0 audio. `tools/geo/` holds cached Natural Earth GeoJSON (fetched via `tools/fetch_geo_data.py`). `tools/export_expo_data.py` / `tools/export_ios_data.py` export subsets of game data for the mobile demo.

## Design constraints

- No teleportation: player movement requires a scheduled flight; all times in data are UTC, local times derived via `tz_offsets`.
- Product catalog must exclude alcohol, tobacco, drugs, weapons (PRD design boundary).
- Trade economy: base currency USD (frozen USD/CNY = 7.2); pricing/synthesis constants live in `economy.yaml`, not in code.
- `game/data/*.json`, `etl/raw/`, `etl/out/` are generated artifacts — never edit by hand; change the pipeline (or `etl/content/` for authored text) and re-run.
