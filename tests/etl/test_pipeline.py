import json
import sqlite3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "etl" / "out"
GAME = ROOT / "game" / "data"


def test_twenty_airports_sqlite():
    con = sqlite3.connect(OUT / "world.sqlite")
    n = con.execute("SELECT COUNT(*) FROM airports").fetchone()[0]
    assert n == 20
    con.close()


def test_route_degree_min_8():
    con = sqlite3.connect(OUT / "world.sqlite")
    rows = con.execute("SELECT origin_iata, COUNT(*) FROM routes GROUP BY origin_iata").fetchall()
    assert len(rows) == 20
    for iata, deg in rows:
        assert deg >= 8, iata
    con.close()


def test_business_price_10x():
    con = sqlite3.connect(OUT / "flights_2025_03.sqlite")
    row = con.execute(
        "SELECT ticket_base_price_economy, ticket_base_price_business FROM flight_instance LIMIT 1"
    ).fetchone()
    eco, biz = row
    assert abs(biz - eco * 10) < 0.02
    con.close()


def test_products_per_city_ge_5():
    world = json.loads((GAME / "world.json").read_text(encoding="utf-8"))
    by = {}
    for p in world["products"]:
        by.setdefault(p["origin_city_id"], 0)
        by[p["origin_city_id"]] += 1
    assert len(by) == 20
    for cid, n in by.items():
        assert n >= 5, cid


def test_flights_indexed_by_origin():
    data = json.loads((GAME / "flights.json").read_text(encoding="utf-8"))
    assert data["flight_count"] > 1000
    assert "atl" in data["by_origin"]
    assert data["by_origin"]["atl"][0]["scheduled_departure_utc"] <= data["by_origin"]["atl"][-1]["scheduled_departure_utc"]


def test_godot_disclaimer_present():
    world = json.loads((GAME / "world.json").read_text(encoding="utf-8"))
    assert "重建" in world["disclaimer"]
