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
    "sfx_coin_roll",
]

V02_BGM = [
    "bgm_market",
    "bgm_menu",
    "bgm_night",
]

# Achievements whose icon reference has no dedicated art file yet (v0.3-era
# additions). IconFactory.get_achievement_icon falls back to a category badge,
# and REQ §6.6 tracks this as a known todo until dedicated icons ship.
ACH_ICON_EXCEPTIONS = {
    "icon_ach_explore_cities_100_64",
    "icon_ach_explore_cities_500_64",
    "icon_ach_explore_countries_10_64",
    "icon_ach_explore_countries_30_64",
    "icon_ach_explore_hubs_20_64",
    "icon_ach_explore_extreme_ns_64",
    "icon_ach_explore_extreme_ew_64",
    "icon_ach_trade_profit_10k_64",
    "icon_ach_trade_net_100k_64",
    "icon_ach_trade_big_loss_64",
    "icon_ach_trade_intel_64",
    "icon_ach_trade_categories_8_64",
    "icon_ach_flight_10_64",
    "icon_ach_flight_50_64",
    "icon_ach_flight_distance_40k_64",
    "icon_ach_flight_ff_64",
    "icon_ach_collect_products_50_64",
    "icon_ach_collect_products_200_64",
    "icon_ach_collect_notes_20_64",
    "icon_ach_collect_heroes_50_64",
}

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

# REQ §5.5 / trade-feedback design §4.3–4.4: consolation/celebration pools
# plus sell-result titles moved into zh_CN.csv (i18n-copy).
FEEDBACK_KEYS = [
    "sell_console_1",
    "sell_console_2",
    "sell_console_3",
    "sell_console_4",
    "sell_console_5",
    "sell_console_big_loss",
    "celebration_w1_1",
    "celebration_w1_2",
    "celebration_w1_3",
    "celebration_w2_1",
    "celebration_w2_2",
    "celebration_w2_3",
    "sell_result_title_l1",
    "sell_result_title_l2",
    "sell_result_title_w0",
    "sell_result_title_w1",
    "sell_result_title_w2",
    "sell_result_title_w2_discovery",
    "sell_result_milestone",
    "sell_result_continue",
]


def test_i18n_csv_loads_and_has_required_keys():
    path = I18N / "zh_CN.csv"
    assert path.is_file()
    with path.open(encoding="utf-8", newline="") as f:
        rows = list(csv.DictReader(f))
    keys = {r["keys"] for r in rows}
    assert len(keys) >= 50
    assert len(keys) == len(rows), "duplicate i18n key"
    for k in REQUIRED_UI_KEYS:
        assert k in keys, k
    for k in FEEDBACK_KEYS:
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
    for aid in V02_BGM:
        assert aid in by_id, f"Missing v0.2 BGM in manifest: {aid}"
        path = AUDIO / by_id[aid]["filename"]
        assert path.is_file() and path.stat().st_size > 200, path


def test_city_product_content_not_template():
    world = json.loads((GAME / "data" / "world.json").read_text(encoding="utf-8"))
    assert len(world["cities"]) >= 20
    authored = [c for c in world["cities"] if c.get("content_confidence") == "A"]
    for c in authored:
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
    assert "sfx_coin_roll" in main
    assert "sfx_search_type" in main
    assert "get_bgm_volume" in main
    assert "_play_transition_fx" in main
    assert "IconFactory" in main

    ops = (GAME / "scripts" / "systems" / "FlightOps.gd").read_text(encoding="utf-8")
    assert 'AudioService.play_sfx("sfx_boarding_alert")' in ops
    assert 'I18nService.tutorial("first_arrive")' in ops

    app = (GAME / "scripts" / "autoload" / "AppState.gd").read_text(encoding="utf-8")
    assert 'I18nService.tutorial("new_game")' in app


def test_icon_factory_and_globe_placeholders():
    """CAS Demo art placeholders: IconFactory (≥19) + GlobeController code gen."""
    icon_path = GAME / "themes" / "IconFactory.gd"
    assert icon_path.is_file()
    icon_src = icon_path.read_text(encoding="utf-8")
    for icon_id in (
        "ic_city",
        "ic_market",
        "ic_flight",
        "ic_inventory",
        "ic_log",
        "ic_attr",
        "ic_search",
        "ic_random",
        "ic_economy",
        "ic_business",
        "ic_baggage",
        "ic_cargo",
        "ic_fast_forward",
        "ic_save",
        "ic_load",
        "ic_money",
        "ic_weight",
        "ic_clock",
        "ic_warning",
    ):
        assert f'"{icon_id}"' in icon_src, icon_id

    globe = (GAME / "scripts" / "render" / "GlobeController.gd").read_text(encoding="utf-8")
    for marker in (
        "earth_albedo_placeholder",
        "_build_grid_overlay",
        "_make_pin_mesh",
        "set_plane_on_route",
        "_build_plane_marker",
    ):
        assert marker in globe, marker

    assert (GAME / "themes" / "ThemeFactory.gd").is_file()
    assert (GAME / "themes" / "DemoColors.gd").is_file()
    assert (GAME / "assets" / "fonts" / "NotoSansSC-Regular.otf").is_file()
    assert (GAME / "assets" / "fonts" / "JetBrainsMono-Regular.ttf").is_file()


def test_a2_art_assets_wired():
    """A2 generated art lives in typed dirs and IconFactory/MainHUD load them."""
    brand = GAME / "assets" / "brand"
    icons = GAME / "assets" / "icons"
    ach = icons / "achievements"
    products = GAME / "assets" / "products"
    cities = GAME / "assets" / "cities"
    anim = GAME / "assets" / "anim" / "flight_transition"

    for path in (
        brand / "app_icon.webp",
        brand / "logo_mark.webp",
        brand / "logo_wordmark_zh.webp",
        brand / "splash.webp",
        icons / "icon_market_32.webp",
        icons / "icon_hot_tag_32.webp",
        icons / "icon_cold_tag_32.webp",
        icons / "icon_intel_upgrade_32.webp",
        icons / "icon_settings_32.webp",
        ach / "icon_ach_flight_first_64.webp",
        products / "product_generic_placeholder_64.webp",
        cities / "city_shanghai_hero_720.webp",
        anim / "anim_flight_takeoff.webp",
        anim / "anim_flight_cruise.webp",
        anim / "anim_flight_land.webp",
    ):
        assert path.is_file(), path

    assert len(list(icons.glob("icon_*.webp"))) >= 20
    assert len(list(ach.glob("icon_ach_*.webp"))) >= 25
    assert len(list(products.glob("product_*.webp"))) >= 40
    assert len(list(cities.glob("city_*_hero_720.webp"))) >= 20

    icon_src = (GAME / "themes" / "IconFactory.gd").read_text(encoding="utf-8")
    for marker in (
        "get_product_icon",
        "get_achievement_icon",
        "get_city_hero",
        "get_transition_art",
        "get_brand",
        "assets/icons/",
        "assets/products/",
        "assets/cities/",
        "assets/brand/",
    ):
        assert marker in icon_src, marker

    main = (GAME / "scripts" / "ui" / "MainHUD.gd").read_text(encoding="utf-8")
    for marker in (
        "get_city_hero",
        "get_product_icon",
        "get_achievement_icon",
        "get_transition_art",
        "get_brand",
        "ic_settings",
        "ic_intel",
        "ic_hot",
    ):
        assert marker in main, marker

    project = (GAME / "project.godot").read_text(encoding="utf-8")
    assert 'config/icon="res://assets/brand/app_icon.webp"' in project

    attr = (GAME / "assets" / "i18n" / "attribution_zh.txt").read_text(encoding="utf-8")
    assert "美术（A2）" in attr
    assert "game/assets/icons/" in attr


def test_hud_status_icons_are_size_clamped():
    icon_src = (GAME / "themes" / "IconFactory.gd").read_text(encoding="utf-8")
    expand_idx = icon_src.index("tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE")
    texture_idx = icon_src.index("tex_rect.texture = tex")
    assert expand_idx < texture_idx

    main = (GAME / "scripts" / "ui" / "MainHUD.gd").read_text(encoding="utf-8")
    assert "top.clip_contents = true" in main


def test_all_cities_have_hero_assets():
    """Every city in world.json ships a hero image under game/assets/cities.

    Demo 20 hubs carry real AI art (640x360); the remaining L2 cities carry
    procedural regional plates (1280x720) generated by gen_city_plates.py.
    Both are gated here so a future city never silently falls back to the
    logo_mark placeholder in IconFactory.get_city_hero.
    """
    from PIL import Image

    world = json.loads((GAME / "data" / "world.json").read_text(encoding="utf-8"))
    cities = world["cities"] if isinstance(world, dict) else world
    cities_dir = GAME / "assets" / "cities"
    demo_ids = {
        "atlanta", "dubai", "dallas", "denver", "london", "chicago",
        "istanbul", "los_angeles", "tokyo", "shanghai", "paris", "amsterdam",
        "guangzhou", "frankfurt", "beijing", "singapore", "seoul",
        "hong_kong", "bangkok", "miami",
    }

    plates = 0
    for c in cities:
        cid = c["city_id"]
        path = cities_dir / f"city_{cid}_hero_720.webp"
        assert path.is_file(), f"{cid}: missing hero asset"
        if cid in demo_ids:
            continue  # real AI art; size not constrained by the plate generator
        with Image.open(path) as im:
            assert im.size == (1280, 720), f"{cid}: expected 1280x720 plate"
        plates += 1

    # Every non-Demo city in world.json is covered by a generated plate.
    assert plates == len(cities) - len(demo_ids)


def test_merchant_portraits_present_and_distinct():
    """Sell-feedback portraits exist at 64x64 and are visibly distinct."""
    from PIL import Image

    portraits_dir = GAME / "assets" / "portraits"
    files = {
        "worried": portraits_dir / "portrait_worried_64.png",
        "celebrating": portraits_dir / "portrait_celebrating_64.png",
    }
    for kind, path in files.items():
        assert path.is_file(), f"{kind}: missing portrait"
        with Image.open(path) as im:
            assert im.size == (64, 64), f"{kind}: expected 64x64"
            assert im.mode == "RGBA", f"{kind}: expected RGBA"

    # Distinct expressions: worried carries a sweat drop (cool blue), the
    # celebrating frame must differ meaningfully in pixel content.
    import numpy as np

    worried = Image.open(files["worried"]).convert("RGBA")
    celebrating = Image.open(files["celebrating"]).convert("RGBA")
    assert worried.tobytes() != celebrating.tobytes()
    wpx = np.asarray(worried)
    sweat = int(
        np.count_nonzero(
            (wpx[..., 3] > 0)
            & (wpx[..., 2] > 150)
            & (wpx[..., 0] > 100) & (wpx[..., 0] < 170)
        )
    )
    assert sweat >= 10, f"worried sweat highlight missing ({sweat} px)"

    # IconFactory wiring: get_portrait resolves both and popup scene has frame.
    icon_src = (GAME / "themes" / "IconFactory.gd").read_text(encoding="utf-8")
    assert "portrait_" in icon_src and "get_portrait" in icon_src
    assert "res://assets/portraits/" in icon_src

    popup_scene = (GAME / "scenes" / "PopupEvent.tscn").read_text(encoding="utf-8")
    assert "PortraitFrame" in popup_scene
    popup_script = (GAME / "scripts" / "components" / "PopupEvent.gd").read_text(
        encoding="utf-8"
    )
    assert "set_portrait" in popup_script


def test_achievement_icon_refs_resolve_to_files():
    """Every achievement icon reference must resolve to a shipped art file.

    Missing art falls back to a category placeholder at runtime, but a stray
    reference that no longer matches any file is a data regression (icon wall
    would silently show a generic badge). Known exceptions without dedicated
    art are whitelisted below and tracked in REQ §6.6.
    """
    ach_path = GAME / "data" / "achievements.json"
    assert ach_path.is_file()
    achievements = json.loads(ach_path.read_text(encoding="utf-8"))["achievements"]
    assert len(achievements) >= 30

    ach_dir = GAME / "assets" / "icons" / "achievements"
    files = {
        p.stem for p in ach_dir.iterdir() if p.suffix in (".png", ".webp")
    }
    missing = [a["icon"] for a in achievements if a.get("icon") not in files]
    # v0.3-era achievements without dedicated art are expected; they use the
    # category fallback in IconFactory.get_achievement_icon. All newly added
    # achievements must ship real art.
    assert set(missing) <= set(ACH_ICON_EXCEPTIONS), (
        f"new missing achievement icons beyond known exceptions: "
        f"{sorted(set(missing) - set(ACH_ICON_EXCEPTIONS))}"
    )


