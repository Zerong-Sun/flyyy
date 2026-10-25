#!/usr/bin/env python3
"""Export a compact content snapshot for the Expo 20-hub mobile profile.

Reads Godot world.json + ios/config/expo_hubs.json, writes
ios/expo/data/ios-data.json, and validates hero/product asset files
under ios/assets/ (Metro require paths use assets/*.webp).
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WORLD_PATH = ROOT / "game" / "data" / "world.json"
HUBS_PATH = ROOT / "ios" / "config" / "expo_hubs.json"
OUT_PATH = ROOT / "ios" / "expo" / "data" / "ios-data.json"
ASSETS = ROOT / "ios" / "assets"
ASSETS_JS = ROOT / "ios" / "expo" / "src" / "assets.js"

# Runtime IDs match Godot; only legacy artwork uses the short spelling.
CITY_ID_ALIAS = {}


def load_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def expo_city_id(city_id: str) -> str:
    return CITY_ID_ALIAS.get(city_id, city_id)


def city_hero(city_id: str) -> str:
    return "assets/city_" + {"hong_kong": "hongkong"}.get(city_id, city_id) + ".webp"


def build_snapshot() -> dict:
    hubs = load_json(HUBS_PATH)
    if len(hubs) < 12:
        raise ValueError("expo_hubs.json must list at least 12 hubs")
    world = load_json(WORLD_PATH) if WORLD_PATH.is_file() else {"cities": [], "products": [], "meta": {}}
    world_cities = {c["city_id"]: c for c in world.get("cities", [])}
    world_products = world.get("products", [])
    airports = {a["city_id"]: a for a in world.get("airports", [])}
    airport_cities = {a["iata"]: a["city_id"] for a in world.get("airports", [])}

    cities = []
    missing_cities = []
    for cid in hubs:
        eid = expo_city_id(cid)
        src = world_cities.get(cid) or world_cities.get(eid)
        if not src:
            missing_cities.append(cid)
            cities.append({
                "id": eid,
                "source_id": cid,
                "hero": city_hero(cid),
                "note": "",
            })
            continue
        airport = airports.get(cid, {})
        cities.append({
            "iata": airport.get("iata"),
            "icao": airport.get("icao"),
            "id": eid,
            "source_id": cid,
            "name": src.get("name_en") or src.get("name") or eid,
            "country": src.get("country_id") or "",
            "lat": airport.get("latitude"),
            "lon": airport.get("longitude"),
            "hero": city_hero(cid),
            "timezone": src.get("timezone") or "",
        })

    expo_hubs = {expo_city_id(h) for h in hubs}
    hub_set = set(hubs) | expo_hubs
    products = []
    for p in world_products:
        home = p.get("origin_city_id") or p.get("home_city_id") or p.get("home")
        if not home:
            continue
        if home not in hub_set and expo_city_id(home) not in expo_hubs:
            continue
        products.append({
            "id": p.get("product_id") or p.get("id"),
            "home": expo_city_id(home),
            "name": p.get("name_en") or p.get("name_zh") or p.get("name"),
            "category": p.get("category") or "",
            "w": float(p.get("weight_kg") or p.get("w") or 1),
            "base": float(p.get("base_reference_price") or p.get("base_price_usd") or p.get("base") or 0),
        })

    return {
        "meta": {
            "schema_version": "expo-demo-1",
            "hub_count": len(cities),
            "product_count": len(products),
            "generated_from": "game/data/world.json" if WORLD_PATH.is_file() else "hubs-only",
            "missing_world_cities": missing_cities,
        },
        "cities": cities,
        "products": products,
        "routes": sorted({(airport_cities.get(r["origin"]), airport_cities.get(r["destination"]))
                          for r in world.get("routes", [])
                          if airport_cities.get(r["origin"]) in hubs and airport_cities.get(r["destination"]) in hubs}),
        "journey_events": load_json(ROOT / "etl/config/runtime/journey_events.json"),
        "merchant_rules": load_json(ROOT / "etl/config/runtime/merchant_rules.json"),
        "mobile_balance": load_json(ROOT / "ios" / "config" / "mobile_balance.json"),
        # Challenge scoring config so the demo's future challenge port reads the
        # same numbers as Godot (GDLC Playtest #2 ratchet).
        "economy": {
            "challenge": world.get("economy", {}).get("challenge", {}),
        },
    }


def validate_assets(snapshot: dict) -> list[str]:
    warnings: list[str] = []
    for city in snapshot["cities"]:
        hero = city["hero"].replace("assets/", "")
        path = ASSETS / hero
        if not path.is_file():
            warnings.append(f"missing city hero: {path}")
    if ASSETS_JS.is_file():
        text = ASSETS_JS.read_text(encoding="utf-8")
        for city in snapshot["cities"]:
            key = city["hero"]
            if key not in text and city["id"] not in text:
                warnings.append(f"assets.js may lack require for {key}")
    return warnings


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="validate only; do not write")
    parser.add_argument("--json-out", type=Path, default=OUT_PATH)
    args = parser.parse_args()
    snapshot = build_snapshot()
    warnings = validate_assets(snapshot)
    if not args.check:
        args.json_out.parent.mkdir(parents=True, exist_ok=True)
        args.json_out.write_text(json.dumps(snapshot, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        if args.json_out == OUT_PATH:
            runtime = {key: snapshot[key] for key in ("cities", "routes", "mobile_balance", "journey_events", "merchant_rules")}
            (ROOT / "ios/expo/src/worldContent.js").write_text(
                "// Generated by tools/export_expo_data.py. Do not edit.\nexport const WORLD_CONTENT = "
                + json.dumps(runtime, ensure_ascii=False, indent=2) + ";\n", encoding="utf-8")
    print(json.dumps({"meta": snapshot["meta"], "warnings": warnings, "out": str(args.json_out)}, ensure_ascii=False, indent=2))
    return 1 if (args.check and warnings) else 0


if __name__ == "__main__":
    raise SystemExit(main())
