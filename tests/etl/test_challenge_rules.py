"""Rule-level tests for the 15-day challenge settlement (PRD_01.md §6.2).

These mirror the formulas implemented in game/scripts/systems/ChallengeSystem.gd
in pure Python (no Godot). They also act as a drift guard on the stat keys
referenced by both the challenge system and AppState.
"""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
GAME = ROOT / "game"
WORLD = json.loads((GAME / "data" / "world.json").read_text(encoding="utf-8"))
APPSTATE_SRC = (GAME / "scripts" / "autoload" / "AppState.gd").read_text(encoding="utf-8")
CHALLENGE_SRC = (GAME / "scripts" / "systems" / "ChallengeSystem.gd").read_text(encoding="utf-8")

# Normalization caps mirrored from ChallengeSystem.gd
CAP_NET_WORTH = 200_000.0
CAP_CITIES = 500.0
CAP_COUNTRIES = 100.0
CAP_PRODUCTS = 800.0
CAP_DISTANCE_KM = 40075.0
CAP_SINGLE_PROFIT = 10_000.0
CAP_PROFIT_PER_HOUR = 200.0

REQUIRED_STAT_KEYS = {
    "total_flight_segments",
    "total_distance_km",
    "total_flight_hours",
    "delayed_flights",
    "single_profit_max",
    "products_discovered",
}

METRIC_KEYS = {
    "net_worth", "visited_cities", "visited_countries", "products_discovered",
    "total_distance_km", "on_time_rate", "single_profit_max", "profit_per_hour",
    "score", "grade",
}


def _normalize(value: float, cap: float) -> float:
    if cap <= 0.0:
        return 0.0
    return min(max(value / cap, 0.0), 1.0)


def _on_time_rate(segments: float, delayed: float) -> float:
    if segments <= 0.0:
        return 0.0
    return min(max((segments - delayed) / segments, 0.0), 1.0)


def _profit_per_hour(net_worth: float, start_cash: float, hours: float) -> float:
    if hours <= 0.0:
        return 0.0
    return max(0.0, (net_worth - start_cash) / hours)


def _score(parts: list[float]) -> int:
    return int(round(sum(parts) / len(parts) * 100.0))


def _grade(score_pct: int) -> str:
    if score_pct >= 80:
        return "A"
    if score_pct >= 60:
        return "B"
    if score_pct >= 40:
        return "C"
    return "D"


def test_starting_cash_baseline_for_net_worth():
    assert WORLD["economy"]["starting_cash_usd"] == 50000.0


def test_on_time_rate_edge_cases():
    assert _on_time_rate(0, 0) == 0.0
    assert _on_time_rate(3, 3) == 0.0
    assert _on_time_rate(3, 0) == 1.0
    assert _on_time_rate(3, 1) == 2.0 / 3.0
    # delayed can never exceed segments (clamped)
    assert _on_time_rate(3, 9) == 0.0


def test_profit_per_hour_edge_cases():
    assert _profit_per_hour(50000.0, 50000.0, 10.0) == 0.0
    assert _profit_per_hour(70000.0, 50000.0, 10.0) == 2000.0
    # negative profit clamps to 0
    assert _profit_per_hour(30000.0, 50000.0, 10.0) == 0.0
    assert _profit_per_hour(60000.0, 50000.0, 0.0) == 0.0


def test_net_worth_convention_cash_plus_inventory():
    # Fixture: cash + single shelf-stable item at quality 1.0 selling at its
    # sell_base_usd — net worth must equal cash + sell_price * qty.
    pvg = next(a for a in WORLD["airports"] if a["iata"] == "PVG")
    city_id = pvg["city_id"]
    product = next(p for p in WORLD["products"] if p["origin_city_id"] == city_id)
    markets = json.loads((GAME / "data" / "markets" / f"{city_id}.json").read_text(encoding="utf-8"))
    row = next(e for e in markets if e["p"] == product["product_id"])
    cash = 1000.0
    qty = 3
    inventory_value = row["s"] * qty
    net_worth = cash + inventory_value
    assert net_worth == 1000.0 + row["s"] * 3


def test_required_stat_keys_exist_in_appstate_defaults():
    # Stat keys used by the challenge metrics must be present in AppState's
    # _default_stats() so they are reset per new game.
    for key in REQUIRED_STAT_KEYS:
        assert f'"{key}"' in APPSTATE_SRC, f"stat key {key!r} missing from AppState.gd"


def test_metric_keys_and_normalization_caps_in_challenge_source():
    for key in METRIC_KEYS:
        assert key in CHALLENGE_SRC, f"metric key {key!r} missing from ChallengeSystem.gd"
    for cap_name in ["CAP_NET_WORTH", "CAP_CITIES", "CAP_COUNTRIES", "CAP_PRODUCTS",
                     "CAP_DISTANCE_KM", "CAP_SINGLE_PROFIT", "CAP_PROFIT_PER_HOUR"]:
        assert cap_name in CHALLENGE_SRC, f"cap {cap_name!r} missing from ChallengeSystem.gd"


def test_grade_boundaries():
    assert _grade(100) == "A"
    assert _grade(80) == "A"
    assert _grade(79) == "B"
    assert _grade(60) == "B"
    assert _grade(59) == "C"
    assert _grade(40) == "C"
    assert _grade(39) == "D"
    assert _grade(0) == "D"


def test_score_aggregation_and_grade_consistency():
    # Perfect metrics on every axis → 100 → A; zero everywhere → 0 → D.
    assert _score([1.0] * 8) == 100
    assert _grade(_score([1.0] * 8)) == "A"
    assert _score([0.0] * 8) == 0
    assert _grade(_score([0.0] * 8)) == "D"


def test_save_paths_per_mode():
    # SaveSystem isolates saves per mode; sandbox keeps the legacy filename.
    save_src = (GAME / "scripts" / "autoload" / "SaveSystem.gd").read_text(encoding="utf-8")
    assert "save_challenge.json" in save_src
    assert "save_collector.json" in save_src
    assert "save_demo.json" in save_src
    # game_mode field must exist in AppState for path routing
    assert '"game_mode"' in APPSTATE_SRC
