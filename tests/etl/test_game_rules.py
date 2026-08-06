"""Pure Python mirrors of Demo game rules fixed in verification pass."""
from __future__ import annotations

from datetime import date


def quality_from_hours(shelf_life_hours: float, hours_elapsed: float) -> float:
    if shelf_life_hours >= 90000:
        return 1.0
    return max(0.0, 1.0 - hours_elapsed / shelf_life_hours)


def day_delta(prev: str, new: str) -> int:
    if prev == new or not prev or not new:
        return 0
    a = date.fromisoformat(prev)
    b = date.fromisoformat(new)
    return max(0, (b - a).days)


def recover_pressure(pressure: float, days: int, rate: float = 0.05) -> float:
    return max(0.0, pressure - rate * days)


def refund_amount(total_paid: float, fee_rate: float = 0.3) -> float:
    return total_paid * (1.0 - fee_rate)


def business_price(economy: float) -> float:
    return economy * 10.0


def test_quality_ages_with_wait():
    assert quality_from_hours(240, 0) == 1.0
    assert abs(quality_from_hours(240, 120) - 0.5) < 1e-9
    assert quality_from_hours(240, 300) == 0.0
    assert quality_from_hours(99999, 10000) == 1.0


def test_multi_day_demand_recovery():
    assert day_delta("2025-03-01", "2025-03-05") == 4
    assert abs(recover_pressure(0.4, 4) - 0.2) < 1e-9


def test_refund_fee_30_percent():
    assert abs(refund_amount(1000) - 700) < 1e-9


def test_business_is_10x():
    assert business_price(123.45) == 1234.5


def test_baggage_tiers_match_economy_yaml():
    import yaml
    from pathlib import Path

    eco = yaml.safe_load((Path(__file__).resolve().parents[2] / "etl" / "config" / "economy.yaml").read_text())
    extras = eco["baggage_extras"]
    assert extras["light"]["extra_kg"] == 10
    assert extras["standard"]["extra_kg"] == 20
    assert extras["heavy"]["extra_kg"] == 50
    assert abs(extras["refund_fee_rate"] - 0.3) < 1e-9
    assert eco["ticket"]["business_multiplier"] == 10.0
    assert eco["ticket"]["baggage_business_kg"] == 60.0
    assert abs(eco["starting_cash_usd"] - 50000.0) < 0.5


def test_theme_fonts_and_colors_present():
    from pathlib import Path

    root = Path(__file__).resolve().parents[2]
    assert (root / "game" / "assets" / "fonts" / "NotoSansSC-Regular.otf").stat().st_size > 100_000
    assert (root / "game" / "assets" / "fonts" / "JetBrainsMono-Regular.ttf").stat().st_size > 10_000
    colors = (root / "game" / "themes" / "DemoColors.gd").read_text(encoding="utf-8")
    assert "E89A3C" in colors  # accent-amber
    assert "0B1C2C" in colors  # bg-deep
    factory = (root / "game" / "themes" / "ThemeFactory.gd").read_text(encoding="utf-8")
    assert "NotoSansSC-Regular.otf" in factory
    assert "static func build(" in factory
