"""PRD §27 automated acceptance checks against exported Demo data."""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WORLD = json.loads((ROOT / "game" / "data" / "world.json").read_text(encoding="utf-8"))
PVG_FLIGHTS = json.loads((ROOT / "game" / "data" / "flights" / "pvg.json").read_text(encoding="utf-8"))


def test_s27_1_twenty_hubs_searchable():
    """Demo hub minimum baseline — expanded in v0.2 to 50+ cities."""
    assert len(WORLD["airports"]) >= 20
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
    sample = PVG_FLIGHTS[0]
    assert abs(sample["ticket_base_price_business"] - sample["ticket_base_price_economy"] * 10) < 0.05


def test_s27_10_baggage_tiers():
    extras = WORLD["economy"]["baggage_extras"]
    assert extras["light"]["extra_kg"] == 10
    assert extras["standard"]["extra_kg"] == 20
    assert extras["heavy"]["extra_kg"] == 50
    assert extras["cargo_per_50kg_usd"] > 0


def test_s27_18_city_content():
    """Extended in v0.2 — authored cities need content, inherited cities get templates."""
    assert len(WORLD["cities"]) >= 20
    # Authored cities must have full content
    for c in WORLD["cities"]:
        if c.get("content_confidence") != "C":
            assert len(c.get("short_description", "")) >= 80, f"{c['city_id']} short desc"
            assert len(c.get("overview", "")) >= 150, f"{c['city_id']} overview"
    by = {}
    for p in WORLD["products"]:
        by.setdefault(p["origin_city_id"], 0)
        by[p["origin_city_id"]] += 1
    authored = [c for c in WORLD["cities"] if c.get("content_confidence") != "C"]
    for c in authored:
        assert by.get(c["city_id"], 0) >= 5, f"{c['city_id']} only {by.get(c['city_id'], 0)} products"
    # All cities must have at least 3 products (via inheritance)
    all_assert = all(by.get(c["city_id"], 0) >= 3 for c in WORLD["cities"])
    assert all_assert, f"Some cities have fewer than 3 products"


def test_s27_21_22_attribution_disclaimer():
    assert "重建" in WORLD["disclaimer"]
    assert WORLD["attributions"]
    assert any("OurAirports" in a["name"] for a in WORLD["attributions"])


def test_route_outdegree_min_8():
    """Original 20 demo hubs must maintain >=8 connections."""
    DEMO_IATA = {"ATL", "DXB", "DFW", "DEN", "LHR", "ORD", "IST", "LAX", "HND",
                 "PVG", "CDG", "AMS", "CAN", "FRA", "PEK", "SIN", "ICN", "HKG",
                 "BKK", "MIA"}
    deg = {}
    for r in WORLD["routes"]:
        deg[r["origin"]] = deg.get(r["origin"], 0) + 1
    for iata in DEMO_IATA:
        assert deg.get(iata, 0) >= 8, f"{iata} degree {deg.get(iata, 0)}"
