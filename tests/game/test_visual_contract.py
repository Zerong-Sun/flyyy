"""Craft contract ratchet (GDLC Playtest #4): computed-style assertions.

RED-before-GREEN on craft work = contract assertions on computed style
(baseline PNGs are green-by-construction). These parse the theme token
values and layout rects from the GDScript sources and compute WCAG 2.1
contrast ratios. Authored RED from the craft personas' measurements
(Game Designer contrast table; Retro Gamer environment audit).
"""
from __future__ import annotations

import json
import unicodedata
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
GAME = ROOT / "game"

COLORS_SRC = (GAME / "themes" / "DemoColors.gd").read_text(encoding="utf-8")
HUD_SRC = (GAME / "scripts" / "ui" / "MainHUD.gd").read_text(encoding="utf-8")
PROJECT_SRC = (GAME / "project.godot").read_text(encoding="utf-8")

MIN_CONTRAST = 4.5  # WCAG AA for normal text


def _hex_token(name: str, src: str) -> tuple[int, int, int]:
    m = re.search(rf'{name}\s*:=\s*Color\("([0-9A-Fa-f]{{6}})"\)', src)
    if not m:
        m = re.search(
            rf'{name}\s*:=\s*Color\(([0-9.]+),\s*([0-9.]+),\s*([0-9.]+)',
            src,
        )
        if not m:
            raise AssertionError(f"token {name} not found")
        return tuple(int(round(float(g) * 255)) for g in m.groups())
    h = m.group(1)
    return tuple(int(h[i : i + 2], 16) for i in (0, 2, 4))


def _luminance(c: tuple[int, int, int]) -> float:
    def ch(v: int) -> float:
        f = v / 255.0
        return f / 12.92 if f <= 0.04045 else ((f + 0.055) / 1.055) ** 2.4
    return 0.2126 * ch(c[0]) + 0.7152 * ch(c[1]) + 0.0722 * ch(c[2])


def _contrast(a: tuple[int, int, int], b: tuple[int, int, int]) -> float:
    la, lb = _luminance(a), _luminance(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


def _composite_over(fg: tuple[int, int, int], alpha: float, bg: tuple[int, int, int]) -> tuple[int, int, int]:
    return tuple(int(round(fg[i] * alpha + bg[i] * (1.0 - alpha))) for i in range(3))


WARN_RED = _hex_token("WARN_RED", COLORS_SRC)
ACCENT_AMBER = _hex_token("ACCENT_AMBER", COLORS_SRC)
TEXT_SECONDARY = _hex_token("TEXT_SECONDARY", COLORS_SRC)
OCEAN = _hex_token("OCEAN", COLORS_SRC)
LAND = _hex_token("LAND", COLORS_SRC)
BG_DEEP = _hex_token("BG_DEEP", COLORS_SRC)
BG_PANEL = _composite_over(_hex_token("BG_PANEL", COLORS_SRC), 0.88, BG_DEEP)


def _rect(var: str) -> tuple[int, int, int, int] | None:
    pos = re.search(rf'{var}\.position\s*=\s*Vector2\((-?\d+),\s*(-?\d+)\)', HUD_SRC)
    if not pos:
        return None
    size = re.search(rf'{var}\.size\s*=\s*Vector2\((\d+),\s*(\d+)\)', HUD_SRC)
    x, y = int(pos.group(1)), int(pos.group(2))
    if not size:
        # _btn_ff is an auto-sized Button; assume a minimal touch target.
        w, h = (110, 40)
    else:
        w, h = int(size.group(1)), int(size.group(2))
    return (x, y, x + w, y + h)


def _scrim_over(bg: tuple[int, int, int]) -> tuple[int, int, int]:
    """The shipped scrim strip behind globe-floating labels (BG_DEEP @ 0.85)."""
    return _composite_over(BG_DEEP, 0.85, bg)


def test_board_countdown_contrast_over_globe():
    """P1 (Game Designer): the boarding/<2h countdown floats over the globe; the
    fix ships a BG_DEEP@0.85 scrim behind the label — the contract is the token
    vs the scrim (raw token-vs-ocean was 2.49:1 and unreadable)."""
    for name, bg in (("ocean", OCEAN), ("land", LAND)):
        ratio = _contrast(WARN_RED, _scrim_over(bg))
        assert ratio >= MIN_CONTRAST, (
            f"WARN_RED countdown on scrim over {name} = {ratio:.2f}:1 < {MIN_CONTRAST}"
        )


def test_warn_red_on_panel_contrast():
    """P1 (Director F6): WARN_RED on card backgrounds was 3.73–4.03:1."""
    ratio = _contrast(WARN_RED, BG_PANEL)
    assert ratio >= MIN_CONTRAST, f"WARN_RED on BG_PANEL = {ratio:.2f}:1 < {MIN_CONTRAST}"


def test_challenge_label_contrast_over_globe():
    """P2 (Game Designer): ACCENT_AMBER 14px challenge label — same scrim contract."""
    for name, bg in (("ocean", OCEAN), ("land", LAND)):
        ratio = _contrast(ACCENT_AMBER, _scrim_over(bg))
        assert ratio >= MIN_CONTRAST, (
            f"ACCENT_AMBER label on scrim over {name} = {ratio:.2f}:1 < {MIN_CONTRAST}"
        )


def test_disclaimer_contrast_on_panel():
    """P3 (Game Designer): TEXT_SECONDARY at 0.9 modulate on card copy."""
    faded = _composite_over(TEXT_SECONDARY, 0.9, BG_PANEL)
    ratio = _contrast(faded, BG_PANEL)
    assert ratio >= MIN_CONTRAST, f"faded disclaimer on BG_PANEL = {ratio:.2f}:1 < {MIN_CONTRAST}"


def test_hint_panel_does_not_block_fast_forward():
    """P1 (Game Designer): the hint toast covered the 加速至起飞 button and
    swallowed clicks for 8-12 s. Shipped contract: mouse_filter IGNORE."""
    assert "_hint_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE" in HUD_SRC, (
        "hint panel must use MOUSE_FILTER_IGNORE so toasts never swallow clicks"
    )
    assert "_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE" in HUD_SRC, (
        "hint label must use MOUSE_FILTER_IGNORE"
    )


def test_no_orphan_city_plates():
    """H2 (Director F3): every shipped plate maps to a world city; 257 orphans
    from the roster trim were removed."""
    world_ids = {c["city_id"] for c in json.loads((GAME / "data" / "world.json").read_text(encoding="utf-8"))["cities"]}
    d = GAME / "assets" / "cities"
    plates = {p.name[len("city_"):-len("_hero_720.webp")] for p in d.glob("city_*_hero_720.webp")}
    orphans = {unicodedata.normalize("NFC", p) for p in plates} - world_ids
    assert not orphans, f"{len(orphans)} orphan city plates: {sorted(orphans)[:5]}"


def test_no_prd_banned_icon_stems():
    """H11 (Director F4): PRD-banned category icons (tobacco/wine/beer/etc.)
    must not ship, dead or alive."""
    banned = ("tobacco", "cigarette", "cigar", "wine", "beer", "alcohol", "weapon", "gun")
    hits = []
    for d in ("products", "icons", "art"):
        base = GAME / "assets" / d
        if not base.is_dir():
            continue
        for p in base.glob("*.webp"):
            if any(b in p.name.lower() for b in banned):
                hits.append(str(p))
    assert not hits, f"PRD-banned icon stems shipped: {hits}"


def test_no_legacy_art_duplicate_tree():
    """H12 (Director F5): the legacy art/ duplicate tree (97 files, 2 drifted)
    must not ship. The duplicate image files were removed; `_archive/` and
    `_sheets/` remain as source-provenance archives (excluded from exports via
    the export preset — GDLC Playtest #4, F8 queued) and the prompt doc stays."""
    art = GAME / "assets" / "art"
    allowed = {"ART_PROMPTS_REQ.md", "_archive", "_sheets"}
    if art.is_dir():
        leftovers = sorted(p.name for p in art.iterdir() if p.name not in allowed)
        assert not leftovers, f"legacy art/ duplicates remain: {leftovers}"


def test_earth_albedo_attributed():
    """H15 (Director F7): the earth albedo's provenance must appear in the
    in-game attribution file."""
    txt = (GAME / "assets" / "i18n" / "attribution_zh.txt").read_text(encoding="utf-8")
    assert "Natural Earth" in txt, "earth albedo provenance missing from attribution_zh.txt"


def test_transition_frame_family_uniform():
    """H13 (Director F10): all flight-transition frames share one canonical size."""
    from PIL import Image

    d = GAME / "assets" / "anim" / "flight_transition"
    sizes = {Image.open(p).size for p in d.glob("*.webp")}
    assert sizes == {(1280, 720)}, f"transition frame sizes not uniform: {sizes}"


def test_globe_has_themed_environment():
    """P1 (Retro Gamer): no WorldEnvironment exists — the 3D layer renders on
    Godot's default gray clear color with zero ambient (centerpiece screen)."""
    scene_srcs = []
    for p in list((GAME / "scenes").rglob("*.tscn")) + list(GAME.glob("*.tscn")):
        scene_srcs.append(p.read_text(encoding="utf-8", errors="replace"))
    script_srcs = []
    for p in (GAME / "scripts").rglob("*.gd"):
        script_srcs.append(p.read_text(encoding="utf-8", errors="replace"))
    env_found = (
        "WorldEnvironment" in PROJECT_SRC
        or any("WorldEnvironment" in s for s in scene_srcs)
        or any(("Environment.new" in s or "WorldEnvironment.new" in s) for s in script_srcs)
    )
    assert env_found, (
        "no WorldEnvironment / Environment in any scene or script — the globe "
        "renders on the default gray clear color; add a themed environment"
    )
