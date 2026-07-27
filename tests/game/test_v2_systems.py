"""MR4 runtime data surface checks (transfer edges + achievements definitions)."""
from __future__ import annotations

import json
from pathlib import Path

from tests.helpers import load_transfer_edges, load_product_market_tags

ROOT = Path(__file__).resolve().parents[2]
WORLD = json.loads((ROOT / "game/data/world.json").read_text(encoding="utf-8"))
ACH = json.loads((ROOT / "game/data/achievements.json").read_text(encoding="utf-8"))
TRANSFER_EDGES = load_transfer_edges()
PRODUCT_MARKET_TAGS = load_product_market_tags()


def test_transfer_edges_loaded_in_world():
    edges = TRANSFER_EDGES
    assert isinstance(edges, dict)
    assert len(edges) > 0
    sample_key = next(iter(edges))
    assert "|" in sample_key
    sample = edges[sample_key]
    assert isinstance(sample, list)
    assert "hub" in sample[0]
    assert "total_distance_km" in sample[0]


def test_product_market_tags_present():
    tags = PRODUCT_MARKET_TAGS
    assert len(tags) > 0
    sample = next(iter(tags.values()))
    assert set(sample.keys()) >= {"hot", "normal", "cold"}


def test_achievements_minimum_set():
    defs = ACH.get("achievements", [])
    assert len(defs) >= 30
    cats = {a["category"] for a in defs}
    assert cats >= {"explore", "trade", "flight", "collect"}
    ids = {a["id"] for a in defs}
    assert "ach_explore_first_city" in ids
    assert "ach_flight_connection" in ids
    assert "ach_trade_intel" in ids
    for a in defs:
        assert a.get("stat_key")
        assert a.get("target") is not None
        assert a.get("name")
        assert a.get("desc")
    # Guard against duplicate achievements: no two defs within the same category
    # share the same (stat_key, target) — cross-category overlaps are intentional
    seen: dict[str, set[tuple[str, float]]] = {}
    for a in defs:
        cat = a["category"]
        if cat not in seen:
            seen[cat] = set()
        pair = (a["stat_key"], float(a["target"]))
        assert pair not in seen[cat], f"Duplicate ({cat}) stat_key+target pair: {pair}"
        seen[cat].add(pair)


def test_inherited_products_have_flag():
    c_cities = [c for c in WORLD["cities"] if c.get("content_confidence") == "C"]
    inherited = [p for p in WORLD["products"] if p.get("inherited_from")]
    if c_cities:
        assert len(inherited) > 0
        for p in inherited:
            assert p["inherited_from"] in ("country_template", "region_template", "region", "country")
    else:
        print(f"Info: {len(inherited)} inherited products (no C-confidence cities)")
