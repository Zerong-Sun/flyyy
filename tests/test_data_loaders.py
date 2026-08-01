"""Regression tests for split game-data loaders."""
from __future__ import annotations

from tests.helpers import load_markets_flat, load_transfer_edges


def test_markets_flat_loads_split_files():
    markets = load_markets_flat()
    assert len(markets) > 0
    sample = markets[0]
    assert {"city_id", "product_id", "buy_base_usd", "sell_base_usd"} <= set(sample.keys())


def test_transfer_edges_loads_split_files():
    edges = load_transfer_edges()
    assert len(edges) > 0
    key = next(iter(edges))
    assert "|" in key
    assert isinstance(edges[key], list)
    assert "hub" in edges[key][0]
