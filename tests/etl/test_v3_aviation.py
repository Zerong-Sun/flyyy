"""v0.3 aviation data layer: MCT, alliances, stopovers, reliability, cold-chain, DG."""
from __future__ import annotations

import json
from pathlib import Path

import pytest
import yaml

ROOT = Path(__file__).resolve().parents[2]
CFG = ROOT / "etl" / "config"
GAME_DATA = ROOT / "game" / "data"


def test_airlines_yaml_alliances_cover_catalog():
    raw = yaml.safe_load((CFG / "airlines.yaml").read_text(encoding="utf-8"))
    alliance_ids = {a["id"] for a in raw["alliances"]}
    assert {"star", "oneworld", "skyteam", "none"} <= alliance_ids
    for row in raw["airlines"]:
        assert row["alliance_id"] in alliance_ids
        assert row["id"] and row["name"]


def test_dangerous_goods_classes_matrix():
    dg = yaml.safe_load((CFG / "dangerous_goods.yaml").read_text(encoding="utf-8"))
    classes = dg["classes"]
    assert classes["none"]["cabin_ok"] is True
    assert classes["restricted_cabin"]["cabin_ok"] is False
    assert classes["restricted_cabin"]["cargo_ok"] is True
    assert classes["forbidden"]["cabin_ok"] is False
    assert "机械" in dg["category_defaults"]


def test_economy_v3_keys():
    eco = yaml.safe_load((CFG / "economy.yaml").read_text(encoding="utf-8"))
    assert eco["ticket"]["first_multiplier"] >= eco["ticket"]["business_multiplier"]
    assert eco["ticket"]["baggage_first_kg"] > eco["ticket"]["baggage_business_kg"]
    assert "cold" in eco["baggage_extras"]
    assert eco["baggage_extras"]["cold"].get("enables_cold_chain") is True
    assert eco["mct"]["default_min"] >= 60
    assert eco["reliability"]["delay_prob"] < 0.5
    assert eco["cold_chain"]["protected_decay_mult"] < eco["cold_chain"]["unprotected_decay_mult"]


def test_airport_mct_helper():
    from etl.scripts import run_pipeline as rp

    eco = {"mct": {"default_min": 90, "international_min": 120}}
    ap = {"mct_minutes": 75}
    assert rp.airport_mct_minutes(ap, eco) == 75
    assert rp.airport_mct_minutes({}, eco, international=True) == 120
    assert rp.airport_mct_minutes({}, eco, international=False) == 90


def test_hazmat_and_cold_helpers():
    from etl.scripts import run_pipeline as rp

    rp._DG_RULES = yaml.safe_load((CFG / "dangerous_goods.yaml").read_text(encoding="utf-8"))
    assert rp.resolve_hazmat_class("机械") == "restricted_cabin"
    assert rp.resolve_hazmat_class("茶叶") == "none"
    assert rp.product_requires_cold("食品", 24, "none") is True
    assert rp.product_requires_cold("工艺品", 99999, "none") is False


def test_world_json_v3_fields_if_present():
    """When world.json has been regenerated with etl 0.3, assert schema."""
    path = GAME_DATA / "world.json"
    if not path.exists():
        pytest.skip("world.json missing")
    world = json.loads(path.read_text(encoding="utf-8"))
    meta = world.get("meta") or {}
    # Accept pre-0.3 until pipeline re-run; soft assert structure when version bumps
    if str(meta.get("etl_version", "")).startswith("0.3"):
        eco = world["economy"]
        assert "mct" in eco
        assert "reliability" in eco
        assert "cold_chain" in eco
        assert world.get("alliances")
        assert world.get("dangerous_goods")
        airlines = world["airlines"]
        assert all("alliance_id" in a for a in airlines)
        products = world["products"]
        assert all("hazmat_class" in p for p in products)
        assert any(p.get("requires_cold_chain") for p in products)
        airports = world["airports"]
        assert any("mct_minutes" in a for a in airports)
        report = world.get("coverage_report") or {}
        assert report.get("etl_version") == "0.3.0"
        assert "stopover_flights" in report


def test_transfer_edge_includes_mct_when_built():
    from etl.scripts.run_pipeline import build_transfer_edges

    airports = {
        "AAA": {"latitude": 0.0, "longitude": 0.0, "country_id": "AA", "mct_minutes": 80},
        "HHH": {"latitude": 10.0, "longitude": 10.0, "country_id": "HH", "mct_minutes": 100},
        "BBB": {"latitude": 20.0, "longitude": 20.0, "country_id": "BB"},
        "CCC": {"latitude": 5.0, "longitude": 5.0, "country_id": "CC"},
        "DDD": {"latitude": 15.0, "longitude": 15.0, "country_id": "DD"},
        "EEE": {"latitude": 8.0, "longitude": 8.0, "country_id": "EE"},
        "FFF": {"latitude": 12.0, "longitude": 12.0, "country_id": "FF"},
        "GGG": {"latitude": 18.0, "longitude": 18.0, "country_id": "GG"},
        "III": {"latitude": 22.0, "longitude": 22.0, "country_id": "II"},
        "JJJ": {"latitude": 25.0, "longitude": 25.0, "country_id": "JJ"},
    }
    # Build a star hub HHH with degree >= 8
    iatas = list(airports.keys())
    routes = set()
    for other in iatas:
        if other == "HHH":
            continue
        routes.add(("HHH", other))
        routes.add((other, "HHH"))
    # No direct AAA→BBB so transfer via HHH should exist
    eco = {"mct": {"default_min": 90, "international_min": 120, "max_connection_min": 480}}
    edges = build_transfer_edges(routes, airports, iatas, eco)
    key = "AAA|BBB"
    assert key in edges
    assert edges[key][0]["hub"] == "HHH"
    assert edges[key][0]["mct_minutes"] == 100
