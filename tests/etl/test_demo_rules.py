"""Pure-python simulation of core Demo economy/ticket rules (no Godot)."""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WORLD = json.loads((ROOT / "game" / "data" / "world.json").read_text(encoding="utf-8"))
FLIGHTS = json.loads((ROOT / "game" / "data" / "flights.json").read_text(encoding="utf-8"))


def test_starting_cash_and_baggage_constants():
    eco = WORLD["economy"]
    assert eco["starting_cash_usd"] > 1000
    assert eco["ticket"]["business_multiplier"] == 10
    assert eco["ticket"]["baggage_economy_kg"] == 20
    assert eco["ticket"]["baggage_business_kg"] == 60
    assert eco["baggage_extras"]["standard"]["extra_kg"] == 20
    assert eco["baggage_extras"]["refund_fee_rate"] == 0.3


def test_origin_buy_cheaper_than_remote_sell_for_specialty():
    # Shanghai specialty sold in London-ish should often have spread after friction
    products = [p for p in WORLD["products"] if p["origin_city_id"] == "shanghai"]
    assert products
    pid = products[0]["product_id"]
    buy_origin = next(m for m in WORLD["markets"] if m["city_id"] == "shanghai" and m["product_id"] == pid)
    sell_remote = next(m for m in WORLD["markets"] if m["city_id"] == "london" and m["product_id"] == pid)
    assert sell_remote["sell_base_usd"] > buy_origin["buy_base_usd"] * 0.9


def test_can_find_future_flight_from_pvg():
    lst = FLIGHTS["by_origin"]["pvg"]
    assert len(lst) > 50
    assert lst[0]["scheduled_departure_utc"] < lst[-1]["scheduled_departure_utc"]
    sample = lst[10]
    assert abs(sample["ticket_base_price_business"] - sample["ticket_base_price_economy"] * 10) < 0.05


def test_cities_have_full_blurbs():
    for c in WORLD["cities"]:
        assert c["short_description"]
        assert c["overview"]
        assert c["history_summary"]
        assert c["food_summary"]
        assert c["travel_note"]
