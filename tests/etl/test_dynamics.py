"""Rule-level tests for dynamic market factors (seasonal + scarcity) and the
Steam achievement mapping.

These mirror the formulas implemented in
game/scripts/systems/EconomySystem.gd and the mapping kept in
game/data/steam_achievements.json, in pure Python (no Godot).
"""
from __future__ import annotations

import json
import random
import re
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
GAME = ROOT / "game"
WORLD = json.loads((GAME / "data" / "world.json").read_text(encoding="utf-8"))
ACHIEVEMENTS = json.loads((GAME / "data" / "achievements.json").read_text(encoding="utf-8"))
STEAM_MAP = json.loads((GAME / "data" / "steam_achievements.json").read_text(encoding="utf-8"))
ECON_SRC = (GAME / "scripts" / "systems" / "EconomySystem.gd").read_text(encoding="utf-8")
MARKETS_DIR = GAME / "data" / "markets"


def _seasonal_factor(month: str) -> float:
    dyn = WORLD["economy"].get("dynamics", {})
    seasonal = dyn.get("seasonal", {})
    return float(seasonal.get(month, 1.0))


# --- deterministic market events mirror (MarketEvents.gd) ---

# Fixed fixtures derived from world data so the mirror stays deterministic.
_PRODUCTS = WORLD["products"]
_FIX_CITY = "atlanta"
_FIX_PRODUCT = next((p for p in _PRODUCTS if p["origin_city_id"] == _FIX_CITY), None)
_FIX_DATE = "2025-03-15"


def _roll(seed_s: str, prob: float) -> bool:
    # Mirrors MarketEvents._roll: stable seeded RNG (crc32, not Python's
    # randomized hash). Same seed => same outcome, cross-call idempotent.
    rng = random.Random(zlib.crc32(seed_s.encode("utf-8")))
    return rng.random() < prob


def _factor_for(save_id, city_id, product_id, date, is_buy, is_local, is_cold):
    # Mirrors MarketEvents.factor_for() seed strings (save_id|city|event|date).
    if is_local and not is_buy and _roll(f"{save_id}|{city_id}|festival|{date}", 0.04):
        return ("festival", 1.15)
    if is_cold and _roll(f"{save_id}|{city_id}|weather|{date}", 0.03):
        return ("weather_cold", 1.10 if is_buy else 0.92)
    if is_local and not is_buy and _roll(f"{save_id}|{city_id}|scarcity|{date}", 0.05):
        return ("scarcity", 1.10)
    return ("", 1.0)


def test_event_factor_seed_deterministic():
    assert _FIX_PRODUCT is not None, "world.json products must contain atlanta"
    is_local = True
    is_cold = bool(_FIX_PRODUCT.get("requires_cold_chain", False))
    args = ("S1", _FIX_CITY, _FIX_PRODUCT["product_id"], _FIX_DATE)
    r1 = _factor_for(*args, False, is_local, is_cold)
    r2 = _factor_for(*args, False, is_local, is_cold)
    assert r1 == r2, "same seeds must yield the same event (idempotent)"


def test_event_factor_save_id_isolation():
    # Different saves must be able to see different events on the same day/city.
    assert _FIX_PRODUCT is not None
    is_local = True
    is_cold = bool(_FIX_PRODUCT.get("requires_cold_chain", False))
    outcomes = set()
    for i in range(80):
        outcomes.add(_factor_for(f"save_{i}", _FIX_CITY, _FIX_PRODUCT["product_id"],
                                 _FIX_DATE, False, is_local, is_cold))
    assert len(outcomes) >= 2, "save_id must affect event outcomes"


def test_city_events_idempotent_and_weather_gated():
    def city_events(save_id, has_cold):
        out = []
        if _roll(f"{save_id}|{_FIX_CITY}|festival|{_FIX_DATE}", 0.04):
            out.append("festival")
        if has_cold and _roll(f"{save_id}|{_FIX_CITY}|weather|{_FIX_DATE}", 0.03):
            out.append("weather_cold")
        if _roll(f"{save_id}|{_FIX_CITY}|scarcity|{_FIX_DATE}", 0.05):
            out.append("scarcity")
        return tuple(sorted(out))

    assert city_events("S1", True) == city_events("S1", True), "city_events idempotent"
    # Weather only fires when the city actually carries cold-chain products.
    assert "weather_cold" not in city_events("S1", False)


# --- seasonal / scarcity formulas ---


def test_dynamics_materialized_in_world_json():
    dyn = WORLD["economy"].get("dynamics")
    assert dyn is not None, "economy.dynamics must exist in world.json"
    assert "seasonal" in dyn
    assert "scarcity" in dyn
    # 12 calendar months, all within the planned [0.9, 1.25] band.
    months = dyn["seasonal"]
    assert len(months) == 12
    for m in range(1, 13):
        key = f"{m:02d}"
        assert key in months, f"missing seasonal factor for month {key}"
        assert 0.9 <= float(months[key]) <= 1.25
    scarcity = dyn["scarcity"]
    assert float(scarcity["weight_kg_over"]) > 0
    assert float(scarcity["mult"]) > 1.0


def test_seasonal_factor_unknown_month_defaults_one():
    assert _seasonal_factor("13") == 1.0
    assert _seasonal_factor("") == 1.0
    assert _seasonal_factor("99") == 1.0


def test_seasonal_factor_month_values():
    # Spot-check a few months against the configured table.
    assert _seasonal_factor("01") == 1.0
    assert _seasonal_factor("12") == 1.15
    assert _seasonal_factor("07") == 1.08
    assert _seasonal_factor("06") == 1.05


def test_sell_price_includes_seasonal_factor():
    # Mirrors EconomySystem.sell_price: sell_base * daily * seasonal * ...,
    # so the seasonal multiplier must move the December price above March.
    assert _FIX_PRODUCT is not None
    rows = json.loads((MARKETS_DIR / f"{_FIX_CITY}.json").read_text(encoding="utf-8"))
    row = next((r for r in rows if r["p"] == _FIX_PRODUCT["product_id"]), None)
    assert row is not None, "atlanta market must include its local product"
    base = float(row["s"])
    mar = base * _seasonal_factor("03")
    dec = base * _seasonal_factor("12")
    assert dec > mar, "December seasonal factor must raise sell price vs March"


def test_market_row_idempotent():
    # Same city/product read twice yields the same base prices (no mutation).
    rows = json.loads((MARKETS_DIR / f"{_FIX_CITY}.json").read_text(encoding="utf-8"))
    rows_again = json.loads((MARKETS_DIR / f"{_FIX_CITY}.json").read_text(encoding="utf-8"))
    assert rows == rows_again
    for r in rows:
        assert float(r["b"]) > 0.0 and float(r["s"]) > 0.0


def test_seasonal_factor_used_in_sell_price_source():
    # EconomySystem must multiply sell price by the seasonal factor.
    assert "seasonal_factor" in ECON_SRC
    assert "dynamics" in ECON_SRC
    # The seasonal call must appear *inside* sell_price's body (after its decl).
    idx_sell = ECON_SRC.index("static func sell_price")
    next_func = ECON_SRC.index("static func", idx_sell + 5)
    body = ECON_SRC[idx_sell:next_func]
    assert "seasonal_factor(" in body, "sell_price must call seasonal_factor()"


def test_economy_etl_config_sources_dynamics():
    # Guard: economy.yaml keeps the dynamics table; pipeline passes it through.
    yaml_src = (ROOT / "etl" / "config" / "economy.yaml").read_text(encoding="utf-8")
    pipeline_src = (ROOT / "etl" / "scripts" / "run_pipeline.py").read_text(encoding="utf-8")
    assert "dynamics:" in yaml_src
    assert "seasonal:" in yaml_src
    assert "scarcity:" in yaml_src
    assert "dynamics" in pipeline_src


# --- Steam achievement mapping ---


def _to_steam(pid: str) -> str:
    return re.sub(r"[^A-Z0-9]", "_", pid.replace("ach_", "").upper())


def test_steam_map_covers_all_achievements():
    src_ids = {a["id"] for a in ACHIEVEMENTS["achievements"]}
    mapped_ids = set(STEAM_MAP["achievements"])
    assert src_ids == mapped_ids, f"diff: {sorted(src_ids ^ mapped_ids)}"


def test_steam_api_names_match_convention():
    for pid, steam_name in STEAM_MAP["achievements"].items():
        expected = _to_steam(pid)
        assert steam_name == expected, f"{pid} mapped to {steam_name}, expected {expected}"
        # Steam API names are uppercase alnum + underscore, unique
        assert re.fullmatch(r"[A-Z0-9_]+", steam_name)


def test_steam_map_has_no_duplicate_api_names():
    names = list(STEAM_MAP["achievements"].values())
    assert len(names) == len(set(names))


def test_steam_achievements_json_schema():
    assert "_generated_from" in STEAM_MAP
    assert isinstance(STEAM_MAP["achievements"], dict)
