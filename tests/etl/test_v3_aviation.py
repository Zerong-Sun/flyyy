"""v0.3 aviation data layer: MCT, alliances, stopovers, reliability, cold-chain, DG."""
from __future__ import annotations

import json
from pathlib import Path

import pytest
import yaml

ROOT = Path(__file__).resolve().parents[2]
CFG = ROOT / "etl" / "config"
GAME_DATA = ROOT / "game" / "data"


def test_airlines_yaml_alliances_cover_catalog():
    raw = yaml.safe_load((CFG / "airlines.yaml").read_text(encoding="utf-8"))
    alliance_ids = {a["id"] for a in raw["alliances"]}
    assert {"star", "oneworld", "skyteam", "none"} <= alliance_ids
    for row in raw["airlines"]:
        assert row["alliance_id"] in alliance_ids
        assert row["id"] and row["name"]


def test_dangerous_goods_classes_matrix():
    dg = yaml.safe_load((CFG / "dangerous_goods.yaml").read_text(encoding="utf-8"))
    classes = dg["classes"]
    assert classes["none"]["cabin_ok"] is True
    assert classes["restricted_cabin"]["cabin_ok"] is False
    assert classes["restricted_cabin"]["cargo_ok"] is True
    assert classes["forbidden"]["cabin_ok"] is False
    assert "机械" in dg["category_defaults"]


def test_economy_v3_keys():
    eco = yaml.safe_load((CFG / "economy.yaml").read_text(encoding="utf-8"))
    assert eco["ticket"]["first_multiplier"] >= eco["ticket"]["business_multiplier"]
    assert eco["ticket"]["baggage_first_kg"] > eco["ticket"]["baggage_business_kg"]
    assert "cold" in eco["baggage_extras"]
    assert eco["baggage_extras"]["cold"].get("enables_cold_chain") is True
    assert eco["mct"]["default_min"] >= 60
    assert eco["reliability"]["delay_prob"] < 0.5
    assert eco["cold_chain"]["protected_decay_mult"] < eco["cold_chain"]["unprotected_decay_mult"]


def test_airport_mct_helper():
    from etl.scripts import run_pipeline as rp

    eco = {"mct": {"default_min": 90, "international_min": 120}}
    ap = {"mct_minutes": 75}
    assert rp.airport_mct_minutes(ap, eco) == 75
    assert rp.airport_mct_minutes({}, eco, international=True) == 120
    assert rp.airport_mct_minutes({}, eco, international=False) == 90


def test_hazmat_and_cold_helpers():
    from etl.scripts import run_pipeline as rp

    rp._DG_RULES = yaml.safe_load((CFG / "dangerous_goods.yaml").read_text(encoding="utf-8"))
    assert rp.resolve_hazmat_class("机械") == "restricted_cabin"
    assert rp.resolve_hazmat_class("茶叶") == "none"
    assert rp.product_requires_cold("食品", 24, "none") is True
    assert rp.product_requires_cold("工艺品", 99999, "none") is False


def test_world_json_v3_fields_if_present():
    """When world.json has been regenerated with etl 0.3, assert schema."""
    path = GAME_DATA / "world.json"
    if not path.exists():
        pytest.skip("world.json missing")
    world = json.loads(path.read_text(encoding="utf-8"))
    meta = world.get("meta") or {}
    # Accept pre-0.3 until pipeline re-run; soft assert structure when version bumps
    if str(meta.get("etl_version", "")).startswith("0.3"):
        eco = world["economy"]
        assert "mct" in eco
        assert "reliability" in eco
        assert "cold_chain" in eco
        assert world.get("alliances")
        assert world.get("dangerous_goods")
        airlines = world["airlines"]
        assert all("alliance_id" in a for a in airlines)
        products = world["products"]
        assert all("hazmat_class" in p for p in products)
        assert any(p.get("requires_cold_chain") for p in products)
        airports = world["airports"]
        assert any("mct_minutes" in a for a in airports)
        report = world.get("coverage_report") or {}
        assert str(report.get("etl_version", "")).startswith("0.3")
        assert "stopover_flights" in report


def test_transfer_edge_includes_mct_when_built():
    from etl.scripts.run_pipeline import build_transfer_edges

    airports = {
        "AAA": {"latitude": 0.0, "longitude": 0.0, "country_id": "AA", "mct_minutes": 80},
        "HHH": {"latitude": 10.0, "longitude": 10.0, "country_id": "HH", "mct_minutes": 100},
        "BBB": {"latitude": 20.0, "longitude": 20.0, "country_id": "BB"},
        "CCC": {"latitude": 5.0, "longitude": 5.0, "country_id": "CC"},
        "DDD": {"latitude": 15.0, "longitude": 15.0, "country_id": "DD"},
        "EEE": {"latitude": 8.0, "longitude": 8.0, "country_id": "EE"},
        "FFF": {"latitude": 12.0, "longitude": 12.0, "country_id": "FF"},
        "GGG": {"latitude": 18.0, "longitude": 18.0, "country_id": "GG"},
        "III": {"latitude": 22.0, "longitude": 22.0, "country_id": "II"},
        "JJJ": {"latitude": 25.0, "longitude": 25.0, "country_id": "JJ"},
    }
    # Build a star hub HHH with degree >= 8
    iatas = list(airports.keys())
    routes = set()
    for other in iatas:
        if other == "HHH":
            continue
        routes.add(("HHH", other))
        routes.add((other, "HHH"))
    # No direct AAA→BBB so transfer via HHH should exist
    eco = {"mct": {"default_min": 90, "international_min": 120, "max_connection_min": 480}}
    edges = build_transfer_edges(routes, airports, iatas, eco)
    key = "AAA|BBB"
    assert key in edges
    assert edges[key][0]["hub"] == "HHH"
    assert edges[key][0]["mct_minutes"] == 100


def _load_generated_world_and_flights():
    """Load the regenerated world.json and per-airport flight files."""
    world_path = GAME_DATA / "world.json"
    if not world_path.exists():
        pytest.skip("world.json missing — run ETL first")
    world = json.loads(world_path.read_text(encoding="utf-8"))
    flights: list[dict] = []
    for p in sorted((GAME_DATA / "flights").glob("*.json")):
        if p.name.endswith("_manifest.json"):
            continue
        flights.extend(json.loads(p.read_text(encoding="utf-8")))
    return world, flights


def _load_real_route_airlines():
    """Parse routes.dat preserving real (airline, src, dst) triples."""
    from collections import defaultdict

    from etl.scripts.run_pipeline import _IATA_RE

    route_airlines: dict[tuple[str, str], set[str]] = defaultdict(set)
    path = ROOT / "etl" / "raw" / "routes.dat"
    with path.open(encoding="utf-8", newline="") as f:
        for line in f:
            parts = line.strip().split(",")
            if len(parts) < 6:
                continue
            al, src, dst = parts[0].strip(), parts[2].strip(), parts[4].strip()
            if not _IATA_RE.match(al) or not src or not dst or src == dst:
                continue
            route_airlines[(src, dst)].add(al)
    return route_airlines


def _load_real_airlines():
    """Parse airlines.dat → {IATA: [entries]} with resolved home countries."""
    from functools import lru_cache

    from etl.scripts.run_pipeline import read_real_airlines

    @lru_cache(maxsize=1)
    def _cached() -> dict[str, list[dict]]:
        path = ROOT / "etl" / "raw" / "airlines.dat"
        return read_real_airlines(path) if path.exists() else {}

    return _cached()


def _active_iatas() -> set[str]:
    return {i for i, entries in _load_real_airlines().items() if any(e["active"] == "Y" for e in entries)}


def test_flight_airlines_match_real_route_operators():
    """On routes with an ACTIVE real operator in routes.dat, flights must use one.

    OpenFlights routes.dat is a 2014 snapshot: some operators are defunct (marked
    inactive in airlines.dat) and some routes are noise. pick_airline only commits
    to routes.dat operators when at least one is active; otherwise it falls back to
    a real active airline from an endpoint country (checked by the continent test).
    """
    world, flights = _load_generated_world_and_flights()
    route_airlines = _load_real_route_airlines()
    active = _active_iatas()
    fabricated = []
    for fl in flights:
        if fl.get("data_source") == "bts_2025_03":
            continue  # BTS 2025-03 is newer/authoritative than routes.dat (2014)
        ops = route_airlines.get((fl["origin_iata"], fl["destination_iata"]), set())
        active_ops = ops & active
        if active_ops and fl["operating_airline_id"] not in active_ops:
            fabricated.append(fl["marketing_flight_number"])
    assert not fabricated, f"{len(fabricated)} flights ignore an active real operator: {fabricated[:5]}"


def test_no_third_continent_airline_on_fallback_routes():
    """Synthetic/filled routes must use a real airline from an endpoint continent."""
    from etl.scripts.run_pipeline import country_continent

    world, flights = _load_generated_world_and_flights()
    by_iata = {a["iata"]: a for a in world["airports"]}
    route_airlines = _load_real_route_airlines()
    active = _active_iatas()
    bad = []
    for fl in flights:
        if fl.get("data_source") == "bts_2025_03":
            continue  # BTS 2025-03 is authoritative, not bound by 2014 routes.dat
        ops = route_airlines.get((fl["origin_iata"], fl["destination_iata"]), set())
        if ops & active:
            continue
        airline_cont = country_continent(str(fl.get("airline_home_country", "")))
        o_cont = country_continent(by_iata[fl["origin_iata"]]["country_id"])
        d_cont = country_continent(by_iata[fl["destination_iata"]]["country_id"])
        if not airline_cont or airline_cont not in (o_cont, d_cont):
            bad.append(fl["marketing_flight_number"])
    assert not bad, f"{len(bad)} fallback flights use a third-continent airline: {bad[:5]}"


def test_domestic_routes_prefer_domestic_operator_when_available():
    """On domestic routes, when a real ACTIVE domestic operator exists, use it.

    Uses the per-flight resolved airline_home_country (the actual entry picked for
    that route) rather than the world.json catalog label, which can only hold one
    home country per reused IATA (e.g. G3 = Gol + Sky Express).
    """
    world, flights = _load_generated_world_and_flights()
    by_iata = {a["iata"]: a for a in world["airports"]}
    real = _load_real_airlines()
    route_airlines = _load_real_route_airlines()
    active = _active_iatas()

    def active_countries(al: str) -> set[str]:
        return {e["home_country"] for e in real.get(al, []) if e["active"] == "Y"}

    # Real active domestic operator exists on the route.
    route_has_domestic_operator: set[tuple[str, str]] = set()
    for (o, d), ops in route_airlines.items():
        if o not in by_iata or d not in by_iata:
            continue
        country = by_iata[o]["country_id"]
        if by_iata[d]["country_id"] != country:
            continue
        if any(country in active_countries(al) for al in ops & active):
            route_has_domestic_operator.add((o, d))

    bad = []
    for fl in flights:
        if fl.get("data_source") == "bts_2025_03":
            continue  # real US schedules, not bound by 2014 routes.dat operators
        o, d = fl["origin_iata"], fl["destination_iata"]
        country = by_iata[o]["country_id"]
        if country != by_iata[d]["country_id"]:
            continue
        if fl.get("airline_home_country") == country:
            continue
        if (o, d) in route_has_domestic_operator:
            bad.append(fl["marketing_flight_number"])
    assert not bad, f"{len(bad)} domestic flights use a foreign airline despite a domestic operator: {bad[:5]}"


def test_every_airport_has_international_route():
    """Each airport must have at least one direct international route."""
    world, _ = _load_generated_world_and_flights()
    by_iata = {a["iata"]: a for a in world["airports"]}
    routes = [(r["origin"], r["destination"]) for r in world["routes"]]
    no_intl = [
        iata for iata, a in by_iata.items()
        if a.get("has_passenger_service", False)
        and not any(by_iata[o]["country_id"] != by_iata[d]["country_id"] for o, d in routes if o == iata)
    ]
    assert not no_intl, f"airports without an international route: {sorted(no_intl)}"


def test_world_airlines_catalog_covers_all_operators():
    """Every operating airline must be present in world.json airlines."""
    world, flights = _load_generated_world_and_flights()
    catalog = {a["id"] for a in world["airlines"]}
    operators = {fl["operating_airline_id"] for fl in flights}
    assert operators <= catalog, f"missing airlines in catalog: {sorted(operators - catalog)}"
    assert len(catalog) > 100, "airline catalog not expanded to real operators"


def test_flight_data_source_tags():
    """Every flight must carry a known data_source tag (traceability)."""
    world, flights = _load_generated_world_and_flights()
    assert flights, "no flights to check"
    allowed = {
        "bts_2025_03", "aeroscope_2019",
        "synthetic_openflights", "synthetic_route_fill", "synthetic_stopover",
    }
    bad = {f["flight_instance_id"]: f.get("data_source") for f in flights if f.get("data_source") not in allowed}
    assert not bad, f"unknown data_source tags: {bad}"
    # v0.3.1 must actually use the new real layers somewhere.
    sources = {f.get("data_source") for f in flights}
    assert sources & {"bts_2025_03", "aeroscope_2019"}, (
        f"no real-schedule layers present (got {sorted(sources)})"
    )


def test_bts_flights_real_schedule():
    """US domestic BTS flights must carry real flight numbers + 2025-03 planned times."""
    world, flights = _load_generated_world_and_flights()
    by_iata = {a["iata"]: a for a in world["airports"]}
    bts = [f for f in flights if f.get("data_source") == "bts_2025_03"]
    assert bts, "no bts_2025_03 flights generated"
    bad_route = []
    bad_date = []
    bad_fn = []
    us_carriers = {"AA", "DL", "UA", "WN", "B6", "AS", "NK", "F9", "G4", "HA", "MX", "SY"}
    for f in bts:
        o, d = f["origin_iata"], f["destination_iata"]
        if by_iata[o]["country_id"] != "US" or by_iata[d]["country_id"] != "US":
            bad_route.append(f["flight_instance_id"])
        dep = f["scheduled_departure_utc"]
        # West-coast late departures can spill into 2025-04-01 UTC; only forbid
        # departures before 2025-03-01 or after 2025-04-01.
        if not (dep[:10] >= "2025-03-01" and dep[:10] <= "2025-04-01"):
            bad_date.append(f["flight_instance_id"])
        fn = f["marketing_flight_number"]
        if not (len(fn) >= 3 and fn[:2] in us_carriers and fn[2:].isdigit()):
            bad_fn.append(fn)
    assert not bad_route, f"non-US flights tagged bts_2025_03: {bad_route[:5]}"
    assert not bad_date, f"BTS flights outside 2025-03 schedule: {bad_date[:5]}"
    assert not bad_fn, f"BTS flight numbers look wrong: {bad_fn[:10]}"
    # A known real schedule should be present (AA/UA/DL on JFK-LAX etc.)
    jfk_lax = [f for f in bts if f["origin_iata"] == "JFK" and f["destination_iata"] == "LAX"]
    assert jfk_lax, "no JFK->LAX BTS flights (expected a heavily served US route)"


def test_aeroscope_frequency_drives_schedule():
    """AeroSCOPE-driven flights must respect the configured daily frequency band."""
    world, flights = _load_generated_world_and_flights()
    aero = [f for f in flights if f.get("data_source") == "aeroscope_2019"]
    assert aero, "no aeroscope_2019 flights generated"
    eco = yaml.safe_load((CFG / "economy.yaml").read_text(encoding="utf-8"))
    fmin = int(eco["flight_synth"].get("aeroscope_freq_min", 1))
    fmax = int(eco["flight_synth"].get("aeroscope_freq_max", 4))
    # Convert UTC dep back to origin-local date using the per-day offset table
    # (exact DST handling), then count flights per (route, local day).
    from datetime import datetime, timedelta

    tz_offsets = world.get("tz_offsets", {})
    by_airport = {a["iata"]: a for a in world["airports"]}

    def local_date(iso: str, iata: str) -> str:
        dep = datetime.strptime(iso, "%Y-%m-%dT%H:%M:%SZ")
        table = tz_offsets.get(by_airport[iata].get("timezone", ""), {})
        off = 0.0
        if table:
            day = dep.strftime("%Y-%m-%d")
            if day in table:
                off = float(table[day])
            else:
                keys = sorted(table.keys())
                off = float(table[keys[0]]) if day < keys[0] else float(table[keys[-1]])
        return (dep + timedelta(hours=off)).strftime("%Y-%m-%d")

    counts: dict[tuple[str, str, str], int] = {}
    for f in aero:
        key = (f["origin_iata"], f["destination_iata"], local_date(f["scheduled_departure_utc"], f["origin_iata"]))
        counts[key] = counts.get(key, 0) + 1
    worst = max(counts.values())
    assert worst <= fmax, f"aero route/day exceeds freq_max: max {worst} > {fmax}"
    # Most routes should have >= freq_min flights on most days (sparse tails tolerated).
    under = sum(1 for v in counts.values() if v < fmin)
    assert under <= len(counts) * 0.2, f"{under}/{len(counts)} route-days under freq_min {fmin}"
