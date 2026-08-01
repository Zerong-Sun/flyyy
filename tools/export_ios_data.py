#!/usr/bin/env python3
"""Export a compact, deterministic data snapshot for the iOS Design Canvas demo.

The exporter reads the same generated Godot JSON/split data that the game uses,
filters it to the curated iOS network, adds the iOS-only catalog entries, and
updates the generated data block inside the .dc.html file.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
from datetime import datetime, timedelta, timezone
from pathlib import Path
from zoneinfo import ZoneInfo


ROOT = Path(__file__).resolve().parents[1]
WORLD_PATH = ROOT / "game" / "data" / "world.json"
FLIGHTS_DIR = ROOT / "game" / "data" / "flights"
MARKETS_DIR = ROOT / "game" / "data" / "markets"
IOS_DIR = ROOT / "ios"
HTML_PATH = IOS_DIR / "Airborne Trader iOS.dc.html"
CITY_CONFIG_PATH = IOS_DIR / "config" / "curated_cities.json"
EXTRA_PRODUCTS_PATH = IOS_DIR / "config" / "extra_products.json"

BEGIN_MARKER = "// BEGIN GENERATED IOS DATA"
END_MARKER = "// END GENERATED IOS DATA"
SCHEDULE_DAYS_FROM_BASELINE = 11

COUNTRY_CONTINENTS = {
    "US": "North America", "CA": "North America", "MX": "North America",
    "BR": "South America", "AR": "South America", "CL": "South America",
    "CO": "South America", "PE": "South America",
    "GB": "Europe", "FR": "Europe", "DE": "Europe", "NL": "Europe",
    "IT": "Europe", "ES": "Europe", "RU": "Europe", "CH": "Europe",
    "SE": "Europe", "NO": "Europe", "DK": "Europe", "FI": "Europe",
    "IE": "Europe", "BE": "Europe", "TR": "Europe",
    "CN": "Asia", "JP": "Asia", "KR": "Asia", "HK": "Asia",
    "TW": "Asia", "IN": "Asia", "SG": "Asia", "TH": "Asia",
    "AE": "Asia", "QA": "Asia", "EG": "Africa", "AU": "Oceania",
    "NZ": "Oceania",
}

CATEGORY_ICON = {
    "电子": "assets/products/p_cat_electronics.webp",
    "Electronics": "assets/products/p_cat_electronics.webp",
    "机械": "assets/products/p_cat_machinery.webp",
    "Machinery": "assets/products/p_cat_machinery.webp",
    "能源": "assets/products/p_cat_energy.webp",
    "Energy": "assets/products/p_cat_energy.webp",
    "工艺品": "assets/products/p_cat_crafts.webp",
    "Crafts": "assets/products/p_cat_crafts.webp",
    "陶瓷": "assets/products/p_cat_crafts.webp",
    "Ceramics": "assets/products/p_cat_crafts.webp",
    "玩具": "assets/products/p_cat_toys.webp",
    "Toys": "assets/products/p_cat_toys.webp",
}


def load_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def stable_unit(*parts: object) -> float:
    digest = hashlib.sha256("|".join(map(str, parts)).encode("utf-8")).hexdigest()
    return int(digest[:12], 16) / float(16**12 - 1)


def haversine_km(a: dict, b: dict) -> float:
    radius = 6371.0
    r = math.pi / 180.0
    d_lat = (b["latitude"] - a["latitude"]) * r
    d_lon = (b["longitude"] - a["longitude"]) * r
    x = math.sin(d_lat / 2) ** 2 + math.cos(a["latitude"] * r) * math.cos(b["latitude"] * r) * math.sin(d_lon / 2) ** 2
    return 2 * radius * math.asin(min(1.0, math.sqrt(x)))


def choose_airports(world: dict, city_ids: list[str]) -> dict[str, dict]:
    by_city: dict[str, list[dict]] = {}
    for airport in world["airports"]:
        by_city.setdefault(airport["city_id"], []).append(airport)
    selected: dict[str, dict] = {}
    for city_id in city_ids:
        choices = by_city.get(city_id, [])
        if not choices:
            raise ValueError(f"No airport found for curated city: {city_id}")
        choices.sort(key=lambda a: (not a.get("has_passenger_service", False), not a.get("has_scheduled_service", False), a["airport_id"]))
        selected[city_id] = choices[0]
    return selected


def offset_for(world: dict, timezone_name: str, baseline_date: str) -> float:
    return float(world.get("tz_offsets", {}).get(timezone_name, {}).get(baseline_date, 0.0))


def city_asset(city_id: str) -> str:
    aliases = {"hong_kong": "hongkong"}
    stem = aliases.get(city_id, city_id)
    candidate = IOS_DIR / "assets" / "cities" / f"city_{stem}.webp"
    if candidate.exists():
        return f"assets/cities/{candidate.name}"
    return "assets/brand/splash.webp"


def build_cities(world: dict, city_ids: list[str]) -> tuple[list[dict], dict[str, dict], dict[str, dict]]:
    city_records = {c["city_id"]: c for c in world["cities"]}
    airports = choose_airports(world, city_ids)
    out: list[dict] = []
    for city_id in city_ids:
        source = city_records[city_id]
        airport = airports[city_id]
        country_id = source.get("country_id", airport.get("country_id", "XX"))
        out.append({
            "id": city_id,
            "name": source.get("name_en") or source.get("name_zh") or city_id,
            "name_zh": source.get("name_zh", city_id),
            "name_en": source.get("name_en", city_id.replace("_", " ").title()),
            "airport": airport.get("name_en") or airport.get("name_zh") or city_id,
            "airport_zh": airport.get("name_zh", ""),
            "iata": airport["iata"],
            "icao": airport.get("icao", ""),
            "country": source.get("country_zh") or airport.get("country_zh", country_id),
            "country_en": airport.get("country_id", country_id),
            "country_id": country_id,
            "cont": COUNTRY_CONTINENTS.get(country_id, "Other"),
            "timezone": source.get("timezone") or airport.get("timezone", "UTC"),
            "tz": offset_for(world, source.get("timezone") or airport.get("timezone", "UTC"), world["meta"]["baseline_date"]),
            "lat": float(airport["latitude"]),
            "lon": float(airport["longitude"]),
            "elev": round(float(airport.get("elevation_ft", 0))),
            "hero": city_asset(city_id),
            "image_asset_id": source.get("image_asset_id", ""),
            "content_confidence": source.get("content_confidence", "C"),
        })
    return out, airports, city_records


def build_routes(world: dict, airports: dict[str, dict], city_ids: set[str]) -> list[dict]:
    iata_to_city = {a["iata"]: city_id for city_id, a in airports.items()}
    seen: set[tuple[str, str]] = set()
    routes: list[dict] = []
    for route in world["routes"]:
        origin = route["origin"]
        destination = route["destination"]
        if origin not in iata_to_city or destination not in iata_to_city or origin == destination:
            continue
        key = (origin, destination)
        if key in seen:
            continue
        seen.add(key)
        origin_city = iata_to_city[origin]
        destination_city = iata_to_city[destination]
        routes.append({
            "origin_iata": origin,
            "destination_iata": destination,
            "origin_city_id": origin_city,
            "destination_city_id": destination_city,
            "distance_km": round(haversine_km(airports[origin_city], airports[destination_city]), 1),
        })
    routes.sort(key=lambda r: (r["origin_iata"], r["destination_iata"]))
    return routes


def parse_utc(iso_value: str) -> datetime:
    return datetime.fromisoformat(iso_value.replace("Z", "+00:00"))


def local_minute(iso_value: str, timezone_name: str) -> int:
    value = parse_utc(iso_value).astimezone(ZoneInfo(timezone_name))
    return value.hour * 60 + value.minute


def format_duration(minutes: int) -> str:
    return f"{minutes // 60}h {minutes % 60:02d}m"


def build_flights(world: dict, airports: dict[str, dict], routes: list[dict], city_ids: set[str], schedule_date: str) -> list[dict]:
    iata_to_city = {a["iata"]: city_id for city_id, a in airports.items()}
    route_keys = {(r["origin_iata"], r["destination_iata"]) for r in routes}
    selected: list[dict] = []
    for city_id, airport in airports.items():
        path = FLIGHTS_DIR / f"{airport['airport_id']}.json"
        if not path.exists():
            continue
        for flight in load_json(path):
            origin = flight.get("origin_iata", "")
            destination = flight.get("destination_iata", "")
            if (origin, destination) not in route_keys:
                continue
            if not str(flight.get("scheduled_departure_utc", "")).startswith(schedule_date):
                continue
            destination_city = iata_to_city.get(destination)
            if not destination_city:
                continue
            duration = int(flight.get("duration_minutes", 0))
            selected.append({
                "id": flight["flight_instance_id"],
                "origin_iata": origin,
                "destination_iata": destination,
                "origin_city_id": city_id,
                "destination_city_id": destination_city,
                "flight_no": flight.get("marketing_flight_number", ""),
                "airline": flight.get("airline_name", ""),
                "departure_utc": flight["scheduled_departure_utc"],
                "arrival_utc": flight["scheduled_arrival_utc"],
                "dep_min": local_minute(flight["scheduled_departure_utc"], airport["timezone"]),
                "arr_min": local_minute(flight["scheduled_arrival_utc"], airports[destination_city]["timezone"]),
                "distance_km": round(float(flight.get("distance_km", 0)), 1),
                "duration_min": duration,
                "duration_text": format_duration(duration),
                "economy": round(float(flight.get("ticket_base_price_economy", 0)), 2),
                "business": round(float(flight.get("ticket_base_price_business", 0)), 2),
                "business_available": bool(flight.get("cabin_business_available", True)),
                "data_source": flight.get("data_source", "synthetic_openflights"),
                "data_confidence": flight.get("data_confidence", "C"),
            })
    selected.sort(key=lambda f: (f["origin_iata"], f["dep_min"], f["destination_iata"], f["id"]))
    return selected


def icon_for_product(product: dict) -> str:
    category = str(product.get("category", ""))
    if category in CATEGORY_ICON:
        return CATEGORY_ICON[category]
    return "assets/products/p_generic.webp"


def normalize_product(product: dict, source: str) -> dict:
    name_zh = product.get("name_zh", product.get("name", product["product_id"]))
    name_en = product.get("name_en", "")
    return {
        "id": product["product_id"],
        "name": name_en or name_zh,
        "name_zh": name_zh,
        "name_en": name_en or name_zh,
        "category": product.get("category", "General"),
        "home": product["origin_city_id"],
        "home_country": product.get("origin_country_id", ""),
        "icon": icon_for_product(product),
        "w": round(float(product.get("weight_kg", 1.0)), 2),
        "base": round(float(product.get("base_reference_price", 100.0)), 2),
        "shelf_life_hours": float(product.get("shelf_life_hours", 99999)),
        "fragility": float(product.get("fragility", 0.0)),
        "rarity": float(product.get("rarity", 0.5)),
        "description": product.get("description", ""),
        "source": source,
    }


def build_products(world: dict, city_ids: list[str], extra_products: list[dict]) -> list[dict]:
    selected = set(city_ids)
    source_products = [p for p in world["products"] if p.get("origin_city_id") in selected]
    by_city: dict[str, list[dict]] = {}
    for product in source_products:
        by_city.setdefault(product["origin_city_id"], []).append(product)
    products: list[dict] = []
    for city_id in city_ids:
        city_products = sorted(by_city.get(city_id, []), key=lambda p: p["product_id"])
        if len(city_products) < 5:
            raise ValueError(f"Curated city {city_id} has fewer than 5 Godot products")
        products.extend(normalize_product(p, "godot_world") for p in city_products[:5])
    for extra in extra_products:
        if extra["city_id"] not in selected:
            raise ValueError(f"Extra product belongs to unselected city: {extra['city_id']}")
        product = dict(extra)
        product["product_id"] = f"ios_{extra['city_id']}_{extra['slug']}"
        product["origin_city_id"] = extra["city_id"]
        product["origin_country_id"] = ""
        products.append(normalize_product(product, "ios_catalog"))
    if len(products) != 200:
        raise ValueError(f"Expected exactly 200 products, got {len(products)}")
    if len({p["id"] for p in products}) != len(products):
        raise ValueError("Duplicate product IDs in iOS catalog")
    return products


def synthetic_market(product: dict, city_id: str) -> tuple[float, float]:
    base = product["base"]
    if product["home"] == city_id:
        buy = base * (0.78 + stable_unit(product["id"], city_id, "origin") * 0.08)
        sell = buy * (1.04 + stable_unit(product["id"], city_id, "origin_sell") * 0.08)
    else:
        buy = base * (1.04 + stable_unit(product["id"], city_id, "import") * 0.34)
        sell = buy * (1.08 + stable_unit(product["id"], city_id, "remote_sell") * 0.28)
    return round(buy, 2), round(sell, 2)


def build_markets(world: dict, city_ids: list[str], products: list[dict]) -> list[dict]:
    source_markets: dict[tuple[str, str], tuple[float, float]] = {}
    for city_id in city_ids:
        path = MARKETS_DIR / f"{city_id}.json"
        if not path.exists():
            raise ValueError(f"Missing Godot market file: {path}")
        for row in load_json(path):
            source_markets[(city_id, row["p"])] = (float(row["b"]), float(row["s"]))
    markets: list[dict] = []
    for city_id in city_ids:
        for product in products:
            values = source_markets.get((city_id, product["id"]))
            source = "godot_market" if values else "ios_synthetic"
            buy, sell = values if values else synthetic_market(product, city_id)
            markets.append({
                "city_id": city_id,
                "product_id": product["id"],
                "buy_base_usd": round(buy, 2),
                "sell_base_usd": round(sell, 2),
                "source": source,
            })
    return markets


def build_snapshot() -> dict:
    world = load_json(WORLD_PATH)
    city_ids = load_json(CITY_CONFIG_PATH)
    extra_products = load_json(EXTRA_PRODUCTS_PATH)
    if len(city_ids) != 30 or len(set(city_ids)) != 30:
        raise ValueError("curated_cities.json must contain exactly 30 unique cities")
    if len(extra_products) != 50:
        raise ValueError("extra_products.json must contain exactly 50 products")
    cities, airports, city_source = build_cities(world, city_ids)
    selected_ids = set(city_ids)
    routes = build_routes(world, airports, selected_ids)
    baseline = world["meta"]["baseline_date"]
    schedule_date = (datetime.fromisoformat(baseline) + timedelta(days=SCHEDULE_DAYS_FROM_BASELINE)).date().isoformat()
    flights = build_flights(world, airports, routes, selected_ids, schedule_date)
    products = build_products(world, city_ids, extra_products)
    markets = build_markets(world, city_ids, products)
    attributions = [
        {"name": "OurAirports", "license": "Unlicense", "use": "机场标识、坐标、海拔和机场元数据。"},
        {"name": "OpenFlights", "license": "ODbL", "use": "航线拓扑和公开航空网络关系。"},
        {"name": "Natural Earth", "license": "Public domain", "use": "地球陆地与海岸线底图。"},
        {"name": "IANA Time Zone Database", "license": "Public domain", "use": "城市本地时间和夏令时偏移。"},
        {"name": "Airborne Trader", "license": "Original game content", "use": "城市文案、商品目录和游戏经济模型。"},
    ]
    return {
        "meta": {
            "schema_version": "ios-demo-1",
            "generated_at": world["meta"].get("generated_at", ""),
            "baseline_date": baseline,
            "schedule_date": schedule_date,
            "schedule_window_days": 1,
            "city_count": len(cities),
            "product_count": len(products),
            "route_count": len(routes),
            "flight_count": len(flights),
            "market_count": len(markets),
        },
        "cities": cities,
        "products": products,
        "routes": routes,
        "flights": flights,
        "markets": markets,
        "attributions": attributions,
        "disclaimer": "航线拓扑来源于 OpenFlights，机场信息来源于 OurAirports；航班时刻、票价和商品市场价格为游戏模拟数据，不是真实购票或行情信息。",
    }


def generated_block(snapshot: dict) -> str:
    payload = json.dumps(snapshot, ensure_ascii=False, separators=(",", ":"))
    return f"{BEGIN_MARKER}\nconst IOS_DATA = {payload};\n{END_MARKER}"


def update_html(snapshot: dict, check_only: bool = False) -> bool:
    text = HTML_PATH.read_text(encoding="utf-8")
    block = generated_block(snapshot)
    if BEGIN_MARKER in text and END_MARKER in text:
        pattern = re.compile(re.escape(BEGIN_MARKER) + r".*?" + re.escape(END_MARKER), re.S)
        updated = pattern.sub(block, text, count=1)
    else:
        start = text.index("const C=")
        end = text.index("const ADDONS=")
        updated = text[:start] + block + "\n" + text[end:]
    if check_only:
        return updated == text
    HTML_PATH.write_text(updated, encoding="utf-8")
    return True


def validate(snapshot: dict) -> None:
    assert len(snapshot["cities"]) == 30
    assert len(snapshot["products"]) == 200
    assert snapshot["routes"]
    selected_iata = {c["iata"] for c in snapshot["cities"]}
    selected_city_ids = {c["id"] for c in snapshot["cities"]}
    route_pairs = {(r["origin_iata"], r["destination_iata"]) for r in snapshot["routes"]}
    assert all(r["origin_iata"] in selected_iata and r["destination_iata"] in selected_iata for r in snapshot["routes"])
    assert all(f["origin_iata"] in selected_iata and f["destination_iata"] in selected_iata for f in snapshot["flights"])
    assert all(f["origin_city_id"] in selected_city_ids and f["destination_city_id"] in selected_city_ids for f in snapshot["flights"])
    assert all((f["origin_iata"], f["destination_iata"]) in route_pairs for f in snapshot["flights"])
    assert len(snapshot["markets"]) == 30 * 200
    assert all(p["w"] > 0 and p["base"] > 0 and p["home"] in selected_city_ids for p in snapshot["products"])
    assert all(m["buy_base_usd"] > 0 and m["sell_base_usd"] > 0 for m in snapshot["markets"])


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="validate the snapshot and report whether HTML is current")
    parser.add_argument("--json-out", type=Path, help="also write the platform-neutral snapshot as JSON")
    args = parser.parse_args()
    snapshot = build_snapshot()
    validate(snapshot)
    current = update_html(snapshot, check_only=args.check)
    if args.json_out and not args.check:
        args.json_out.parent.mkdir(parents=True, exist_ok=True)
        args.json_out.write_text(json.dumps(snapshot, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"meta": snapshot["meta"], "html_current": current}, ensure_ascii=False, indent=2))
    return 0 if not args.check or current else 1


if __name__ == "__main__":
    raise SystemExit(main())
