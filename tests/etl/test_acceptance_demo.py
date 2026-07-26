"""PRD §27 automated acceptance checks against exported Demo data."""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WORLD = json.loads((ROOT / "game" / "data" / "world.json").read_text(encoding="utf-8"))
FLIGHTS = json.loads((ROOT / "game" / "data" / "flights.json").read_text(encoding="utf-8"))


def test_s27_1_twenty_hubs_searchable():
    assert len(WORLD["airports"]) == 20
    iatas = {a["iata"] for a in WORLD["airports"]}
    assert "PVG" in iatas and "LHR" in iatas and "ATL" in iatas


def test_s27_3_baseline_and_clock_meta():
    assert WORLD["meta"]["baseline_date"] == "2025-03-01"
    assert WORLD["economy"]["starting_cash_usd"] > 1000


def test_s27_5_tz_offsets_dst():
    tz = WORLD["tz_offsets"]["America/New_York"]
    assert tz["2025-03-08"] == -5.0
    assert tz["2025-03-10"] == -4.0


def test_s27_8_business_10x():
    sample = FLIGHTS["by_origin"]["pvg"][0]
    assert abs(sample["ticket_base_price_business"] - sample["ticket_base_price_economy"] * 10) < 0.05


def test_s27_10_baggage_tiers():
    extras = WORLD["economy"]["baggage_extras"]
    assert extras["light"]["extra_kg"] == 10
    assert extras["standard"]["extra_kg"] == 20
    assert extras["heavy"]["extra_kg"] == 50
    assert extras["cargo_per_50kg_usd"] > 0


def test_s27_18_city_content():
    assert len(WORLD["cities"]) == 20
    for c in WORLD["cities"]:
        assert len(c["short_description"]) >= 80
        assert len(c["overview"]) >= 150
    by = {}
    for p in WORLD["products"]:
        by.setdefault(p["origin_city_id"], 0)
        by[p["origin_city_id"]] += 1
    assert all(n >= 5 for n in by.values())


def test_s27_21_22_attribution_disclaimer():
    assert "重建" in WORLD["disclaimer"]
    assert WORLD["attributions"]
    assert any("OurAirports" in a["name"] for a in WORLD["attributions"])


def test_route_outdegree_min_8():
    deg = {}
    for r in WORLD["routes"]:
        deg[r["origin"]] = deg.get(r["origin"], 0) + 1
    assert len(deg) == 20
    assert min(deg.values()) >= 8
