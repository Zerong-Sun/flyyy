"""English city-text generation for the ETL pipeline (Step 3 i18n).

Policy:
- Demo 20 hubs: hand-authored English corpus (cities_en_data.DEMO20_EN).
- All other cities (C-confidence or pending translation): generic template
  that mirrors the Chinese placeholder style, so every city carries the full
  set of 7 `*_en` fields and the UI never blanks out.

Field name mapping (data-file short keys -> world.json keys):
    short_description_en, overview_en, history_en, geography_en,
    economy_en, food_en, travel_en
"""
from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from etl.content import cities_en_data

REPO_ROOT = Path(__file__).resolve().parents[2]
WORLD_JSON = REPO_ROOT / "game" / "data" / "world.json"

# short key (in DEMO20_EN) -> world.json field name
FIELD_EN_MAP: dict[str, str] = {
    "short_description_en": "short_description_en",
    "overview_en": "overview_en",
    "history_en": "history_summary_en",
    "geography_en": "geography_summary_en",
    "economy_en": "economy_summary_en",
    "food_en": "food_summary_en",
    "travel_en": "travel_note_en",
}

_TEMPLATE_PLACEHOLDER = (
    "Further details will be added in a future content update. "
    "Please keep to essential goods and follow local trading rules."
)


def _template_en(city: dict[str, Any]) -> dict[str, str]:
    name_en = str(city.get("name_en") or city.get("city_id") or "This city")
    return {
        "short_description_en": (
            f"{name_en} sits on the reconstructed flight network as a trading "
            f"stopover, with more details arriving in a future update."
        ),
        "overview_en": (
            f"{name_en} serves as a route node connecting the surrounding region; "
            f"travellers may stop here to pick up local specialty goods. "
            f"Public reference data is limited for now."
        ),
        "history_summary_en": _TEMPLATE_PLACEHOLDER,
        "geography_summary_en": _TEMPLATE_PLACEHOLDER,
        "economy_summary_en": _TEMPLATE_PLACEHOLDER,
        "food_summary_en": _TEMPLATE_PLACEHOLDER,
        "travel_note_en": _TEMPLATE_PLACEHOLDER,
    }


def _short_description_from_overview(en: dict[str, str]) -> str:
    overview = en.get("overview_en", "")
    first = overview.split(";", 1)[0].split(". ", 1)[0].strip()
    if len(first) > 150:
        first = first[:147].rstrip() + "..."
    return first or overview[:150]


def en_fields_for_city(city: dict[str, Any]) -> dict[str, str]:
    """Return the 7 `*_en` world.json fields for one city record."""
    seed = cities_en_data.DEMO20_EN.get(str(city.get("city_id") or ""))
    if seed:
        out = {FIELD_EN_MAP[k]: v for k, v in seed.items() if k in FIELD_EN_MAP}
        out["short_description_en"] = _short_description_from_overview(out)
    else:
        out = _template_en(city)
    return out


def apply_en_fields(cities: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Attach `*_en` fields onto each city dict (in place) and return them."""
    for city in cities:
        for k, v in en_fields_for_city(city).items():
            city[k] = v
    return cities


def _cli() -> int:
    if not WORLD_JSON.exists():
        print(f"ERROR: {WORLD_JSON} not found; run the pipeline first")
        return 1
    payload = json.loads(WORLD_JSON.read_text(encoding="utf-8"))
    cities = payload.get("cities", [])
    apply_en_fields(cities)
    WORLD_JSON.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    hub_ids = set(cities_en_data.DEMO20_EN.keys())
    authored = sum(1 for c in cities if c["city_id"] in hub_ids)
    missing = [
        c["city_id"] for c in cities
        if any(not str(c.get(k, "")).strip() for k in FIELD_EN_MAP.values())
    ]
    print(
        f"city *_en: {len(cities)} cities, {authored} hub-authored, "
        f"{len(cities) - authored} templated, missing={missing or 'none'}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(_cli())
