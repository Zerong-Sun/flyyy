"""v0.2 coverage report + product inheritance tests."""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WORLD = json.loads((ROOT / "game" / "data" / "world.json").read_text(encoding="utf-8"))
CR = WORLD.get("coverage_report", {})
OUT = ROOT / "etl" / "out"


def test_coverage_report_exists():
    assert CR, "coverage_report should exist in world.json"
    # Also check the standalone file
    cr_path = OUT / "coverage_report.json"
    assert cr_path.exists(), "coverage_report.json should exist in etl/out"
    cr_file = json.loads(cr_path.read_text(encoding="utf-8"))
    assert cr_file["l2_cities"] == CR["l2_cities"]


def test_coverage_l2_cities():
    assert CR.get("l2_cities", 0) >= 20


def test_coverage_l1_airports():
    assert CR.get("l1_passenger_airports", 0) >= 20


def test_coverage_no_souvenir():
    assert not CR.get("has_souvenir_category", True), "souvenir category should be absent"


def test_coverage_transfer_edges():
    assert CR.get("transfer_edge_pairs", 0) > 0, "transfer edges should exist"


def test_coverage_product_categories_ge_5():
    assert CR.get("product_categories", 0) >= 5


def test_coverage_product_market_tags():
    assert CR.get("product_market_tag_pairs", 0) > 0, "product_market_tags should exist"


def test_product_inheritance_marks():
    """Inherited products must have 'inherited_from' field."""
    inherited = [p for p in WORLD["products"] if p.get("inherited_from")]
    assert len(inherited) > 0, "Should have inherited products"


def test_all_cities_have_min_3_products():
    """Every city must have at least 3 products (authored or inherited)."""
    by_city: dict[str, int] = {}
    for p in WORLD["products"]:
        by_city[p["origin_city_id"]] = by_city.get(p["origin_city_id"], 0) + 1
    for c in WORLD["cities"]:
        cid = c["city_id"]
        assert by_city.get(cid, 0) >= 3, f"{cid} has only {by_city.get(cid, 0)} products"


def test_passenger_service_field():
    """Airports should have has_passenger_service field."""
    for a in WORLD["airports"]:
        assert "has_passenger_service" in a, f"{a.get('iata', '?')}: missing has_passenger_service"
        assert "has_scheduled_service" in a, f"{a.get('iata', '?')}: missing has_scheduled_service"


def test_image_asset_id_field():
    """Cities should have image_asset_id field."""
    for c in WORLD["cities"]:
        assert "image_asset_id" in c, f"{c.get('city_id', '?')}: missing image_asset_id"
