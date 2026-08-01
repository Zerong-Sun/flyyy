"""Shared helpers for loading the split game data files in tests."""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DATA_DIR = ROOT / "game" / "data"


def _load_markets_by_city() -> dict[str, list[dict]]:
    """Load per-city market files from game/data/markets/."""
    markets_dir = DATA_DIR / "markets"
    if markets_dir.is_dir():
        by_city: dict[str, list[dict]] = {}
        for path in sorted(markets_dir.glob("*.json")):
            by_city[path.stem] = json.loads(path.read_text(encoding="utf-8"))
        return by_city

    legacy = DATA_DIR / "markets.json"
    if legacy.exists():
        return json.loads(legacy.read_text(encoding="utf-8"))

    raise FileNotFoundError(
        f"No market data under {markets_dir} or {legacy}. Run the ETL pipeline first."
    )


def load_markets_flat() -> list[dict]:
    """Expand compact market rows into the legacy flat test format."""
    markets = _load_markets_by_city()
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
    """Rebuild origin|dest transfer index from split files or legacy JSON."""
    transfers_dir = DATA_DIR / "transfers"
    if transfers_dir.is_dir():
        edges: dict[str, list] = {}
        for path in sorted(transfers_dir.glob("*.json")):
            origin = path.stem
            by_dest = json.loads(path.read_text(encoding="utf-8"))
            for dest, options in by_dest.items():
                edges[f"{origin}|{dest}"] = options
        return edges

    legacy = DATA_DIR / "transfer_edges.json"
    if legacy.exists():
        return json.loads(legacy.read_text(encoding="utf-8"))

    raise FileNotFoundError(
        f"No transfer data under {transfers_dir} or {legacy}. Run the ETL pipeline first."
    )
