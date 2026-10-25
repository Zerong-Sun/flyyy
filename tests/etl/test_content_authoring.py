import json
from pathlib import Path

import yaml

from etl.scripts.author_cities_wikidata import _snap
from etl.scripts.author_product_descriptions import _compose


ROOT = Path(__file__).resolve().parents[2]
CITIES = ROOT / "etl" / "content" / "cities"
PRODUCTS = ROOT / "etl" / "content" / "products"
FACTS = ROOT / "etl" / "content" / "wikidata_facts.json"

CITY_FIELDS = (
    "short_description", "overview", "history_summary", "geography_summary",
    "economy_summary", "food_summary", "travel_note",
)
FILLER_MARKERS = (
    "更多细节将在后续更新中扩展",
    "更多细节将在后续内容更新中扩展",
    "旅客可在此采购特色商品",
    "城市作为全球航线节点",
)


def test_snap_preserves_the_requested_maximum_length():
    assert _snap("甲" * 150, 150) == "甲" * 149 + "。"
    assert _snap("内容。。", 10) == "内容。"


def test_current_city_source_has_complete_nonplaceholder_copy():
    world = json.loads((ROOT / "game/data/world.json").read_text(encoding="utf-8"))
    assert len(world["cities"]) == 500
    for entry in world["cities"]:
        path = CITIES / f"{entry['city_id']}.json"
        city = json.loads(path.read_text(encoding="utf-8"))
        assert city["content_confidence"] in {"A", "B"}, path.name
        assert len(city["short_description"]) >= 60, path.name
        assert city["source_ids"], path.name
        for field in CITY_FIELDS:
            assert city[field].strip() and city[field] != "。", (path.name, field)
            assert not any(marker in city[field] for marker in FILLER_MARKERS), (path.name, field)


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
