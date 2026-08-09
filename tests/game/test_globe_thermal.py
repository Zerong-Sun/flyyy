"""Regression gates for desktop globe thermal optimizations."""
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
PROJECT = ROOT / "game/project.godot"
GLOBE = ROOT / "game/scripts/render/GlobeController.gd"
HUD = ROOT / "game/scripts/ui/MainHUD.gd"
SMOKE = ROOT / "game/scripts/dev/SmokePerf.gd"


def test_runtime_is_vsynced_and_capped_at_60_fps():
    project = PROJECT.read_text(encoding="utf-8")
    assert "run/max_fps=60" in project
    assert "window/vsync/vsync_mode=1" in project


def test_airport_pins_use_four_shadowless_multimesh_batches():
    globe = GLOBE.read_text(encoding="utf-8")
    assert 'const PIN_STATES := ["unvisited", "visited", "selected", "current"]' in globe
    assert "MultiMeshInstance3D.new()" in globe
    assert "SHADOW_CASTING_SETTING_OFF" in globe
    assert "_pin_materials[state] = mat" in globe
    assert "MeshInstance3D.new()\n\t\tmi.mesh = pin_mesh" not in globe


def test_accessibility_palette_refreshes_shared_materials_immediately():
    globe = GLOBE.read_text(encoding="utf-8")
    hud = HUD.read_text(encoding="utf-8")
    assert "func refresh_marker_style()" in globe
    assert "globe.refresh_marker_style()" in hud


def test_performance_smoke_guards_batching_and_runtime_config():
    smoke = SMOKE.read_text(encoding="utf-8")
    for marker in (
        'ProjectSettings.get_setting("application/run/max_fps"',
        'ProjectSettings.get_setting("display/window/vsync/vsync_mode"',
        "batch_count != 4",
        "pin_mesh_ids.size() != 1",
        "pin_material_ids.size() != 4",
        "SHADOW_CASTING_SETTING_OFF",
    ):
        assert marker in smoke
