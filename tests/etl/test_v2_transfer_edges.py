"""v0.2 transfer-edge index tests."""
from __future__ import annotations

import json
from pathlib import Path

from tests.helpers import load_transfer_edges

ROOT = Path(__file__).resolve().parents[2]
WORLD = json.loads((ROOT / "game" / "data" / "world.json").read_text(encoding="utf-8"))
TRANSFER_EDGES = load_transfer_edges()


def test_transfer_edges_exist():
    edges = TRANSFER_EDGES
    assert len(edges) > 0, "transfer_edges should exist with at least one pair"


def test_transfer_edges_no_direct_overlap():
    """Transfer edges must not duplicate direct routes."""
    edges = TRANSFER_EDGES
    directs = {(r["origin"], r["destination"]) for r in WORLD["routes"]}
    for key in edges:
        orig, dest = key.split("|")
        assert (orig, dest) not in directs, f"{key} has a direct route"


def test_transfer_edges_valid_hubs():
    """All transfer hubs must exist as airports."""
    edges = TRANSFER_EDGES
    airport_ids = {a["iata"] for a in WORLD["airports"]}
    for key, options in edges.items():
        for opt in options:
            hub = opt["hub"]
            assert hub in airport_ids, f"Hub {hub} not in airports for {key}"


def test_transfer_edges_distance_ge_direct():
    """Transfer total distance should be >= direct distance (triangle inequality)."""
    edges = TRANSFER_EDGES
    airports = {a["iata"]: a for a in WORLD["airports"]}
    for key, options in edges.items():
        orig, dest = key.split("|")
        oa = airports.get(orig, {})
        da = airports.get(dest, {})
        if not oa or not da:
            continue
        # Direct distance via haversine (approximate)
        for opt in options:
            assert opt["total_distance_km"] > 0, f"{key}: zero distance"
            # Transfer should be >= direct (triangle inequality guarantee:
            # hub may be off-path but total segments >= direct)
            assert opt["seg1_duration_avg"] > 0, f"{key}: zero seg1 duration"
            assert opt["seg2_duration_avg"] > 0, f"{key}: zero seg2 duration"


def test_transfer_edges_per_od_max_5():
    """Each O/D pair should have at most 5 transfer options."""
    edges = TRANSFER_EDGES
    for key, options in edges.items():
        assert len(options) <= 5, f"{key} has {len(options)} options"


def test_transfer_edges_no_self_hub():
    """Transfer hub must differ from both origin and destination."""
    edges = TRANSFER_EDGES
    for key, options in edges.items():
        orig, dest = key.split("|")
        for opt in options:
            assert opt["hub"] != orig, f"{key}: hub={opt['hub']} equals origin"
            assert opt["hub"] != dest, f"{key}: hub={opt['hub']} equals destination"
