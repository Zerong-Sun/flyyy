#!/usr/bin/env python3
"""Pure-logic Demo smoke: buy → ticket/baggage/refund rules → FF aging → sell → save."""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WORLD = json.loads((ROOT / "game" / "data" / "world.json").read_text(encoding="utf-8"))
ECONOMY = WORLD["economy"]


def _load_markets_by_city() -> dict:
    markets_dir = ROOT / "game" / "data" / "markets"
    if markets_dir.is_dir():
        return {
            path.stem: json.loads(path.read_text(encoding="utf-8"))
            for path in sorted(markets_dir.glob("*.json"))
        }
    legacy = ROOT / "game" / "data" / "markets.json"
    if legacy.exists():
        return json.loads(legacy.read_text(encoding="utf-8"))
    raise FileNotFoundError("Run the ETL pipeline to generate market data.")


MARKETS_BY_CITY = _load_markets_by_city()


def market_row(city_id: str, product_id: str) -> dict:
    entries = MARKETS_BY_CITY.get(city_id, [])
    for e in entries:
        if e["p"] == product_id:
            return {"city_id": city_id, "product_id": product_id,
                    "buy_base_usd": e["b"], "sell_base_usd": e["s"]}
    raise KeyError(product_id)


def flights_from(origin_airport_id: str) -> list:
    fp = ROOT / "game" / "data" / "flights" / f"{origin_airport_id}.json"
    if fp.exists():
        return json.loads(fp.read_text(encoding="utf-8"))
    return []


def quality_from_hours(shelf_life_hours: float, hours_elapsed: float) -> float:
    if shelf_life_hours >= 90000:
        return 1.0
    return max(0.0, 1.0 - hours_elapsed / shelf_life_hours)


def main() -> int:
    cash = float(ECONOMY["starting_cash_usd"])
    assert abs(cash - 50000.0) < 0.5

    extras = ECONOMY["baggage_extras"]
    assert extras["light"]["extra_kg"] == 10
    assert extras["standard"]["extra_kg"] == 20
    assert extras["heavy"]["extra_kg"] == 50
    assert abs(float(extras["refund_fee_rate"]) - 0.3) < 1e-9

    airport = next(a for a in WORLD["airports"] if a["iata"] == "PVG")
    city_id = airport["city_id"]
    local = next(p for p in WORLD["products"] if p["origin_city_id"] == city_id)
    buy = market_row(city_id, local["product_id"])["buy_base_usd"]
    assert buy > 0
    cash -= buy
    inventory = [
        {
            "product_id": local["product_id"],
            "qty": 1,
            "unit_cost": buy,
            "quality": 1.0,
            "purchased_unix": 0.0,
        }
    ]

    flights = flights_from(airport["airport_id"])
    future = [f for f in flights if f["scheduled_departure_utc"] >= "2025-03-01T00:00:00Z"]
    assert future
    fl = future[0]
    eco = float(fl["ticket_base_price_economy"])
    biz = float(fl["ticket_base_price_business"])
    assert abs(biz - eco * 10) < 0.05

    # Economy + light baggage + one cargo block
    bag = float(extras["light"]["price_usd"])
    cargo = float(extras["cargo_per_50kg_usd"])
    total_paid = eco + bag + cargo
    cash -= total_paid
    assert cash > 0

    # Refund 30% fee before departure
    refund = total_paid * (1.0 - float(extras["refund_fee_rate"]))
    assert abs(refund - total_paid * 0.7) < 1e-6
    cash_after_refund_sim = cash + refund
    assert cash_after_refund_sim > cash

    # Re-buy economy only for rest of loop
    cash = cash_after_refund_sim - eco
    assert cash > 0

    life = float(local["shelf_life_hours"])
    hours = 24.0
    quality = quality_from_hours(life, hours)
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
        "last_market_date": "2025-03-02",
    }
    assert save["current_airport_id"] != airport["airport_id"]
    assert len(save["travel_log"]) == 1
    assert WORLD["tz_offsets"]["America/New_York"]["2025-03-10"] == -4.0

    # Theme / font / icon / globe placeholders present for Demo UI
    fonts = ROOT / "game" / "assets" / "fonts"
    assert (fonts / "NotoSansSC-Regular.otf").is_file()
    assert (fonts / "JetBrainsMono-Regular.ttf").is_file()
    assert (ROOT / "game" / "themes" / "DemoColors.gd").is_file()
    assert (ROOT / "game" / "themes" / "ThemeFactory.gd").is_file()
    assert (ROOT / "game" / "themes" / "IconFactory.gd").is_file()
    globe_src = (ROOT / "game" / "scripts" / "render" / "GlobeController.gd").read_text(encoding="utf-8")
    assert "earth_albedo_placeholder.png" in globe_src
    assert "_build_grid_overlay" in globe_src
    assert "_make_pin_mesh" in globe_src
    assert (ROOT / "game" / "assets" / "earth" / "earth_albedo_placeholder.png").is_file()

    print(
        "SMOKE OK:",
        json.dumps(
            {
                "cash": round(cash, 2),
                "dest": dest["iata"],
                "quality": round(quality, 3),
                "biz_x10": True,
                "baggage_tiers": True,
                "refund_30": True,
                "theme_fonts": True,
                "icon_factory": True,
                "globe_placeholders": True,
            }
        ),
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
