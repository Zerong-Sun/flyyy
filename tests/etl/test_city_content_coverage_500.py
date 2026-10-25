"""Coverage gate for the playable city copy and credited city photographs."""
from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
CITY_DIR = ROOT / "etl/content/cities"
ASSET_DIR = ROOT / "game/assets/cities"
WORLD = json.loads((ROOT / "game/data/world.json").read_text(encoding="utf-8"))
FIELDS = (
    "short_description", "overview", "history_summary", "geography_summary",
    "economy_summary", "food_summary", "travel_note",
)
PLACEHOLDERS = (
    "更多细节将在", "结构化资料可确认", "旅客可在此采购特色商品",
    "城市作为全球航线节点", "适合体验地方特产贸易与跨区价差",
)


def test_all_playable_cities_have_real_copy_in_source_and_runtime():
    cities = WORLD["cities"]
    assert len(cities) == 500
    assert len({city["city_id"] for city in cities}) == 500
    for city in cities:
        cid = city["city_id"]
        source = json.loads((CITY_DIR / f"{cid}.json").read_text(encoding="utf-8"))
        assert city["content_confidence"] in {"A", "B"}, cid
        assert source["name_zh"] == city["name_zh"], cid
        assert source["source_ids"], cid
        for field in FIELDS:
            text = city[field].strip()
            assert text and text != "。", (cid, field)
            assert not any(marker in text for marker in PLACEHOLDERS), (cid, field)


def test_one_hundred_featured_cities_have_credited_local_photos():
    credits = json.loads((ASSET_DIR / "photo_credits.json").read_text(encoding="utf-8"))
    assert len(credits) == 100
    by_id = {city["city_id"]: city for city in WORLD["cities"]}
    assert "tianjin" in credits
    for cid, credit in credits.items():
        assert cid in by_id
        assert credit["author"] and credit["license"] and credit["source_url"]
        assert credit["source_url"].startswith("https://commons.wikimedia.org/wiki/File:")
        stem = by_id[cid]["image_asset_id"]
        assert stem == f"city_{cid}_photo_720"
        assert any((ASSET_DIR / (stem + ext)).is_file()
                   for ext in (".jpg", ".png", ".webp")), cid
