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
