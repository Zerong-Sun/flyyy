"""Trade-contract catalog + flight lead-time rules for Demo UX."""
from __future__ import annotations

import json
from pathlib import Path

from tests.helpers import load_markets_flat, load_product_market_tags

ROOT = Path(__file__).resolve().parents[2]
WORLD = json.loads((ROOT / "game" / "data" / "world.json").read_text(encoding="utf-8"))
MARKETS = load_markets_flat()
PRODUCT_MARKET_TAGS = load_product_market_tags()

FOCUS_LEAD_SEC = 7200.0


def test_no_souvenirs_or_magnets():
    for p in WORLD["products"]:
        assert p.get("category") != "纪念品", p["product_id"]
        assert "magnet" not in str(p.get("product_id", "")).lower(), p["product_id"]


def test_contract_mix_light_and_high_value():
    by_city: dict[str, list] = {}
    authored_ids = {c["city_id"] for c in WORLD["cities"] if c.get("content_confidence") == "A"}
    for p in WORLD["products"]:
        w = float(p["weight_kg"])
        price = float(p["base_reference_price"])
        pid = p["product_id"]
        origin = p["origin_city_id"]
        # Authored cities: strict contract constraints
        if origin in authored_ids and "inherited_from" not in p:
            assert w <= 12.0, f"{pid} weight {w} > 12"
            assert price >= 200.0, f"{pid} price {price} < 200"
        # All products must be tradable (positive weight and price)
        assert w > 0, pid
        assert price > 0, pid
        # No souvenir category
        assert p.get("category") != "纪念品", pid
        by_city.setdefault(origin, []).append(p)
    assert len(by_city) >= 20
    for cid, items in by_city.items():
        assert len(items) >= 3, cid
        if cid in authored_ids:
            # Authored cities: must have at least one light and one high-value
            assert any(float(p["weight_kg"]) <= 2.0 for p in items), f"{cid} no light product"
            assert any(float(p["base_reference_price"]) >= 2000.0 for p in items), f"{cid} no high-value product"


def test_starting_cash_trade_float():
    assert abs(float(WORLD["economy"]["starting_cash_usd"]) - 50000.0) < 0.5


def test_baggage_extras_raised():
    extras = WORLD["economy"]["baggage_extras"]
    assert abs(float(extras["light"]["price_usd"]) - 160) < 0.5
    assert abs(float(extras["standard"]["price_usd"]) - 320) < 0.5
    assert abs(float(extras["heavy"]["price_usd"]) - 650) < 0.5
    assert abs(float(extras["cargo_per_50kg_usd"]) - 380) < 0.5


def test_flight_focus_lead_index_logic():
    """Mirror FlightSearch.first_focus_index: first flight with lead >= 2h."""
    now = 1_000_000.0
    flights = [
        {"dep": now + 1800},
        {"dep": now + 3600},
        {"dep": now + 8000},
        {"dep": now + 12000},
    ]

    def is_short(fl: dict) -> bool:
        return (fl["dep"] - now) < FOCUS_LEAD_SEC

    def first_focus(fls: list) -> int:
        for i, fl in enumerate(fls):
            if not is_short(fl):
                return i
        return 0

    assert first_focus(flights) == 2
    assert first_focus([{"dep": now + 100}]) == 0


# ---------------------------------------------------------------------------
# sell_buy_ratio / product_market_tags tests
# ---------------------------------------------------------------------------


def _market_index(markets: list) -> dict:
    """Build {(city_id, product_id): {"buy": ..., "sell": ...}} lookup."""
    idx = {}
    for m in markets:
        idx[(m["city_id"], m["product_id"])] = {
            "buy": float(m["buy_base_usd"]),
            "sell": float(m["sell_base_usd"]),
        }
    return idx


def test_sell_buy_ratio_tags_exist():
    """After pipeline run, product_market_tags must have entries for every product at its origin city."""
    tags = PRODUCT_MARKET_TAGS
    products = WORLD["products"]

    for product in products:
        origin_id = product.get("origin_city_id", "")
        key = f"{origin_id}|{product['product_id']}"
        assert key in tags, f"Missing tags for {key}"
        entry = tags[key]
        assert "hot" in entry, f"{key}: missing 'hot'"
        assert "normal" in entry, f"{key}: missing 'normal'"
        assert "cold" in entry, f"{key}: missing 'cold'"


def test_sell_buy_ratio_hot_threshold():
    """Hot cities must have sell_buy_ratio >= 1.15."""
    tags = PRODUCT_MARKET_TAGS
    mi = _market_index(MARKETS)

    for key, entry in tags.items():
        origin_id, product_id = key.split("|")
        for city_id in entry["hot"]:
            sell_base = mi[(city_id, product_id)]["sell"]
            buy_origin = mi[(origin_id, product_id)]["buy"]
            if buy_origin > 0:
                ratio = sell_base / buy_origin
                assert ratio >= 1.15, (
                    f"{key} → {city_id} tagged hot but ratio={ratio:.3f} < 1.15"
                )


def test_sell_buy_ratio_cold_threshold():
    """Cold cities must have sell_buy_ratio < 1.10 (ETL cold cutoff)."""
    tags = PRODUCT_MARKET_TAGS
    mi = _market_index(MARKETS)

    for key, entry in tags.items():
        origin_id, product_id = key.split("|")
        for city_id in entry["cold"]:
            sell_base = mi[(city_id, product_id)]["sell"]
            buy_origin = mi[(origin_id, product_id)]["buy"]
            if buy_origin > 0:
                ratio = sell_base / buy_origin
                assert ratio < 1.10, (
                    f"{key} → {city_id} tagged cold but ratio={ratio:.3f} >= 1.10"
                )


def test_sell_buy_ratio_no_city_duplicates():
    """Each city must appear in exactly one of hot/normal/cold per product."""
    tags = PRODUCT_MARKET_TAGS
    all_city_ids = {c["city_id"] for c in WORLD["cities"]}

    for key, entry in tags.items():
        cities_seen = set()
        for cat in ("hot", "normal", "cold"):
            for city_id in entry[cat]:
                assert city_id not in cities_seen, (
                    f"{key}: {city_id} appears in multiple categories"
                )
                cities_seen.add(city_id)
        assert cities_seen == all_city_ids, (
            f"{key}: missing cities: {all_city_ids - cities_seen}"
        )
