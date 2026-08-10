"""Regression gates for desktop runtime thermal settings."""
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
PROJECT = ROOT / "game/project.godot"
GLOBE = ROOT / "game/scripts/render/GlobeController.gd"
SMOKE = ROOT / "game/scripts/dev/SmokePerf.gd"


def test_runtime_is_not_explicitly_unsynced_and_is_capped_at_60_fps():
    project = PROJECT.read_text(encoding="utf-8")
    assert "run/max_fps=60" in project
    # Godot omits default-valued settings when saving project.godot. VSync's
    # default is enabled, so absence is valid; only an explicit 0 disables it.
    assert "window/vsync/vsync_mode=0" not in project


def test_airport_pins_use_the_original_individual_mesh_nodes():
    globe = GLOBE.read_text(encoding="utf-8")
    assert "var _airport_nodes: Dictionary = {}" in globe
    assert "var mi := MeshInstance3D.new()\n\t\tmi.mesh = pin_mesh" in globe
    assert "_airport_nodes[a.airport_id] = mi" in globe
    for batched_marker in (
        "PIN_STATES",
        "MultiMeshInstance3D",
        "_pin_batches",
        "_pin_materials",
        "refresh_marker_style",
    ):
        assert batched_marker not in globe


def test_performance_smoke_guards_runtime_config():
    smoke = SMOKE.read_text(encoding="utf-8")
    for marker in (
        'ProjectSettings.get_setting("application/run/max_fps"',
        'ProjectSettings.get_setting("display/window/vsync/vsync_mode"',
    ):
        assert marker in smoke
