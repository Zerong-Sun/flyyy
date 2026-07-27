"""Shared helpers for loading the split game data files in tests."""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DATA_DIR = ROOT / "game" / "data"


def load_markets_flat() -> list[dict]:
    """Load markets.json and expand the compact format into the old flat format.

    markets.json format: {"city_id": [{"p": product_id, "b": buy, "s": sell}, ...], ...}
    Returns: [{"city_id": ..., "product_id": ..., "buy_base_usd": ..., "sell_base_usd": ...}, ...]
    """
    markets = json.loads((DATA_DIR / "markets.json").read_text(encoding="utf-8"))
    flat: list[dict] = []
    for city_id, entries in markets.items():
        for entry in entries:
            flat.append({
                "city_id": city_id,
                "product_id": entry["p"],
                "buy_base_usd": entry["b"],
                "sell_base_usd": entry["s"],
            })
    return flat


def load_product_market_tags() -> dict:
    """Load product_market_tags.json."""
    return json.loads((DATA_DIR / "product_market_tags.json").read_text(encoding="utf-8"))


def load_transfer_edges() -> dict:
    """Load transfer_edges.json."""
    return json.loads((DATA_DIR / "transfer_edges.json").read_text(encoding="utf-8"))
