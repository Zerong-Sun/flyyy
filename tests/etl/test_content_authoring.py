import json
from pathlib import Path

import yaml

from etl.scripts.author_cities_wikidata import CityWriter, _load_airports, _snap
from etl.scripts.author_product_descriptions import _compose


ROOT = Path(__file__).resolve().parents[2]
CITIES = ROOT / "etl" / "content" / "cities"
PRODUCTS = ROOT / "etl" / "content" / "products"
FACTS = ROOT / "etl" / "content" / "wikidata_facts.json"

CITY_LIMITS = {
    "short_description": (80, 150),
    "overview": (150, 300),
    "history_summary": (1, 250),
    "geography_summary": (1, 200),
    "economy_summary": (1, 200),
    "food_summary": (1, 200),
    "travel_note": (1, 150),
}
FILLER_MARKERS = (
    "更多细节将在后续更新中扩展",
    "更多细节将在后续内容更新中扩展",
    "旅客可在此采购特色商品",
    "城市作为全球航线节点",
)


def test_snap_preserves_the_requested_maximum_length():
    assert _snap("甲" * 150, 150) == "甲" * 149 + "。"
    assert _snap("内容。。", 10) == "内容。"


def test_city_content_matches_the_checked_in_generator_output():
    facts = json.loads(FACTS.read_text(encoding="utf-8"))
    writer = CityWriter(facts, _load_airports())
    checked = 0

    for path in sorted(CITIES.glob("*.json")):
        city = json.loads(path.read_text(encoding="utf-8"))
        if city.get("content_confidence") == "A":
            continue
        generated = writer.compose(city)
        checked += 1
        for field, (minimum, maximum) in CITY_LIMITS.items():
            assert city[field] == generated[field], f"{path.name}: stale {field}"
            assert minimum <= len(city[field]) <= maximum, path.name
            assert not any(marker in city[field] for marker in FILLER_MARKERS), path.name

    assert checked == 400


def test_product_descriptions_match_the_checked_in_generator_output():
    checked = 0
    for path in sorted(PRODUCTS.glob("*.yaml")):
        city_path = CITIES / f"{path.stem}.json"
        city = json.loads(city_path.read_text(encoding="utf-8"))
        rows = yaml.safe_load(path.read_text(encoding="utf-8"))["products"]
        for row in rows:
            assert row["description"] == _compose(row, city), row["product_id"]
            assert 40 <= len(row["description"]) <= 120, row["product_id"]
            checked += 1

    assert checked == 2500
