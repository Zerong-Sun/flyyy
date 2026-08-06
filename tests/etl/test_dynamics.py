"""Rule-level tests for dynamic market factors (seasonal + scarcity) and the
Steam achievement mapping.

These mirror the formulas implemented in
game/scripts/systems/EconomySystem.gd and the mapping kept in
game/data/steam_achievements.json, in pure Python (no Godot).
"""
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
GAME = ROOT / "game"
WORLD = json.loads((GAME / "data" / "world.json").read_text(encoding="utf-8"))
ACHIEVEMENTS = json.loads((GAME / "data" / "achievements.json").read_text(encoding="utf-8"))
STEAM_MAP = json.loads((GAME / "data" / "steam_achievements.json").read_text(encoding="utf-8"))
ECON_SRC = (GAME / "scripts" / "systems" / "EconomySystem.gd").read_text(encoding="utf-8")


def _seasonal_factor(month: str) -> float:
    dyn = WORLD["economy"].get("dynamics", {})
    seasonal = dyn.get("seasonal", {})
    return float(seasonal.get(month, 1.0))


def test_dynamics_materialized_in_world_json():
    dyn = WORLD["economy"].get("dynamics")
    assert dyn is not None, "economy.dynamics must exist in world.json"
    assert "seasonal" in dyn
    assert "scarcity" in dyn
    # 12 calendar months, all >= 1.0 (never discount below base)
    months = dyn["seasonal"]
    assert len(months) == 12
    for m in range(1, 13):
        key = f"{m:02d}"
        assert key in months, f"missing seasonal factor for month {key}"
        assert float(months[key]) >= 1.0
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
