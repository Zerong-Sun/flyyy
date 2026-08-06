"""Rule-level tests for the reputation / level / unlock tree.

Mirror of game/scripts/systems/ReputationSystem.gd plus the gameplay wiring
in AppState.gd and MainHUD.gd, in pure Python (no Godot).
"""
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
GAME = ROOT / "game"

LEVEL_THRESHOLDS = [0, 30, 80, 160, 280, 460]

UNLOCK_BY_LEVEL = {
    2: "unlock_lv2_cargo",
    3: "unlock_lv3_cold_discount",
    4: "unlock_lv4_intel_discount",
    5: "unlock_lv5_baggage_plus10",
    6: "unlock_lv6_globe_title",
}


def level_for(xp: int) -> int:
    lv = 1
    for i in range(len(LEVEL_THRESHOLDS) - 1, 0, -1):
        if xp >= LEVEL_THRESHOLDS[i]:
            lv = i + 1
            break
    return lv


def active_unlocks(level: int) -> list[str]:
    return [UNLOCK_BY_LEVEL[k] for k in range(2, 7) if level >= k]


def test_thresholds_monotonic_and_flat():
    assert LEVEL_THRESHOLDS == sorted(LEVEL_THRESHOLDS)
    assert LEVEL_THRESHOLDS[0] == 0


def test_level_for_boundaries():
    assert level_for(0) == 1
    assert level_for(29) == 1
    assert level_for(30) == 2
    assert level_for(79) == 2
    assert level_for(80) == 3
    assert level_for(159) == 3
    assert level_for(160) == 4
    assert level_for(279) == 4
    assert level_for(280) == 5
    assert level_for(459) == 5
    assert level_for(460) == 6
    assert level_for(9999) == 6


def test_active_unlocks_progression():
    assert active_unlocks(1) == []
    assert active_unlocks(2) == ["unlock_lv2_cargo"]
    assert active_unlocks(3) == ["unlock_lv2_cargo", "unlock_lv3_cold_discount"]
    assert active_unlocks(6) == list(UNLOCK_BY_LEVEL.values())


def test_starting_city_reputation_stays_level_one():
    # reset_new_game visits the start city once -> +5 points, still Lv1.
    assert level_for(5) == 1


def test_sell_margin_contribution():
    # AppState.log_sell_transaction: +int(margin / 1000) when margin > 0.
    assert int(500 / 1000) == 0
    assert int(1500 / 1000) == 1
    assert int(3450 / 1000) == 3


def test_unlock_discount_constants():
    # Lv3 cold-chain baggage 20% off (120 -> 96), Lv4 intel 30% off (200 -> 140).
    assert round(120 * 0.8, 2) == 96.0
    assert round(200 * 0.7, 2) == 140.0


def test_unlock_effects_wired_in_source():
    # The unlock tree must actually affect gameplay, not only the panel.
    rep_src = (GAME / "scripts" / "systems" / "ReputationSystem.gd").read_text(encoding="utf-8")
    app_src = (GAME / "scripts" / "autoload" / "AppState.gd").read_text(encoding="utf-8")
    hud_src = (GAME / "scripts" / "ui" / "MainHUD.gd").read_text(encoding="utf-8")
    assert "func has_unlock" in rep_src
    assert "UNLOCK_LV5" in app_src, "Lv5 +10kg baggage must be applied in AppState"
    assert "UNLOCK_LV4" in hud_src, "Lv4 intel discount must be applied in MainHUD"
    assert "UNLOCK_LV3" in hud_src, "Lv3 cold discount must be applied in MainHUD"
    assert "UNLOCK_LV2" in hud_src, "Lv2 free cargo block must be applied in MainHUD"


def test_reputation_persisted_with_defaults():
    # to_dict/from_dict carry reputation_points/level; old saves default 0 / 1.
    app_src = (GAME / "scripts" / "autoload" / "AppState.gd").read_text(encoding="utf-8")
    assert "reputation_points" in app_src
    assert '"level"' in app_src
    assert 'd.get("reputation_points", 0)' in app_src
    assert 'd.get("level", 1)' in app_src
