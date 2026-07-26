"""Validate Demo i18n + audio content packs and wiring markers."""
from __future__ import annotations

import csv
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
GAME = ROOT / "game"
I18N = GAME / "assets" / "i18n"
AUDIO = GAME / "assets" / "audio"

P0_AUDIO = [
    "bgm_globe_day",
    "sfx_ui_click",
    "sfx_ui_hover",
    "sfx_ui_open_panel",
    "sfx_ui_close_panel",
    "sfx_search_type",
    "sfx_airport_select",
    "sfx_buy",
    "sfx_sell",
    "sfx_error",
    "sfx_ticket_ok",
    "sfx_ff_confirm",
    "sfx_boarding_alert",
    "sfx_takeoff",
    "sfx_cruise",
    "sfx_landing",
    "sfx_arrive",
]

# Sell feedback SFX added in trade-feedback-anchors (placeholder mapping verified in manifest)
FEEDBACK_SFX = [
    "sfx_loss",
    "sfx_loss_light",
    "sfx_big_win",
    "sfx_grand_slam",
]

TUTORIAL_TRIGGERS = [
    "new_game",
    "first_buy",
    "first_ticket",
    "first_arrive",
    "first_sell",
]

REQUIRED_UI_KEYS = [
    "ui.new_game.title",
    "ui.new_game.random",
    "ui.new_game.start",
    "ui.tab.city",
    "ui.tab.market",
    "ui.tab.flights",
    "ui.tab.inventory",
    "ui.tab.log",
    "ui.tab.attribution",
    "ui.ff.button",
    "ui.ff.confirm",
    "ui.ticket.economy",
    "ui.ticket.business",
    "ui.ticket.refund",
    "ui.disclaimer",
]


def test_i18n_csv_loads_and_has_required_keys():
    path = I18N / "zh_CN.csv"
    assert path.is_file()
    with path.open(encoding="utf-8", newline="") as f:
        rows = list(csv.DictReader(f))
    keys = {r["keys"] for r in rows}
    assert len(keys) >= 50
    for k in REQUIRED_UI_KEYS:
        assert k in keys, k
    disc = next(r["zh_CN"] for r in rows if r["keys"] == "ui.disclaimer")
    assert "公开航空数据重建" in disc


def test_tutorial_json_valid_and_complete():
    path = I18N / "tutorial_zh.json"
    data = json.loads(path.read_text(encoding="utf-8"))
    triggers = {t["trigger"] for t in data["tutorials"]}
    assert set(TUTORIAL_TRIGGERS) <= triggers
    for t in data["tutorials"]:
        assert 20 <= len(t["text"]) <= 200
        assert t.get("can_skip") is True


def test_attribution_file_mentions_audio_and_sources():
    text = (I18N / "attribution_zh.txt").read_text(encoding="utf-8")
    assert "OurAirports" in text
    assert "OpenFlights" in text
    assert "Kenney" in text or "CC0" in text
    assert "公开航空数据重建" in text
    assert "Noto Sans" in text or "OFL" in text


def test_audio_manifest_and_files():
    manifest = AUDIO / "AUDIO_MANIFEST.csv"
    assert manifest.is_file()
    with manifest.open(encoding="utf-8", newline="") as f:
        rows = list(csv.DictReader(f))
    by_id = {r["id"]: r for r in rows}
    assert set(P0_AUDIO) <= set(by_id)
    for aid in P0_AUDIO:
        rel = by_id[aid]["filename"]
        path = AUDIO / rel
        assert path.is_file(), path
        assert path.stat().st_size > 200
    # Verify sell-feedback SFX are registered (use placeholder mappings)
    for aid in FEEDBACK_SFX:
        assert aid in by_id, f"Missing audio ID in manifest: {aid}"
        rel = by_id[aid]["filename"]
        path = AUDIO / rel
        assert path.is_file(), f"Missing audio file for {aid}: {path}"


def test_city_product_content_not_template():
    world = json.loads((GAME / "data" / "world.json").read_text(encoding="utf-8"))
    assert len(world["cities"]) == 20
    for c in world["cities"]:
        assert "特色：城市作为全球航线节点" not in c.get("short_description", "")
        assert "更多细节将在后续内容更新中扩展" not in c.get("history_summary", "")
        assert len(c["overview"]) >= 150
    templates = [p for p in world["products"] if "特色：" in p.get("description", "")]
    assert templates == []


def test_godot_autoload_and_wiring_markers():
    project = (GAME / "project.godot").read_text(encoding="utf-8")
    assert 'I18nService="*res://scripts/autoload/I18nService.gd"' in project
    assert 'AudioService="*res://scripts/autoload/AudioService.gd"' in project
    assert (GAME / "scripts" / "autoload" / "I18nService.gd").is_file()
    assert (GAME / "scripts" / "autoload" / "AudioService.gd").is_file()
    assert (GAME / "default_bus_layout.tres").is_file()

    main = (GAME / "scripts" / "ui" / "MainHUD.gd").read_text(encoding="utf-8")
    assert "I18nService.t(" in main
    assert "I18nService.disclaimer()" in main
    assert "AudioService.set_bgm" in main
    assert "AudioService.play_sfx" in main

    ops = (GAME / "scripts" / "systems" / "FlightOps.gd").read_text(encoding="utf-8")
    assert 'AudioService.play_sfx("sfx_boarding_alert")' in ops
    assert 'I18nService.tutorial("first_arrive")' in ops

    app = (GAME / "scripts" / "autoload" / "AppState.gd").read_text(encoding="utf-8")
    assert 'I18nService.tutorial("new_game")' in app
