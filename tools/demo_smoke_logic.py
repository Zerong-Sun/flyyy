#!/usr/bin/env python3
"""Pure-logic Demo smoke: open → buy → ticket math → FF aging → sell → save fields."""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WORLD = json.loads((ROOT / "game" / "data" / "world.json").read_text(encoding="utf-8"))
FLIGHTS = json.loads((ROOT / "game" / "data" / "flights.json").read_text(encoding="utf-8"))


def market_row(city_id: str, product_id: str) -> dict:
    for m in WORLD["markets"]:
        if m["city_id"] == city_id and m["product_id"] == product_id:
            return m
    raise KeyError(product_id)


def main() -> int:
    cash = float(WORLD["economy"]["starting_cash_usd"])
    airport = next(a for a in WORLD["airports"] if a["iata"] == "PVG")
    city_id = airport["city_id"]
    local = next(p for p in WORLD["products"] if p["origin_city_id"] == city_id)
    buy = market_row(city_id, local["product_id"])["buy_base_usd"]
    assert buy > 0
    cash -= buy
    inventory = [{"product_id": local["product_id"], "qty": 1, "unit_cost": buy, "quality": 1.0}]

    flights = FLIGHTS["by_origin"][airport["airport_id"]]
    future = [f for f in flights if f["scheduled_departure_utc"] >= "2025-03-01T00:00:00Z"]
    assert future
    fl = future[0]
    eco = fl["ticket_base_price_economy"]
    biz = fl["ticket_base_price_business"]
    assert abs(biz - eco * 10) < 0.05
    cash -= eco
    assert cash > 0

    # Simulate FF quality aging for perishable
    life = float(local["shelf_life_hours"])
    hours = 24.0
    quality = max(0.0, 1.0 - hours / life) if life < 90000 else 1.0
    inventory[0]["quality"] = quality

    dest = next(a for a in WORLD["airports"] if a["airport_id"] == fl["destination_airport_id"])
    sell = market_row(dest["city_id"], local["product_id"])["sell_base_usd"]
    revenue = sell * quality
    cash += revenue
    save = {
        "cash_usd": cash,
        "current_airport_id": dest["airport_id"],
        "inventory": inventory,
        "travel_log": [{"flight": fl["marketing_flight_number"], "to": dest["iata"]}],
    }
    assert save["current_airport_id"] != airport["airport_id"]
    assert len(save["travel_log"]) == 1
    # DST table present
    assert WORLD["tz_offsets"]["America/New_York"]["2025-03-10"] == -4.0
    print("SMOKE OK:", json.dumps({"cash": round(cash, 2), "dest": dest["iata"], "quality": round(quality, 3)}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
