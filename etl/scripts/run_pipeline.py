#!/usr/bin/env python3
"""Full Demo ETL: hubs → routes → flights → cities/products → markets → SQLite + JSON for Godot."""
from __future__ import annotations

import csv
import hashlib
import json
import math
import random
import re
import sqlite3
import sys
import zlib
from collections import Counter
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[1]
CFG = ROOT / "config"
RAW = ROOT / "raw"
OUT = ROOT / "out"
CONTENT = ROOT / "content"
GAME_DATA = ROOT.parents[0] / "game" / "data"

# Allow `from etl.content...` imports when run as a plain script / via runpy.
sys.path.insert(0, str(ROOT.parent))
from etl.content.city_content_en import FIELD_EN_MAP, apply_en_fields

EARTH_R_KM = 6371.0


def load_yaml(path: Path):
    with path.open(encoding="utf-8") as f:
        return yaml.safe_load(f)


def haversine_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlmb = math.radians(lon2 - lon1)
    a = math.sin(dphi / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dlmb / 2) ** 2
    return 2 * EARTH_R_KM * math.asin(math.sqrt(a))


def stable_rand(*parts: object) -> random.Random:
    h = hashlib.sha256("|".join(map(str, parts)).encode()).hexdigest()
    return random.Random(int(h[:16], 16))


def read_ourairports_by_iata(path: Path) -> dict[str, dict]:
    if not path.exists():
        return {}
    out: dict[str, dict] = {}
    with path.open(encoding="utf-8", newline="") as f:
        for row in csv.DictReader(f):
            iata = (row.get("iata_code") or "").strip()
            if not iata:
                continue
            try:
                lat = float(row["latitude_deg"])
                lon = float(row["longitude_deg"])
            except (KeyError, ValueError, TypeError):
                continue
            elev = row.get("elevation_ft") or "0"
            try:
                elev_ft = float(elev)
            except ValueError:
                elev_ft = 0.0
            out[iata] = {
                "lat": lat,
                "lon": lon,
                "elev_ft": elev_ft,
                "ident": row.get("ident", ""),
                "type": row.get("type", "large_airport"),
                "municipality": row.get("municipality", ""),
                "iso_country": (row.get("iso_country") or "").strip(),
                "continent": (row.get("continent") or "").strip(),
                "name": (row.get("name") or "").strip(),
            }
    return out


def build_cities_500_from_ourairports(
    oa: dict[str, dict],
    existing_hubs: list[dict],
    openflights_iatas: set[str],
) -> list[dict]:
    """Select 500+ cities from OurAirports data with passenger service.

    Priority rules:
    1. Existing 20 demo hubs (preserved).
    2. Airports that appear in OpenFlights routes (passenger service indicator).
    3. Major airports (large_airport / medium_airport) sorted by if they have routes.
    4. Capital cities / largest airports per country.
    """
    existing_iata = {h["iata"] for h in existing_hubs}
    existing_city = {h["city_id"] for h in existing_hubs}

    # Score airports by: has routes (100), type (large=50, medium=30), then alphabetical
    candidates = []
    for iata, info in oa.items():
        if iata in existing_iata:
            continue
        if not iata or len(iata) != 3:
            continue
        atype = info.get("type", "")
        if atype not in ("large_airport", "medium_airport"):
            continue
        if info["municipality"] == "" and info["name"] == "":
            continue
        has_routes = iata in openflights_iatas
        score = (100 if has_routes else 0)
        if atype == "large_airport":
            score += 50
        elif atype == "medium_airport":
            score += 30
        candidates.append((score, iata, info))

    candidates.sort(key=lambda x: (-x[0], x[1]))

    additional = []
    seen_city_ids: set[str] = set(existing_city)

    for score, iata, info in candidates:
        municipality = info["municipality"] or info["name"] or iata
        # Derive city_id from municipality
        city_id = municipality.lower().replace(" ", "_").replace("/", "_").replace("-", "_")[:30]
        if city_id in seen_city_ids:
            # Same city, just different airport - skip for city list (but airport can still be added)
            continue
        seen_city_ids.add(city_id)

        # Derive country and timezone
        country_id = info.get("iso_country", "XX")
        country_zh = COUNTRY_ZH.get(country_id, "未知")
        timezone = _guess_timezone(info.get("continent", ""), country_id)

        # Get Chinese city name and airport name
        city_zh = _get_city_zh(municipality, country_id)
        city_en = municipality
        name_zh = f"{city_zh}国际机场"
        name_en = f"{municipality} International Airport" if "International" not in municipality else municipality

        additional.append({
            "iata": iata,
            "icao": "",
            "name_zh": name_zh,
            "name_en": name_en,
            "city_id": city_id,
            "city_zh": city_zh,
            "city_en": city_en,
            "country_id": country_id,
            "country_zh": country_zh,
            "timezone": timezone,
            "has_content_file": False,
        })

        if len(additional) >= 480:
            break

    print(f"Selected {len(additional)} additional cities from OurAirports")
    return additional


def _guess_timezone(continent: str, country_id: str) -> str:
    """Guess IANA timezone from continent and country."""
    zone_map = {
        "NA": {"US": "America/Chicago", "CA": "America/Toronto", "MX": "America/Mexico_City"},
        "SA": {"BR": "America/Sao_Paulo", "AR": "America/Argentina/Buenos_Aires"},
        "EU": {
            "GB": "Europe/London", "DE": "Europe/Berlin", "FR": "Europe/Paris",
            "IT": "Europe/Rome", "ES": "Europe/Madrid", "NL": "Europe/Amsterdam",
            "RU": "Europe/Moscow", "TR": "Europe/Istanbul",
        },
        "AS": {
            "CN": "Asia/Shanghai", "JP": "Asia/Tokyo", "KR": "Asia/Seoul",
            "IN": "Asia/Kolkata", "SG": "Asia/Singapore", "TH": "Asia/Bangkok",
            "AE": "Asia/Dubai", "HK": "Asia/Hong_Kong", "TW": "Asia/Taipei",
            "MY": "Asia/Kuala_Lumpur", "ID": "Asia/Jakarta", "PH": "Asia/Manila",
            "VN": "Asia/Ho_Chi_Minh", "SA": "Asia/Riyadh", "IL": "Asia/Jerusalem",
        },
        "AF": {"ZA": "Africa/Johannesburg", "EG": "Africa/Cairo", "NG": "Africa/Lagos"},
        "OC": {"AU": "Australia/Sydney", "NZ": "Pacific/Auckland"},
    }
    cont = zone_map.get(continent, {})
    return cont.get(country_id, "UTC")


def read_openflights_routes(path: Path, hub_iatas: set[str]) -> set[tuple[str, str]]:
    edges: set[tuple[str, str]] = set()
    if not path.exists():
        return edges
    with path.open(encoding="utf-8", newline="") as f:
        for line in f:
            parts = line.strip().split(",")
            if len(parts) < 5:
                continue
            src, dst = parts[2].strip(), parts[4].strip()
            if src in hub_iatas and dst in hub_iatas and src != dst:
                edges.add((src, dst))
    return edges


# country name (airlines.dat) → ISO-3166-1 alpha-2 (matches airport.country_id).
_COUNTRY_NAME_OVERRIDES = {
    "Russia": "RU",
    "Russian Federation": "RU",
    "Russia]]": "RU",
    "Republic of Korea": "KR",
    "South Korea": "KR",
    "Democratic People's Republic of Korea": "KP",
    "Hong Kong SAR of China": "HK",
    "Hong Kong": "HK",
    "Macao": "MO",
    "Macau": "MO",
    "Taiwan": "TW",
    "Ivory Coast": "CI",
    "Cote d'Ivoire": "CI",
    "Congo (Brazzaville)": "CG",
    "Congo (Kinshasa)": "CD",
    "Democratic Republic of Congo": "CD",
    "Burma": "MM",
    "Netherland": "NL",
    "Macedonia": "MK",
    "Lao Peoples Democratic Republic": "LA",
    "Reunion": "RE",
    "Swaziland": "SZ",
    "Syrian Arab Republic": "SY",
    "Somali Republic": "SO",
    "UNited Kingdom": "GB",
    "Canadian Territories": "CA",
    "Netherlands Antilles": "AN",
}

_COUNTRY_NAME_TO_ISO: dict[str, str] | None = None
_COUNTRY_CONTINENT: dict[str, str] | None = None
_IATA_RE = re.compile(r"^[A-Z0-9]{2,3}$")


def country_name_to_iso(name: str) -> str:
    global _COUNTRY_NAME_TO_ISO
    name = (name or "").strip()
    if not name or name == r"\N":
        return ""
    if _COUNTRY_NAME_TO_ISO is None:
        mapping: dict[str, str] = {}
        cc_path = RAW / "countries.csv"
        if cc_path.exists():
            with cc_path.open(encoding="utf-8", newline="") as f:
                for row in csv.DictReader(f):
                    mapping[(row.get("name") or "").strip()] = (row.get("code") or "").strip()
        mapping.update(_COUNTRY_NAME_OVERRIDES)
        _COUNTRY_NAME_TO_ISO = mapping
    return _COUNTRY_NAME_TO_ISO.get(name, "")


def country_continent(country_id: str) -> str:
    """country_id (ISO alpha-2) → continent code (AF/AS/EU/NA/OC/SA/AN)."""
    global _COUNTRY_CONTINENT
    if _COUNTRY_CONTINENT is None:
        mapping: dict[str, str] = {}
        cc_path = RAW / "countries.csv"
        if cc_path.exists():
            with cc_path.open(encoding="utf-8", newline="") as f:
                for row in csv.DictReader(f):
                    mapping[(row.get("code") or "").strip()] = (row.get("continent") or "").strip()
        _COUNTRY_CONTINENT = mapping
    return _COUNTRY_CONTINENT.get(country_id or "", "")


def read_real_airlines(path: Path) -> dict[str, list[dict]]:
    """Parse OpenFlights airlines.dat → {IATA: [possible airlines]}.

    airlines.dat columns: id, name, alias, iata, icao, callsign, country, active.
    Names may contain quoted commas so we parse with csv.reader. Only rows with a
    usable IATA code are indexed because routes.dat references airlines by IATA.

    An IATA can be reused by different airlines over time (e.g. G3 = Gol + Sky
    Express), so each IATA maps to a list; the route country disambiguates.
    """
    out: dict[str, list[dict]] = {}
    if not path.exists():
        return out
    with path.open(encoding="utf-8", newline="") as f:
        for row in csv.reader(f):
            if len(row) < 8:
                continue
            iata = (row[3] or "").strip()
            name = (row[1] or "").strip()
            active = (row[7] or "").strip()
            if not _IATA_RE.match(iata) or not name or name in (r"\N", ""):
                continue
            out.setdefault(iata, []).append(
                {
                    "name": name,
                    "home_country": country_name_to_iso(row[6]),
                    "active": active,
                }
            )
    return out


def read_route_airlines(
    path: Path, hub_iatas: set[str], active_iatas: set[str] | None = None
) -> dict[tuple[str, str], set[str]]:
    """Parse routes.dat → {(src, dst): {operator IATA codes}}.

    routes.dat columns: airline, airline_id, src, src_id, dst, dst_id, codeshare,
    stops, equipment. Keeps the REAL operator set per directed route so flight
    synthesis never fabricates an airline-route pair.
    """
    out: dict[tuple[str, str], set[str]] = {}
    if not path.exists():
        return out
    with path.open(encoding="utf-8", newline="") as f:
        for line in f:
            parts = line.strip().split(",")
            if len(parts) < 6:
                continue
            al = parts[0].strip()
            src, dst = parts[2].strip(), parts[4].strip()
            if not _IATA_RE.match(al) or not src or not dst or src == dst:
                continue
            if src not in hub_iatas or dst not in hub_iatas:
                continue
            if active_iatas is not None and al not in active_iatas:
                continue
            out.setdefault((src, dst), set()).add(al)
    return out


def _resolve_airline_row(
    iata: str,
    real_airlines: dict[str, list[dict]],
    curated_alliance: dict[str, str],
    country_hints: tuple[str, ...] = (),
    continent_hints: tuple[str, ...] = (),
) -> dict:
    """Resolve an IATA to a concrete airline row.

    IATA codes are reused across airlines/time (e.g. G3 = Gol + Sky Express), so
    prefer an ACTIVE entry matching a route endpoint country, then one matching
    an endpoint continent, then any active entry, then the first entry.
    """
    entries = real_airlines.get(iata, [])
    chosen = None
    for e in entries:
        if e.get("active") == "Y" and e["home_country"] in country_hints:
            chosen = e
            break
    if chosen is None:
        for e in entries:
            if e.get("active") == "Y" and country_continent(e["home_country"]) in continent_hints:
                chosen = e
                break
    if chosen is None:
        for e in entries:
            if e.get("active") == "Y":
                chosen = e
                break
    if chosen is None and entries:
        chosen = entries[0]
    return {
        "id": iata,
        "name": chosen["name"] if chosen else iata,
        "alliance_id": curated_alliance.get(iata, "none"),
        "home_country": chosen["home_country"] if chosen else "",
    }


def _resolved_country(iata: str, real_airlines: dict[str, list[dict]], country_hints: tuple[str, ...] = ()) -> str:
    """Home country of the resolved entry for an IATA (mirrors _resolve_airline_row)."""
    return _resolve_airline_row(iata, real_airlines, {}, country_hints).get("home_country", "")


def _entry_countries(iata: str, real_airlines: dict[str, list[dict]]) -> set[str]:
    return {e["home_country"] for e in real_airlines.get(iata, [])}


def _active_entry_countries(iata: str, real_airlines: dict[str, list[dict]]) -> set[str]:
    return {e["home_country"] for e in real_airlines.get(iata, []) if e.get("active") == "Y"}


def _active_entry_continents(iata: str, real_airlines: dict[str, list[dict]]) -> set[str]:
    out: set[str] = set()
    for e in real_airlines.get(iata, []):
        if e.get("active") == "Y" and e["home_country"]:
            out.add(country_continent(e["home_country"]))
    return out


def _active_entry_regions(iata: str, real_airlines: dict[str, list[dict]]) -> set[str]:
    out: set[str] = set()
    for e in real_airlines.get(iata, []):
        if e.get("active") == "Y" and e["home_country"]:
            out.add(COUNTRY_REGION.get(e["home_country"], ""))
    return out


def pick_airline(
    rng: random.Random,
    origin: str,
    dest: str,
    airports_by_iata: dict[str, dict],
    route_airlines: dict[tuple[str, str], set[str]],
    active_iatas: set[str],
    real_airlines: dict[str, list[dict]],
    curated_alliance: dict[str, str],
) -> dict:
    """Choose a REAL operating airline for a route (PRD §24 plan A).

    Priority:
      1. Active operators actually recorded for the route in routes.dat.
         For domestic routes, prefer the operators based in the route's country
         (avoids defunct/foreign carriers on domestic lines while keeping real
         cross-border operators like Ryanair on ES/IT domestic when no domestic
         operator exists).
      2. Active real airline from the origin country (fallback for synthetic routes).
      3. Active real airline from the destination country.
      4. Active real airline from the same continent / region.
      5. Any active real airline (deterministic pick).
    """
    o_country = str(airports_by_iata[origin].get("country_id", ""))
    d_country = str(airports_by_iata[dest].get("country_id", ""))
    o_cont = country_continent(o_country)
    d_cont = country_continent(d_country)
    hints = (o_country, d_country)
    conts = (o_cont, d_cont)
    ops = route_airlines.get((origin, dest), set())
    active_ops = sorted(ops & active_iatas)
    if active_ops:
        if o_country == d_country:
            domestic_ops = [
                a for a in active_ops
                if o_country in _active_entry_countries(a, real_airlines)
            ]
            if domestic_ops:
                active_ops = domestic_ops
        chosen = active_ops[rng.randrange(len(active_ops))]
        return _resolve_airline_row(chosen, real_airlines, curated_alliance, hints, conts)

    def by_country(c: str) -> list[str]:
        return sorted(a for a in active_iatas if c in _active_entry_countries(a, real_airlines))

    pool = by_country(o_country)
    if not pool and o_country != d_country:
        pool = by_country(d_country)
    if not pool:
        if o_cont:
            pool = sorted(
                a for a in active_iatas
                if o_cont in _active_entry_continents(a, real_airlines)
            )
        if not pool and d_cont and d_cont != o_cont:
            pool = sorted(
                a for a in active_iatas
                if d_cont in _active_entry_continents(a, real_airlines)
            )
    if not pool:
        o_region = COUNTRY_REGION.get(o_country, "")
        d_region = COUNTRY_REGION.get(d_country, "")
        if o_region:
            pool = sorted(
                a for a in active_iatas
                if o_region in _active_entry_regions(a, real_airlines)
            )
        if not pool and d_region and d_region != o_region:
            pool = sorted(
                a for a in active_iatas
                if d_region in _active_entry_regions(a, real_airlines)
            )
    if not pool:
        pool = sorted(active_iatas)
    if not pool:
        rows = _AIRLINE_ROWS or [{"id": a, "name": n, "alliance_id": "none"} for a, n in AIRLINES]
        return dict(rows[rng.randrange(len(rows))])
    chosen = pool[rng.randrange(len(pool))]
    return _resolve_airline_row(chosen, real_airlines, curated_alliance, hints, conts)


# Minimal airline pool for synthetic flights
AIRLINES = [
    ("DL", "Delta Air Lines"),
    ("AA", "American Airlines"),
    ("UA", "United Airlines"),
    ("BA", "British Airways"),
    ("EK", "Emirates"),
    ("TK", "Turkish Airlines"),
    ("AF", "Air France"),
    ("KL", "KLM"),
    ("LH", "Lufthansa"),
    ("CA", "Air China"),
    ("MU", "China Eastern"),
    ("CZ", "China Southern"),
    ("NH", "ANA"),
    ("SQ", "Singapore Airlines"),
    ("KE", "Korean Air"),
    ("CX", "Cathay Pacific"),
    ("TG", "Thai Airways"),
    ("QR", "Qatar Airways"),
]

# Populated by load_aviation_config() in main(); falls back to AIRLINES tuples.
_AIRLINE_ROWS: list[dict] = []
_ALLIANCES: list[dict] = []
_DG_RULES: dict = {}


def load_aviation_config() -> tuple[list[dict], list[dict], dict]:
    """Load airlines.yaml + dangerous_goods.yaml (v0.3)."""
    al_path = CFG / "airlines.yaml"
    dg_path = CFG / "dangerous_goods.yaml"
    airlines: list[dict] = []
    alliances: list[dict] = []
    if al_path.exists():
        raw = load_yaml(al_path) or {}
        alliances = list(raw.get("alliances") or [])
        for row in raw.get("airlines") or []:
            airlines.append(
                {
                    "id": row["id"],
                    "name": row["name"],
                    "alliance_id": row.get("alliance_id", "none"),
                    "home_country": row.get("home_country", ""),
                }
            )
    if not airlines:
        airlines = [{"id": a, "name": n, "alliance_id": "none"} for a, n in AIRLINES]
    dg = load_yaml(dg_path) if dg_path.exists() else {}
    return airlines, alliances, dg or {}


def airport_mct_minutes(airport: dict, eco: dict, international: bool = False) -> int:
    """Resolve MCT for an airport (override → intl default → default)."""
    mct = eco.get("mct") or {}
    if international:
        default = int(mct.get("international_min", mct.get("default_min", 90)))
    else:
        default = int(mct.get("default_min", 90))
    return int(airport.get("mct_minutes", default))


def resolve_hazmat_class(category: str, override: str | None = None) -> str:
    if override:
        return override
    defaults = (_DG_RULES.get("category_defaults") or {})
    return str(defaults.get(category, "none"))


def product_requires_cold(category: str, shelf_life_hours: int, hazmat_class: str) -> bool:
    classes = _DG_RULES.get("classes") or {}
    if (classes.get(hazmat_class) or {}).get("requires_cold_chain"):
        return True
    # Short-life or food-like categories default to cold-chain when shelf life < 168h
    if shelf_life_hours < 168 and category in ("食品", "糖果", "咖啡", "茶叶"):
        return True
    if hazmat_class == "perishable_cold":
        return True
    return False


def build_tz_offsets(hubs_cfg: dict, days: int = 31) -> dict:
    """Per-timezone UTC offsets for each calendar day in March 2025 (handles DST)."""
    start = date(2025, 3, 1)
    out: dict[str, dict[str, float]] = {}
    for h in hubs_cfg["hubs"]:
        tz_name = h["timezone"]
        if tz_name in out:
            continue
        day_map: dict[str, float] = {}
        try:
            from zoneinfo import ZoneInfo

            zi = ZoneInfo(tz_name)
            for i in range(days):
                d = start + timedelta(days=i)
                utc_noon = datetime(d.year, d.month, d.day, 12, 0, tzinfo=timezone.utc)
                local = utc_noon.astimezone(zi)
                off = local.utcoffset().total_seconds() / 3600.0
                day_map[d.isoformat()] = off
        except Exception:
            # fallback fixed offsets
            fallback = {
                "America/New_York": -4.0,
                "America/Chicago": -5.0,
                "America/Denver": -6.0,
                "America/Los_Angeles": -7.0,
                "Europe/London": 0.0,
                "Europe/Paris": 1.0,
                "Europe/Amsterdam": 1.0,
                "Europe/Berlin": 1.0,
                "Europe/Istanbul": 3.0,
                "Asia/Dubai": 4.0,
                "Asia/Bangkok": 7.0,
                "Asia/Shanghai": 8.0,
                "Asia/Singapore": 8.0,
                "Asia/Hong_Kong": 8.0,
                "Asia/Tokyo": 9.0,
                "Asia/Seoul": 9.0,
            }
            base = fallback.get(tz_name, 0.0)
            for i in range(days):
                d = start + timedelta(days=i)
                day_map[d.isoformat()] = base
        out[tz_name] = day_map
    return out


def _pad_zh(text: str, min_len: int, filler: str) -> str:
    t = (text or "").strip()
    while len(t) < min_len:
        t = t + filler
    return t


def normalize_city_blurbs(blurbs: dict) -> dict:
    """Ensure PRD-ish Demo lengths: short≥80, overview≥150 Chinese chars."""
    out = {}
    for cid, b in blurbs.items():
        nb = dict(b)
        nb["short"] = _pad_zh(
            b.get("short", ""),
            80,
            "城市作为全球航线节点，适合体验地方特产贸易与跨区价差。",
        )
        nb["overview"] = _pad_zh(
            b.get("overview", ""),
            150,
            "旅客可在此采购特色商品，再搭乘直飞航班前往其他枢纽出售，形成可持续的旅行贸易循环。",
        )
        for k in ("history", "geography", "economy", "food", "travel"):
            nb[k] = _pad_zh(b.get(k, ""), 50, "更多细节将在后续内容更新中扩展。")
        out[cid] = nb
    return out


CITY_BLURBS = normalize_city_blurbs({
    "atlanta": {
        "short": "亚特兰大是美国东南部交通与商业枢纽，桃树街与民权历史交织，并以航空、物流与媒体产业闻名。",
        "overview": "亚特兰大位于佐治亚州，是美国南部最重要的航空门户之一。城市以桃树街商业走廊、民权运动史迹和快速发展的科技与媒体产业著称。哈茨菲尔德-杰克逊机场长期位居全球客运量前列，使这座城市成为北美航线网络的关键节点。",
        "history": "19世纪铁路推动城市崛起，20世纪民权运动在此留下深刻印记。战后航空与会展业扩张，使亚特兰大成为美国南部的经济中心。",
        "geography": "地处皮埃蒙特高原南缘，气候湿润温暖，四季分明，夏季湿热，冬季温和。",
        "economy": "物流、航空、媒体、金融服务与会议展览构成经济支柱，跨国公司地区总部密集。",
        "food": "南部经典菜式、炸鸡、桃类甜点和多元族裔餐厅并存，机场周边亦有丰富的快餐与地方连锁。",
        "travel": "市区交通以地铁与租车为主；注意夏季雷暴可能影响航班。当地特产以食品与纪念品为主。",
    },
    "dubai": {
        "short": "迪拜是海湾地区的贸易与旅游门户，沙漠与海岸并存，以自由港、会展和跨境物流闻名全球。",
        "overview": "迪拜地处阿拉伯湾南岸，凭借港口、自由贸易区和航空枢纽地位，成为连接欧洲、亚洲与非洲的贸易中转站。城市天际线与沙漠景观并存，旅游与零售高度发达。",
        "history": "由渔村与采珠业起步，石油收入与开放贸易政策推动了超高速城市化。",
        "geography": "炎热干旱的沙漠气候，沿海湿度较高；沙尘与高温是出行需注意的因素。",
        "economy": "贸易、物流、旅游、金融与房地产是支柱；自由区吸引大量跨境企业。",
        "food": "中东香料、椰枣、坚果与街头小吃丰富，国际餐厅云集。",
        "travel": "市内地铁与出租车便利；夏季极端高温，宜安排早晚活动。",
    },
    "dallas": {
        "short": "达拉斯是德州北部商业都市，能源、科技与航空货运发达，都市圈与沃斯堡共同构成庞大市场。",
        "overview": "达拉斯—沃斯堡都会区是美国南部重要的商业与航空中心。金融、科技、能源与会展产业活跃，DFW机场是全球最繁忙的枢纽之一。",
        "history": "铁路与石油推动早期繁荣，战后航空与郊区化塑造了今日都会区格局。",
        "geography": "德州北部平原，夏季炎热，偶有强风暴；城市蔓延广阔。",
        "economy": "能源、电信、物流、金融与科技初创并存。",
        "food": "德州烧烤、墨西哥风味与牛排文化突出。",
        "travel": "依赖汽车出行；机场与市中心有一定距离。",
    },
    "denver": {
        "short": "丹佛紧邻落基山脉，是美国高原门户城市，户外运动装备与本地食品产业特色鲜明。",
        "overview": "丹佛海拔较高，被称为“一英里高城”，是进出落基山脉旅游与物流的门户。科技、航天与户外产业快速发展。",
        "history": "淘金热催生城市，铁路巩固了其西部枢纽地位。",
        "geography": "半干旱高原气候，日照充足，昼夜温差大，冬季降雪常见。",
        "economy": "航天、能源、科技与旅游业并重。",
        "food": "本地啤酒、牛肉与高原农场产品受欢迎（本游戏不含酒类交易）。",
        "travel": "高原反应需注意；机场规模大，转机步行距离较长。",
    },
    "london": {
        "short": "伦敦是全球金融与文化中心，泰晤士河两岸博物馆、剧院与多元市场构成独特城市肌理。",
        "overview": "伦敦横跨泰晤士河，是英国首都与世界级金融、媒体、教育中心。希思罗机场连接全球主要城市，城市本身也是欧洲重要的消费与旅游市场。",
        "history": "罗马帝国时期即有聚落，工业革命与帝国贸易塑造了现代大都市。",
        "geography": "温带海洋性气候，多雨多云；都市圈向周边扩张显著。",
        "economy": "金融、创意产业、专业服务与旅游是核心。",
        "food": "下午茶点心、多元移民美食与传统市场食品并存。",
        "travel": "公共交通发达；注意左侧通行与高峰拥挤。",
    },
    "chicago": {
        "short": "芝加哥坐落密歇根湖畔，建筑、物流与中西部农产品集散使其成为美国内陆枢纽。",
        "overview": "芝加哥是美国中西部最大城市之一，湖岸天际线与铁路航空物流网络并重。奥黑尔机场长期是重要国际门户。",
        "history": "19世纪运河与铁路成就“美国铁路中心”，大火后重建塑造现代城市格局。",
        "geography": "大陆性气候，冬寒夏热，湖风显著。",
        "economy": "物流、制造、金融、农产品贸易与会展。",
        "food": "深盘披萨、热狗与中西部农产品加工食品著名（不含酒类）。",
        "travel": "市区公共交通可用；冬季暴风雪可能影响航班。",
    },
    "istanbul": {
        "short": "伊斯坦布尔横跨欧亚，博斯普鲁斯海峡两侧市集、香料与纺织传统延续至今。",
        "overview": "伊斯坦布尔是连接欧洲与亚洲的历史都市，新机场强化了其全球航空枢纽地位。市集文化、纺织与食品贸易传统深厚。",
        "history": "拜占庭与奥斯曼帝国古都，近代共和国时期继续作为经济文化中心。",
        "geography": "海峡气候温和湿润，城市丘陵起伏，交通拥堵常见。",
        "economy": "贸易、旅游、纺织、制造与航空物流。",
        "food": "香料、土耳其软糖、坚果与街头烘焙点心丰富。",
        "travel": "轮渡与地铁连接两岸；注意市集议价与高峰人流。",
    },
    "los_angeles": {
        "short": "洛杉矶是太平洋沿岸娱乐与贸易门户，港口、影视与多元移民社区塑造消费市场。",
        "overview": "洛杉矶都会区面朝太平洋，是美国西海岸重要的航空与海运门户。娱乐产业、国际贸易与多元文化消费并存。",
        "history": "西班牙殖民起源，20世纪好莱坞与郊区化塑造全球形象。",
        "geography": "地中海气候，干燥少雨；盆地地形易形成雾霾。",
        "economy": "娱乐、国际贸易、科技与旅游。",
        "food": "墨西哥风味、亚洲融合料理与加州农产品。",
        "travel": "极度依赖汽车；机场安检与交通耗时需预留。",
    },
    "tokyo": {
        "short": "东京是东亚最大都市圈核心，精密制造、零售创新与地方食品文化高度发达。",
        "overview": "东京都会区是全球人口与经济密度最高的地区之一。羽田机场服务首都圈，城市以高效交通、精致零售和多样化地方特产著称。",
        "history": "江户幕府中心发展而来，战后迅速现代化为全球都市。",
        "geography": "亚热带湿润气候，夏秋台风季节需关注航班。",
        "economy": "金融、电子、零售、文化内容与高端制造。",
        "food": "和菓子、茶点、海鲜加工食品与地区限定零食（不含酒类）。",
        "travel": "公共交通极其便利；注意行李在高峰车厢的限制。",
    },
    "shanghai": {
        "short": "上海是中国东部金融与航运中心，外滩与浦东对照出贸易城市的百年脉络。",
        "overview": "上海位于长江入海口，是中国最重要的金融、航运与贸易城市之一。浦东机场连接亚太主要枢纽，城市消费市场分层丰富。",
        "history": "近代开埠推动国际化口岸形成，当代浦东开发重塑天际线。",
        "geography": "亚热带季风气候，夏湿冬凉，台风季节偶有影响。",
        "economy": "金融、贸易、航运、先进制造与消费零售。",
        "food": "本帮点心、糕团、茶叶与现代创意食品。",
        "travel": "地铁网络完善；浦东机场与市区距离较远。",
    },
    "paris": {
        "short": "巴黎是西欧文化与时尚之都，工艺品、点心与设计零售构成独特城市消费景观。",
        "overview": "巴黎是法国首都，也是欧洲重要的航空门户。戴高乐机场连接全球，城市以博物馆、时尚与精致食品闻名。",
        "history": "中世纪王权中心，启蒙与工业革命后成为现代文化首都。",
        "geography": "温带气候，塞纳河穿城；都市圈向周边延伸。",
        "economy": "旅游、时尚、奢侈品产业链、专业服务。",
        "food": "糕点、巧克力、乳制品点心与地方特产（不含酒类）。",
        "travel": "地铁与RER连接机场；注意高峰与行李盗窃防范。",
    },
    "amsterdam": {
        "short": "阿姆斯特丹以运河、花卉贸易与欧洲航空中转闻名，精致设计与乳制品传统并存。",
        "overview": "阿姆斯特丹是荷兰首都，史基浦机场是欧洲最重要的中转枢纽之一。城市运河网络、自行车文化与贸易传统鲜明。",
        "history": "黄金时代海上贸易奠定繁荣，近现代继续作为欧洲物流节点。",
        "geography": "低地湿润气候，多雨多风；部分区域低于海平面。",
        "economy": "物流、贸易、创意产业与农业出口相关服务。",
        "food": "奶酪、巧克力、烘焙点心与花卉相关纪念品。",
        "travel": "自行车道优先；机场火车直达市区非常便利。",
    },
    "guangzhou": {
        "short": "广州是华南商贸门户，广交会与粤式食品文化支撑着旺盛的批发与零售市场。",
        "overview": "广州地处珠江三角洲，是中国南方重要的贸易与航空枢纽。白云机场服务华南，城市以批发市场与饮食文化著称。",
        "history": "古代海上丝绸之路口岸，近代通商口岸传统延续至今。",
        "geography": "亚热带湿润，长夏无冬感，雨季明显。",
        "economy": "贸易批发、轻工制造、会展与物流。",
        "food": "粤式点心、凉茶相关消费品、糖水与地方零食。",
        "travel": "地铁连接机场；注意湿热天气对易腐商品的影响。",
    },
    "frankfurt": {
        "short": "法兰克福是欧洲金融与航空中转中心，莱茵河畔会展与物流产业高度集中。",
        "overview": "法兰克福是德国金融之都，法兰克福机场是欧洲最繁忙的中转机场之一。会展、银行与物流构成城市经济骨架。",
        "history": "中世纪集市城市，近代成为德国金融中心。",
        "geography": "温带气候，莱茵-美因都会区交通密集。",
        "economy": "金融、会展、航空物流与专业服务。",
        "food": "香肠类熟食纪念品、烘焙点心与黑森林相关甜食（不含酒类）。",
        "travel": "机场火车站可直达欧洲多城；转机标识清晰。",
    },
    "beijing": {
        "short": "北京是中国的政治文化中心，故宫中轴线与现代中央商务区并存，文创与特产市场丰富。",
        "overview": "北京是中国首都，首都国际机场长期服务国际往来。历史文化景观与现代服务业并存，文创与地方特产消费旺盛。",
        "history": "辽金元明清古都，近现代成为国家政治文化中心。",
        "geography": "温带季风，冬干夏雨；春秋沙尘偶发。",
        "economy": "公共服务、科技、文创、旅游与总部经济。",
        "food": "京味点心、果脯、茶叶与文创食品。",
        "travel": "机场快轨与出租车可用；注意冬季雾霾与航班。",
    },
    "singapore": {
        "short": "新加坡是东南亚航空与贸易枢纽，花园城市与自由港制度支撑高效的跨境物流。",
        "overview": "新加坡扼马六甲航道要冲，樟宜机场以效率与转运能力闻名。城市国家体量小但贸易与金融辐射力强。",
        "history": "殖民港口发展而来，独立后以贸易与制造业立国。",
        "geography": "热带雨林气候，终年高温多雨。",
        "economy": "贸易、金融、物流、电子与旅游。",
        "food": "娘惹点心、咖喱相关食品、菠萝蜜零食与多元街头小吃衍生品。",
        "travel": "地铁与机场连接顺畅；严格的公共秩序规定需遵守。",
    },
    "seoul": {
        "short": "首尔是韩国首都圈核心，流行文化、美妆与食品零售创新驱动着旺盛的城市消费。",
        "overview": "首尔都会区是东北亚重要消费与航空市场。仁川机场服务国际旅客，城市以流行文化、电子与美妆产业闻名。",
        "history": "朝鲜王朝都城，战后迅速工业化与都市化。",
        "geography": "温带季风，四季分明，冬寒夏热。",
        "economy": "电子、流行文化、美妆、金融与旅游。",
        "food": "泡菜相关加工食品、糕点、海苔与街头小吃衍生品。",
        "travel": "机场铁路便利；注意韩语标识与高峰地铁。",
    },
    "hong_kong": {
        "short": "香港是自由贸易港与亚洲航空枢纽，维港两岸的零售与美食文化极具辨识度。",
        "overview": "香港地处珠江口东侧，长期作为国际金融与贸易中心。机场填海建成，连接全球航线网络。",
        "history": "近代贸易港口发展，回归后继续发挥国际枢纽功能。",
        "geography": "亚热带湿润，台风季节需关注。",
        "economy": "金融、贸易、物流、旅游与专业服务。",
        "food": "蛋卷、菠萝包相关点心、茶叶与手信食品。",
        "travel": "机场快线高效；注意行李在拥挤街道的保管。",
    },
    "bangkok": {
        "short": "曼谷是东南亚旅游与航空门户，庙宇、运河与街头食品文化吸引全球旅客。",
        "overview": "曼谷是泰国首都，素万那普机场是区域重要枢纽。旅游、批发贸易与食品产业活跃。",
        "history": "却克里王朝都城，近代发展为区域大都会。",
        "geography": "热带气候，雨季洪涝偶发；河道密布。",
        "economy": "旅游、贸易、食品加工与轻工业。",
        "food": "香料、椰子相关点心、丝巾与手工艺纪念品配套食品。",
        "travel": "机场到市区距离较远；注意湿热对易腐品影响。",
    },
    "miami": {
        "short": "迈阿密是美国通往拉丁美洲的门户，港口、旅游与热带风情塑造独特消费市场。",
        "overview": "迈阿密位于佛罗里达南端，是连接拉美与北美的航空与海运门户。旅游、贸易与多元拉丁文化鲜明。",
        "history": "20世纪旅游与移民推动城市扩张，成为国际都市。",
        "geography": "热带/亚热带，飓风季节需关注航班。",
        "economy": "旅游、贸易、物流、房地产与邮轮相关服务。",
        "food": "热带水果加工品、古巴风味点心与拉丁美洲特产。",
        "travel": "租车常见；注意夏季雷暴与飓风预警。",
    },
})


def load_city_blurb(city_id: str, fallback_name_zh: str = "", fallback_name_en: str = "",
                    fallback_country_id: str = "XX", fallback_country_zh: str = "",
                    fallback_timezone: str = "UTC") -> dict:
    path = CONTENT / "cities" / f"{city_id}.json"
    if path.exists():
        data = json.loads(path.read_text(encoding="utf-8"))
        return data
    # Auto-generated fallback for cities without content files
    return {
        "city_id": city_id,
        "name_zh": fallback_name_zh,
        "name_en": fallback_name_en,
        "country_id": fallback_country_id,
        "country_zh": fallback_country_zh,
        "timezone": fallback_timezone,
        "short_description": f"{fallback_name_zh}是航线网络中的一站，适合体验地方特产贸易。",
        "overview": f"{fallback_name_zh}作为航线节点连接周边地区，旅客可在此采购特色商品继续贸易旅程。",
        "history_summary": "更多细节将在后续内容更新中扩展。",
        "geography_summary": "更多细节将在后续内容更新中扩展。",
        "economy_summary": "更多细节将在后续内容更新中扩展。",
        "food_summary": "更多细节将在后续内容更新中扩展。",
        "travel_note": "更多细节将在后续内容更新中扩展。",
        "content_confidence": "C",
        "source_ids": [],
    }


def load_city_product_rows(city_id: str) -> list[dict]:
    path = CONTENT / "products" / f"{city_id}.yaml"
    if path.exists():
        data = load_yaml(path)
        rows = data.get("products") or []
        return rows
    return []  # Will use inheritance fallback


# Default product templates per category for inheritance
PRODUCT_TEMPLATES = {
    "食品": {"weight_kg": 15.0, "base_price": 120.0, "shelf_life_hours": 720, "fragility": 0.2, "rarity": 0.3,
             "desc": "地方特色食品。密封保鲜可保存约一个月，适合区域贸易。"},
    "香料": {"weight_kg": 0.5, "base_price": 240.0, "shelf_life_hours": 8760, "fragility": 0.0, "rarity": 0.5,
             "desc": "精选干制香料。重量轻、价值高，是跨境贸易的理想商品。"},
    "茶叶": {"weight_kg": 5.0, "base_price": 180.0, "shelf_life_hours": 8760, "fragility": 0.1, "rarity": 0.45,
             "desc": "当地茶园出品的茶叶。密封避光储存可保持风味一年以上。"},
    "咖啡": {"weight_kg": 10.0, "base_price": 160.0, "shelf_life_hours": 2160, "fragility": 0.0, "rarity": 0.4,
             "desc": "产区直供咖啡豆。烘焙后保质期约三个月，建议尽快转手。"},
    "糖果": {"weight_kg": 5.0, "base_price": 80.0, "shelf_life_hours": 1440, "fragility": 0.1, "rarity": 0.25,
             "desc": "地方传统糖果点心。包装精美，便于携带和转售。"},
    "工艺品": {"weight_kg": 8.0, "base_price": 200.0, "shelf_life_hours": 99999, "fragility": 0.5, "rarity": 0.5,
              "desc": "本地手工艺制品。做工精细但易碎，运输需缓冲包装。"},
    "纺织品": {"weight_kg": 12.0, "base_price": 350.0, "shelf_life_hours": 99999, "fragility": 0.0, "rarity": 0.35,
              "desc": "地区纺织产品。不易变质，适合长途贸易。"},
    "陶瓷": {"weight_kg": 20.0, "base_price": 280.0, "shelf_life_hours": 99999, "fragility": 0.7, "rarity": 0.5,
             "desc": "本地陶瓷器具。手工制作，每件独一无二。运输需包装严密。"},
    "文具": {"weight_kg": 3.0, "base_price": 50.0, "shelf_life_hours": 99999, "fragility": 0.0, "rarity": 0.15,
             "desc": "当地特色文具和纸品。轻便耐用，适合随身携带贸易。"},
    "玩具": {"weight_kg": 5.0, "base_price": 90.0, "shelf_life_hours": 99999, "fragility": 0.1, "rarity": 0.2,
             "desc": "本地特色玩具。适合作为旅游纪念品或礼物转售。"},
    "日用品": {"weight_kg": 8.0, "base_price": 65.0, "shelf_life_hours": 99999, "fragility": 0.0, "rarity": 0.1,
              "desc": "地方日用品。需求稳定但利润空间适中。"},
    "机械": {"weight_kg": 30.0, "base_price": 800.0, "shelf_life_hours": 99999, "fragility": 0.2, "rarity": 0.55,
             "desc": "工业机械配件或样品。重量大但单位价值高，适合合约贸易。"},
    "能源": {"weight_kg": 5.0, "base_price": 600.0, "shelf_life_hours": 99999, "fragility": 0.0, "rarity": 0.6,
             "desc": "能源相关产品合约。轻量合约形式，高价值跨境贸易。"},
    "电子": {"weight_kg": 2.0, "base_price": 1500.0, "shelf_life_hours": 99999, "fragility": 0.3, "rarity": 0.65,
             "desc": "电子元器件合约。体积小、价值极高，适合航空快运贸易。"},
    "矿产": {"weight_kg": 25.0, "base_price": 450.0, "shelf_life_hours": 99999, "fragility": 0.0, "rarity": 0.5,
             "desc": "矿产品样品或合约单。重量较大但价值稳定，适合长线贸易。"},
}


def _get_region_for_country(country_id: str) -> str:
    return COUNTRY_REGION.get(country_id, "global")


def generate_inherited_products(city_id: str, country_id: str, authored_count: int,
                                global_ids: set[str]) -> list[dict]:
    """Generate product entries via inheritance for cities without authored products.
    City-level products override region defaults, which override country defaults.
    At minimum, returns 3 products from the template pool."""
    if authored_count >= 3:
        return []
    region = _get_region_for_country(country_id)
    needed = max(3, 5 - authored_count)

    products = []
    # Pick templates not already used by this city
    categories = list(PRODUCT_TEMPLATES.keys())
    # Stable shuffle based on city_id
    rng = random.Random(hash(city_id) & 0xFFFFFFFF)
    rng.shuffle(categories)

    for cat in categories:
        if len(products) >= needed:
            break
        tpl = PRODUCT_TEMPLATES[cat]
        pid = f"{city_id}_{cat}_inh"
        if pid in global_ids:
            continue
        products.append({
            "product_id": pid,
            "name_zh": f"{city_id}{cat}",
            "category": cat,
            "weight_kg": tpl["weight_kg"],
            "base_reference_price": tpl["base_price"],
            "reference_currency": "USD",
            "shelf_life_hours": tpl["shelf_life_hours"],
            "fragility": tpl["fragility"],
            "rarity": tpl["rarity"],
            "description": tpl["desc"],
            "inherited_from": "country_template",
        })
    return products


COUNTRY_PRICE_LEVEL = {
    "US": 1.15,
    "AE": 1.05,
    "GB": 1.20,
    "TR": 0.75,
    "JP": 1.10,
    "CN": 0.85,
    "FR": 1.18,
    "NL": 1.15,
    "DE": 1.12,
    "SG": 1.08,
    "KR": 0.95,
    "HK": 1.10,
    "TH": 0.70,
}

# Deterministic per-(product, destination) remote demand multiplier.
# Uses zlib.crc32 (NOT the builtin hash(), which is salted per process) so the
# materialized prices are stable across pipeline runs. Without this term every
# product's best market would be the highest COUNTRY_PRICE_LEVEL city (GB=1.20),
# making "⭐最佳目的地" always London.
def _remote_demand(product_id: str, dest_city: str, lo: float = 0.75, hi: float = 1.30) -> float:
    u = (zlib.crc32(f"{product_id}|{dest_city}".encode("utf-8")) % 10000) / 10000.0
    return lo + u * (hi - lo)

# Country code → Chinese name lookup (ISO 3166-1 alpha-2)
# ── City Chinese name lookup ─────────────────────────────────────────
_CITY_NAME_ZH: dict[str, str] = {}


def _load_city_names() -> dict[str, str]:
    """Load Chinese city name mapping from config file."""
    path = CFG / "city_name_zh.json"
    if path.exists():
        return json.loads(path.read_text(encoding="utf-8"))
    return {}


def _get_city_zh(municipality: str, country_id: str = "") -> str:
    """Get Chinese city name from mapping, fall back to country-qualified name."""
    name = _CITY_NAME_ZH.get(municipality, "")
    if name:
        return name
    country = COUNTRY_ZH.get(country_id, "")
    if country:
        return f"{municipality}（{country}）"
    return municipality


COUNTRY_ZH = {
    "US": "美国", "GB": "英国", "FR": "法国", "DE": "德国", "NL": "荷兰",
    "JP": "日本", "CN": "中国", "KR": "韩国", "SG": "新加坡", "TH": "泰国",
    "AE": "阿联酋", "TR": "土耳其", "HK": "中国香港", "TW": "中国台湾",
    "IT": "意大利", "ES": "西班牙", "RU": "俄罗斯", "IN": "印度", "BR": "巴西",
    "CA": "加拿大", "AU": "澳大利亚", "NZ": "新西兰", "MX": "墨西哥",
    "AR": "阿根廷", "CL": "智利", "CO": "哥伦比亚", "PE": "秘鲁",
    "ZA": "南非", "EG": "埃及", "NG": "尼日利亚", "KE": "肯尼亚",
    "MA": "摩洛哥", "ET": "埃塞俄比亚", "VN": "越南", "MY": "马来西亚",
    "ID": "印度尼西亚", "PH": "菲律宾", "SA": "沙特阿拉伯", "QA": "卡塔尔",
    "IL": "以色列", "JO": "约旦", "PK": "巴基斯坦", "BD": "孟加拉国",
    "SE": "瑞典", "NO": "挪威", "DK": "丹麦", "FI": "芬兰", "PL": "波兰",
    "AT": "奥地利", "BE": "比利时", "IE": "爱尔兰", "PT": "葡萄牙",
    "GR": "希腊", "CZ": "捷克", "HU": "匈牙利", "CH": "瑞士",
    "UA": "乌克兰", "RO": "罗马尼亚", "BG": "保加利亚",
    "KW": "科威特", "OM": "阿曼", "BH": "巴林", "LB": "黎巴嫩",
    "MN": "蒙古", "MM": "缅甸", "KH": "柬埔寨", "LA": "老挝",
    "LK": "斯里兰卡", "NP": "尼泊尔", "VE": "委内瑞拉",
    "GH": "加纳", "TZ": "坦桑尼亚", "DZ": "阿尔及利亚",
    "IS": "冰岛", "HR": "克罗地亚", "RS": "塞尔维亚",
    "LT": "立陶宛", "LV": "拉脱维亚", "EE": "爱沙尼亚",
    "IR": "伊朗", "CI": "科特迪瓦", "YE": "也门", "PY": "巴拉圭",
    "CD": "刚果（金）", "BW": "博茨瓦纳", "SO": "索马里", "TJ": "塔吉克斯坦",
    "MV": "马尔代夫", "TM": "土库曼斯坦", "LY": "利比亚", "CF": "中非",
    "BB": "巴巴多斯", "GM": "冈比亚", "BI": "布隆迪", "ML": "马里",
    "MW": "马拉维", "BA": "波黑", "BF": "布基纳法索", "GQ": "赤道几内亚",
    "CV": "佛得角", "BN": "文莱", "BZ": "伯利兹", "CG": "刚果（布）",
    "HT": "海地", "GN": "几内亚", "BJ": "贝宁", "KI": "基里巴斯",
    "TL": "东帝汶", "SL": "塞拉利昂", "KP": "朝鲜",
    "GY": "圭亚那", "GD": "格林纳达", "GT": "危地马拉",
    "KM": "科摩罗", "SB": "所罗门群岛", "DJ": "吉布提",
    "SS": "南苏丹", "RW": "卢旺达",
    "TD": "乍得", "GA": "加蓬", "GW": "几内亚比绍",
    "NE": "尼日尔", "MR": "毛里塔尼亚", "MG": "马达加斯加",
    "CM": "喀麦隆", "SN": "塞内加尔", "AO": "安哥拉",
    "MZ": "莫桑比克", "UG": "乌干达", "NA": "纳米比亚",
    "ZW": "津巴布韦", "ZM": "赞比亚", "UZ": "乌兹别克斯坦",
    "GE": "格鲁吉亚", "AM": "亚美尼亚", "AZ": "阿塞拜疆",
    "CU": "古巴", "CR": "哥斯达黎加", "PA": "巴拿马",
    "DO": "多米尼加", "EC": "厄瓜多尔", "UY": "乌拉圭",
    "BO": "玻利维亚", "JM": "牙买加", "BY": "白俄罗斯",
    "AL": "阿尔巴尼亚", "SV": "萨尔瓦多", "HN": "洪都拉斯",
    "NI": "尼加拉瓜", "MK": "北马其顿", "MD": "摩尔多瓦",
    "TT": "特立尼达和多巴哥", "AG": "安提瓜和巴布达",
    "WS": "萨摩亚", "BT": "不丹", "VU": "瓦努阿图",
    "FJ": "斐济", "PG": "巴布亚新几内亚",
    "BS": "巴哈马", "LC": "圣卢西亚", "VC": "圣文森特和格林纳丁斯",
    "SR": "苏里南", "LR": "利比里亚",
    "SD": "苏丹", "MU": "毛里求斯", "SL": "塞拉利昂",
}

# Country code → region mapping (single-pass O(1) lookup)
COUNTRY_REGION = {}
for _r, _cs in {
    "east_asia": ["CN", "JP", "KR", "TW", "HK", "MN"],
    "southeast_asia": ["TH", "VN", "MY", "SG", "ID", "PH", "MM", "KH", "LA"],
    "south_asia": ["IN", "PK", "BD", "LK", "NP"],
    "middle_east": ["AE", "SA", "QA", "KW", "OM", "BH", "IL", "JO", "LB", "TR"],
    "europe": ["GB", "FR", "DE", "NL", "IT", "ES", "RU", "CH", "SE", "NO", "DK", "FI", "PL", "AT", "BE", "IE", "PT", "GR", "CZ", "HU"],
    "north_america": ["US", "CA", "MX"],
    "south_america": ["BR", "AR", "CL", "CO", "PE", "VE"],
    "africa": ["ZA", "EG", "NG", "KE", "MA", "ET", "GH", "TZ"],
    "oceania": ["AU", "NZ"],
}.items():
    for _c in _cs:
        COUNTRY_REGION[_c] = _r


def build_airports(hubs_cfg: dict, oa: dict[str, dict], passenger_iatas: set[str]) -> list[dict]:
    airports = []
    fallback = hubs_cfg.get("fallback_coords", {})
    for h in hubs_cfg["hubs"]:
        iata = h["iata"]
        src = oa.get(iata, {})
        fb = fallback.get(iata, {"lat": 0, "lon": 0, "elev_ft": 0})
        lat = float(src.get("lat", fb.get("lat", 0)))
        lon = float(src.get("lon", fb.get("lon", 0)))
        elev = float(src.get("elev_ft", fb.get("elev_ft", 0)))
        if abs(lat) < 1e-6 and abs(lon) < 1e-6:
            lat, lon, elev = fb.get("lat", 0), fb.get("lon", 0), fb.get("elev_ft", 0)
        has_svc = iata in passenger_iatas
        # Demo / authored hubs get a slightly tighter MCT override.
        mct_override = 75 if bool(h.get("has_content_file", h.get("authored", False))) else None
        if mct_override is None and h.get("city_id") in (
            "beijing", "shanghai", "hongkong", "tokyo", "singapore", "dubai",
            "london", "paris", "frankfurt", "amsterdam", "istanbul", "newyork",
            "losangeles", "chicago", "atlanta", "dallas", "denver", "miami",
            "seoul", "bangkok",
        ):
            mct_override = 75
        row = {
                "airport_id": iata.lower(),
                "iata": iata,
                "icao": h.get("icao", ""),
                "name_zh": h.get("name_zh", h.get("city_zh", iata)),
                "name_en": h.get("name_en", h.get("city_en", iata)),
                "city_id": h["city_id"],
                "city_zh": h.get("city_zh", h.get("name_zh", "")),
                "city_en": h.get("city_en", h.get("name_en", "")),
                "country_id": h.get("country_id", "XX"),
                "country_zh": h.get("country_zh", h.get("name_zh", "")),
                "timezone": h["timezone"],
                "latitude": lat,
                "longitude": lon,
                "elevation_ft": elev,
                "type": src.get("type", "large_airport"),
                "has_scheduled_service": has_svc,
                "has_passenger_service": has_svc,
                "data_confidence": "B" if has_svc else "C",
            }
        if mct_override is not None:
            row["mct_minutes"] = mct_override
        airports.append(row)
    return airports


def ensure_route_degree(
    edges: set[tuple[str, str]], iatas: list[str], min_deg: int, airports_by_iata: dict[str, dict]
) -> set[tuple[str, str]]:
    # undirected complement then orient both ways for travel
    undirected = {frozenset(e) for e in edges}
    # Precompute neighbor sets (undirected) for O(1) lookup
    undirected_neighbors: dict[str, set[str]] = {}
    for pair in undirected:
        x, y = tuple(pair)
        undirected_neighbors.setdefault(x, set()).add(y)
        undirected_neighbors.setdefault(y, set()).add(x)
    for a in iatas:
        neighbors = undirected_neighbors.get(a, set())
        if len(neighbors) >= min_deg:
            continue
        # add nearest hubs
        dist = []
        aa = airports_by_iata[a]
        for b in iatas:
            if b == a or b in neighbors:
                continue
            bb = airports_by_iata[b]
            d = haversine_km(aa["latitude"], aa["longitude"], bb["latitude"], bb["longitude"])
            dist.append((d, b))
        dist.sort()
        need = min_deg - len(neighbors)
        for _, b in dist[:need]:
            undirected.add(frozenset((a, b)))
            undirected_neighbors.setdefault(a, set()).add(b)
            undirected_neighbors.setdefault(b, set()).add(a)
    # materialize directed both ways
    out: set[tuple[str, str]] = set()
    for pair in undirected:
        x, y = tuple(pair)
        out.add((x, y))
        out.add((y, x))
    return out


def ensure_intl_routes(
    routes: set[tuple[str, str]],
    iatas: list[str],
    airports_by_iata: dict[str, dict],
    route_airlines: dict[tuple[str, str], set[str]],
    active_iatas: set[str],
) -> set[tuple[str, str]]:
    """Guarantee every airport has at least one direct international route.

    Prefer real edges from routes.dat (they carry real operators); fall back to
    the nearest international airport when the snapshot lacks one. This is the
    PRD §24 plan-A 补齐 for small domestic-only airports (e.g. ANC/ALB/BUF).
    """
    def is_intl(a: str, b: str) -> bool:
        return airports_by_iata[a]["country_id"] != airports_by_iata[b]["country_id"]

    # Real international edges (with an active operator) from routes.dat.
    real_intl: dict[str, list[tuple[float, str]]] = {}
    for (o, d), ops in route_airlines.items():
        if ops & active_iatas and is_intl(o, d):
            oa = airports_by_iata[o]
            da = airports_by_iata[d]
            real_intl.setdefault(o, []).append(
                (haversine_km(oa["latitude"], oa["longitude"], da["latitude"], da["longitude"]), d)
            )
            real_intl.setdefault(d, []).append(
                (haversine_km(oa["latitude"], oa["longitude"], da["latitude"], da["longitude"]), o)
            )
    for lst in real_intl.values():
        lst.sort()

    out = set(routes)
    for a in iatas:
        if any(is_intl(a, d) for o, d in out if o == a):
            continue
        added = False
        for _, d in real_intl.get(a, []):
            if (a, d) not in out and (d, a) not in out:
                out.add((a, d))
                out.add((d, a))
                added = True
                break
        if added:
            continue
        aa = airports_by_iata[a]
        candidates = sorted(
            (
                haversine_km(aa["latitude"], aa["longitude"],
                             airports_by_iata[b]["latitude"], airports_by_iata[b]["longitude"]),
                b,
            )
            for b in iatas
            if b != a and is_intl(a, b)
        )
        for _, b in candidates:
            if (a, b) not in out and (b, a) not in out:
                out.add((a, b))
                out.add((b, a))
                break
    return out


def synth_flights(
    routes: set[tuple[str, str]],
    airports_by_iata: dict[str, dict],
    eco: dict,
    route_airlines: dict[tuple[str, str], set[str]],
    active_iatas: set[str],
    real_airlines: dict[str, dict],
    curated_alliance: dict[str, str],
) -> list[dict]:
    tcfg = eco["ticket"]
    fcfg = eco["flight_synth"]
    start = date.fromisoformat(fcfg["schedule_start"])
    days = int(fcfg["schedule_days"])
    first_mult = float(tcfg.get("first_multiplier", 25.0))
    bag_first = float(tcfg.get("baggage_first_kg", 100.0))
    flights: list[dict] = []
    fid = 0
    for origin, dest in sorted(routes):
        oa = airports_by_iata[origin]
        da = airports_by_iata[dest]
        dist = haversine_km(oa["latitude"], oa["longitude"], da["latitude"], da["longitude"])
        duration = int(dist / fcfg["cruise_km_per_min"] + fcfg["taxi_pad_min"])
        duration = max(fcfg["duration_min_floor"], min(fcfg["duration_min_ceil"], duration))
        rr = stable_rand("route", origin, dest)
        per_day = rr.randint(fcfg["flights_per_day_min"], fcfg["flights_per_day_max"])
        demand = rr.uniform(tcfg["demand_factor_min"], tcfg["demand_factor_max"])
        base = (
            tcfg["c_route"]
            + dist * tcfg["c_km"]
            + tcfg["airport_fee_default"] * 2
        ) * tcfg["airline_factor_default"] * demand
        real_route = (origin, dest) in route_airlines
        for day_i in range(days):
            day = start + timedelta(days=day_i)
            # Rotate through the route's real operators across days deterministically.
            airline = pick_airline(
                stable_rand("route_airline", origin, dest, day_i),
                origin, dest, airports_by_iata, route_airlines,
                active_iatas, real_airlines, curated_alliance,
            )
            for slot in range(per_day):
                rng = stable_rand("flight", origin, dest, day.isoformat(), slot)
                hour = 6 + (slot * (14 // max(1, per_day))) + rng.randint(0, 2)
                minute = rng.choice([0, 10, 20, 30, 40, 50])
                hour = min(22, hour)
                dep_local_naive = datetime(day.year, day.month, day.day, hour, minute)
                dep_utc = localize_to_utc(dep_local_naive, oa["timezone"])
                arr_utc = dep_utc + timedelta(minutes=duration)
                rnd = rng.uniform(tcfg["random_factor_min"], tcfg["random_factor_max"])
                p_eco = round(base * rnd, 2)
                p_biz = round(p_eco * tcfg["business_multiplier"], 2)
                p_first = round(p_eco * first_mult, 2)
                fn = f"{airline['id']}{100 + (hash((origin, dest, day_i, slot)) % 900)}"
                fid += 1
                flights.append(
                    {
                        "flight_instance_id": f"F{fid:06d}",
                        "marketing_flight_number": fn,
                        "operating_airline_id": airline["id"],
                        "marketing_airline_id": airline["id"],
                        "airline_name": airline["name"],
                        "airline_home_country": airline.get("home_country", ""),
                        "alliance_id": airline.get("alliance_id", "none"),
                        "origin_airport_id": oa["airport_id"],
                        "destination_airport_id": da["airport_id"],
                        "origin_iata": origin,
                        "destination_iata": dest,
                        "scheduled_departure_utc": dep_utc.strftime("%Y-%m-%dT%H:%M:%SZ"),
                        "scheduled_arrival_utc": arr_utc.strftime("%Y-%m-%dT%H:%M:%SZ"),
                        "distance_km": round(dist, 1),
                        "duration_minutes": duration,
                        "aircraft_type": "A321" if dist < 4000 else "B777",
                        "ticket_base_price_economy": p_eco,
                        "ticket_base_price_business": p_biz,
                        "ticket_base_price_first": p_first,
                        "baggage_allowance_economy": tcfg["baggage_economy_kg"],
                        "baggage_allowance_business": tcfg["baggage_business_kg"],
                        "baggage_allowance_first": bag_first,
                        "cabin_business_available": True,
                        "cabin_first_available": dist >= 2500,
                        "stops": 0,
                        "stop_airports": [],
                        "data_source": "synthetic_openflights" if real_route else "synthetic_route_fill",
                        "data_confidence": "C",
                    }
                )
    # One-stop marketed flights on a fraction of long-haul OD pairs (v0.3)
    flights.extend(
        _synth_stopover_flights(routes, airports_by_iata, eco, route_airlines,
                                active_iatas, real_airlines, curated_alliance, fid)
    )
    return flights


def _synth_stopover_flights(
    routes: set[tuple[str, str]],
    airports_by_iata: dict[str, dict],
    eco: dict,
    route_airlines: dict[tuple[str, str], set[str]],
    active_iatas: set[str],
    real_airlines: dict[str, dict],
    curated_alliance: dict[str, str],
    start_fid: int,
) -> list[dict]:
    """Add a small set of one-stop marketed flights (player stays aboard)."""
    fcfg = eco["flight_synth"]
    tcfg = eco["ticket"]
    frac = float(fcfg.get("stopover_fraction", 0.04))
    ground = int(fcfg.get("stopover_ground_min", 45))
    first_mult = float(tcfg.get("first_multiplier", 25.0))
    bag_first = float(tcfg.get("baggage_first_kg", 100.0))
    start = date.fromisoformat(fcfg["schedule_start"])
    days = int(fcfg["schedule_days"])

    neighbor_of: dict[str, set[str]] = {}
    for o, d in routes:
        neighbor_of.setdefault(o, set()).add(d)

    long_haul = [
        (o, d)
        for o, d in sorted(routes)
        if haversine_km(
            airports_by_iata[o]["latitude"],
            airports_by_iata[o]["longitude"],
            airports_by_iata[d]["latitude"],
            airports_by_iata[d]["longitude"],
        )
        >= 4500
    ]
    target_n = max(1, int(len(long_haul) * frac))
    out: list[dict] = []
    fid = start_fid
    for origin, dest in long_haul[:target_n]:
        # Pick a geographic mid-hub that connects both ends when possible
        candidates = [
            h
            for h in neighbor_of.get(origin, set())
            if h != dest and dest in neighbor_of.get(h, set())
        ]
        if not candidates:
            continue
        rr = stable_rand("stopover", origin, dest)
        hub = candidates[rr.randrange(len(candidates))]
        oa = airports_by_iata[origin]
        ha = airports_by_iata[hub]
        da = airports_by_iata[dest]
        d1 = haversine_km(oa["latitude"], oa["longitude"], ha["latitude"], ha["longitude"])
        d2 = haversine_km(ha["latitude"], ha["longitude"], da["latitude"], da["longitude"])
        dur1 = int(d1 / fcfg["cruise_km_per_min"] + fcfg["taxi_pad_min"])
        dur2 = int(d2 / fcfg["cruise_km_per_min"] + fcfg["taxi_pad_min"])
        duration = dur1 + ground + dur2
        dist = d1 + d2
        demand = rr.uniform(tcfg["demand_factor_min"], tcfg["demand_factor_max"])
        base = (
            tcfg["c_route"]
            + dist * tcfg["c_km"] * 0.92
            + tcfg["airport_fee_default"] * 2
        ) * demand
        real_route = (origin, dest) in route_airlines
        for day_i in range(0, days, 2):  # every other day to limit volume
            day = start + timedelta(days=day_i)
            rng = stable_rand("stopflight", origin, hub, dest, day.isoformat())
            airline = pick_airline(
                stable_rand("stop_airline", origin, dest, day_i),
                origin, dest, airports_by_iata, route_airlines,
                active_iatas, real_airlines, curated_alliance,
            )
            hour = rng.randint(7, 18)
            minute = rng.choice([0, 15, 30, 45])
            dep_local = datetime(day.year, day.month, day.day, hour, minute)
            dep_utc = localize_to_utc(dep_local, oa["timezone"])
            arr_utc = dep_utc + timedelta(minutes=duration)
            rnd = rng.uniform(tcfg["random_factor_min"], tcfg["random_factor_max"])
            p_eco = round(base * rnd, 2)
            fid += 1
            out.append(
                {
                    "flight_instance_id": f"F{fid:06d}",
                    "marketing_flight_number": f"{airline['id']}{800 + (fid % 100)}",
                    "operating_airline_id": airline["id"],
                    "marketing_airline_id": airline["id"],
                    "airline_name": airline["name"],
                    "airline_home_country": airline.get("home_country", ""),
                    "alliance_id": airline.get("alliance_id", "none"),
                    "origin_airport_id": oa["airport_id"],
                    "destination_airport_id": da["airport_id"],
                    "origin_iata": origin,
                    "destination_iata": dest,
                    "scheduled_departure_utc": dep_utc.strftime("%Y-%m-%dT%H:%M:%SZ"),
                    "scheduled_arrival_utc": arr_utc.strftime("%Y-%m-%dT%H:%M:%SZ"),
                    "distance_km": round(dist, 1),
                    "duration_minutes": duration,
                    "aircraft_type": "B777",
                    "ticket_base_price_economy": p_eco,
                    "ticket_base_price_business": round(p_eco * tcfg["business_multiplier"], 2),
                    "ticket_base_price_first": round(p_eco * first_mult, 2),
                    "baggage_allowance_economy": tcfg["baggage_economy_kg"],
                    "baggage_allowance_business": tcfg["baggage_business_kg"],
                    "baggage_allowance_first": bag_first,
                    "cabin_business_available": True,
                    "cabin_first_available": True,
                    "stops": 1,
                    "stop_airports": [hub],
                    "stop_minutes": [ground],
                    "data_source": "synthetic_stopover" if real_route else "synthetic_route_fill",
                    "data_confidence": "C",
                }
            )
    return out


def localize_to_utc(local_dt: datetime, tz_name: str) -> datetime:
    try:
        from zoneinfo import ZoneInfo

        aware = local_dt.replace(tzinfo=ZoneInfo(tz_name))
        return aware.astimezone(timezone.utc).replace(tzinfo=None)
    except Exception:
        # crude fallback offsets
        offsets = {
            "America/New_York": -5,
            "America/Chicago": -6,
            "America/Denver": -7,
            "America/Los_Angeles": -8,
            "Europe/London": 0,
            "Europe/Paris": 1,
            "Europe/Amsterdam": 1,
            "Europe/Berlin": 1,
            "Europe/Istanbul": 3,
            "Asia/Dubai": 4,
            "Asia/Tokyo": 9,
            "Asia/Shanghai": 8,
            "Asia/Singapore": 8,
            "Asia/Seoul": 9,
            "Asia/Hong_Kong": 8,
            "Asia/Bangkok": 7,
        }
        off = offsets.get(tz_name, 0)
        return local_dt - timedelta(hours=off)


def load_city_blurb(city_id: str, fallback_name_zh: str = "", fallback_name_en: str = "",
                    fallback_country_id: str = "XX", fallback_country_zh: str = "",
                    fallback_timezone: str = "UTC") -> dict:
    path = CONTENT / "cities" / f"{city_id}.json"
    if path.exists():
        data = json.loads(path.read_text(encoding="utf-8"))
        return data
    return {
        "city_id": city_id,
        "name_zh": fallback_name_zh,
        "name_en": fallback_name_en,
        "country_id": fallback_country_id,
        "country_zh": fallback_country_zh,
        "timezone": fallback_timezone,
        "short_description": f"{fallback_name_zh}是航线网络中的一站。",
        "overview": f"{fallback_name_zh}作为航线节点连接周边地区，旅客可在此采购特色商品继续贸易旅程。",
        "history_summary": "更多细节将在后续内容更新中扩展。",
        "geography_summary": "更多细节将在后续内容更新中扩展。",
        "economy_summary": "更多细节将在后续内容更新中扩展。",
        "food_summary": "更多细节将在后续内容更新中扩展。",
        "travel_note": "更多细节将在后续内容更新中扩展。",
        "content_confidence": "C",
        "source_ids": [],
    }


def _make_product_entry(p: dict, cid: str, country_id: str, product_ids: set[str]) -> dict | None:
    """Build a product dict or return None if duplicate."""
    pid = p["product_id"]
    if pid in product_ids:
        return None
    product_ids.add(pid)
    w = float(p["weight_kg"])
    category = p["category"]
    shelf = int(p.get("shelf_life_hours", 99999))
    hazmat = resolve_hazmat_class(category, p.get("hazmat_class"))
    requires_cold = bool(p.get("requires_cold_chain", product_requires_cold(category, shelf, hazmat)))
    entry = {
        "product_id": pid,
        "name_zh": p["name_zh"],
        "category": category,
        "origin_city_id": cid,
        "origin_country_id": country_id,
        "weight_kg": w,
        "volume_l": round(w * 1.2, 2),
        "base_reference_price": float(p["base_reference_price"]),
        "reference_currency": p.get("reference_currency", "USD"),
        "shelf_life_hours": shelf,
        "fragility": float(p.get("fragility", 0.0)),
        "rarity": float(p["rarity"]),
        "description": p.get("description", ""),
        "price_confidence": "C",
        "hazmat_class": hazmat,
        "requires_cold_chain": requires_cold,
    }
    if p.get("inherited_from"):
        entry["inherited_from"] = p["inherited_from"]
    return entry


def _is_template_filler(blur: dict) -> bool:
    """True when a city's text is still padded with the expansion placeholder.

    Template-filler cities are downgraded to C confidence so the game UI shows
    the "资料不足" disclaimer (MainHUD checks content_confidence == "C").
    """
    filler = "更多细节将在后续更新中扩展"
    return any(
        filler in str(blur.get(k, ""))
        for k in (
            "short_description", "overview", "history_summary",
            "geography_summary", "economy_summary", "food_summary", "travel_note",
        )
    )


def build_cities_products(hubs_cfg: dict, eco: dict) -> tuple[list[dict], list[dict], list[dict]]:
    cities = []
    products = []
    markets = []
    product_ids: set[str] = set()
    for h in hubs_cfg["hubs"]:
        cid = h["city_id"]
        country_id = h.get("country_id", "XX")
        country_zh = h.get("country_zh", h.get("city_zh", h.get("name_zh", "")))
        blur = load_city_blurb(cid, h.get("city_zh", cid), h.get("city_en", cid),
                               country_id, country_zh, h.get("timezone", "UTC"))
        has_content = h.get("has_content_file", True)
        image_id = h.get("image_asset_id", f"city_{cid}_hero_720")
        conf = "C" if _is_template_filler(blur) else blur.get("content_confidence", "C")
        cities.append(
            {
                "city_id": cid,
                "name_zh": blur.get("name_zh", h.get("city_zh", cid)),
                "name_en": blur.get("name_en", h.get("city_en", cid)),
                "country_id": blur.get("country_id", country_id),
                "country_zh": blur.get("country_zh", country_zh),
                "timezone": blur.get("timezone", h.get("timezone", "UTC")),
                "short_description": blur["short_description"][:150],
                "overview": blur["overview"],
                "history_summary": blur["history_summary"],
                "geography_summary": blur["geography_summary"],
                "economy_summary": blur["economy_summary"],
                "food_summary": blur["food_summary"],
                "travel_note": blur["travel_note"],
                "content_confidence": conf,
                "source_ids": blur.get("source_ids", []),
                "image_asset_id": image_id,
                "has_content_file": has_content,
            }
        )
        # Load authored products
        authored = load_city_product_rows(cid)
        for p in authored:
            entry = _make_product_entry(p, cid, country_id, product_ids)
            if entry:
                # Template cities use national-standard products (inheritance).
                if conf == "C":
                    entry["inherited_from"] = "country_template"
                products.append(entry)
        # Generate inherited products if needed
        if len(authored) < 3:
            inherited = generate_inherited_products(cid, country_id, len(authored), product_ids)
            for p in inherited:
                entry = _make_product_entry(p, cid, country_id, product_ids)
                if entry:
                    products.append(entry)
    # markets: every product in every city
    mcfg = eco["market"]
    city_ids = [h["city_id"] for h in hubs_cfg["hubs"]]
    city_country = {h["city_id"]: h.get("country_id", "XX") for h in hubs_cfg["hubs"]}
    for city_id in city_ids:
        cpl = COUNTRY_PRICE_LEVEL.get(city_country[city_id], 1.0)
        for prod in products:
            origin = prod["origin_city_id"]
            is_origin = origin == city_id
            supply = mcfg["origin_supply_bonus"] if is_origin else 1.0
            scarcity = 1.0
            if not is_origin:
                scarcity = 1.0 + (prod["rarity"] * (mcfg["scarcity_remote_bonus"] - 1.0))
                if city_country.get(city_id, "") == prod["origin_country_id"]:
                    scarcity *= 0.9
            buy = prod["base_reference_price"] * cpl * supply * mcfg["retail_markup"]
            sell = prod["base_reference_price"] * cpl * scarcity * (1.0 - mcfg["buy_sell_spread"] * 0.5)
            if is_origin:
                sell = buy * (1.0 - mcfg["buy_sell_spread"])
            else:
                # Per-(product, destination) demand factor so best markets vary
                # across cities instead of always being the highest price-level
                # country (GB). Keeps "⭐最佳目的地" meaningful per product.
                sell *= _remote_demand(prod["product_id"], city_id)
                sell = max(sell, buy * 0.95)
                buy = prod["base_reference_price"] * cpl * 1.05 * mcfg["retail_markup"]
            markets.append(
                {
                    "city_id": city_id,
                    "product_id": prod["product_id"],
                    "buy_base_usd": round(buy, 2),
                    "sell_base_usd": round(sell, 2),
                }
            )
    return cities, products, markets


def write_sqlite(airports, routes, flights, cities, products, markets, eco, meta: dict) -> Path:
    OUT.mkdir(parents=True, exist_ok=True)
    world_path = OUT / "world.sqlite"
    flights_path = OUT / "flights_2025_03.sqlite"
    if world_path.exists():
        world_path.unlink()
    if flights_path.exists():
        flights_path.unlink()

    w = sqlite3.connect(world_path)
    w.executescript(
        """
        CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT);
        CREATE TABLE airports(
          airport_id TEXT PRIMARY KEY, iata TEXT, icao TEXT, name_zh TEXT, name_en TEXT,
          city_id TEXT, city_zh TEXT, city_en TEXT, country_id TEXT, country_zh TEXT,
          timezone TEXT, latitude REAL, longitude REAL, elevation_ft REAL, type TEXT,
          has_scheduled_service INTEGER, has_passenger_service INTEGER, data_confidence TEXT
        );
        CREATE TABLE routes(
          origin_iata TEXT, destination_iata TEXT, distance_km REAL,
          PRIMARY KEY(origin_iata, destination_iata)
        );
        CREATE TABLE airlines(airline_id TEXT PRIMARY KEY, name TEXT);
        CREATE TABLE cities(
          city_id TEXT PRIMARY KEY, name_zh TEXT, name_en TEXT, country_id TEXT, country_zh TEXT,
          timezone TEXT, short_description TEXT, overview TEXT, history_summary TEXT,
          geography_summary TEXT, economy_summary TEXT, food_summary TEXT, travel_note TEXT,
          content_confidence TEXT
        );
        CREATE TABLE products(
          product_id TEXT PRIMARY KEY, name_zh TEXT, category TEXT, origin_city_id TEXT,
          origin_country_id TEXT, weight_kg REAL, volume_l REAL, base_reference_price REAL,
          reference_currency TEXT, shelf_life_hours REAL, fragility REAL, rarity REAL,
          description TEXT, price_confidence TEXT
        );
        CREATE TABLE market_base(
          city_id TEXT, product_id TEXT, buy_base_usd REAL, sell_base_usd REAL,
          PRIMARY KEY(city_id, product_id)
        );
        CREATE TABLE fx_rates(currency_code TEXT PRIMARY KEY, rate_to_cny REAL, effective_date TEXT, source TEXT);
        CREATE TABLE attributions(id INTEGER PRIMARY KEY, name TEXT, license TEXT, note TEXT);
        """
    )
    for k, v in meta.items():
        w.execute("INSERT INTO meta VALUES(?,?)", (k, str(v)))
    for a in airports:
        w.execute(
            "INSERT INTO airports VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
            (
                a["airport_id"], a["iata"], a["icao"], a["name_zh"], a["name_en"],
                a["city_id"], a["city_zh"], a["city_en"], a["country_id"], a["country_zh"],
                a["timezone"], a["latitude"], a["longitude"], a["elevation_ft"], a["type"],
                1 if a.get("has_scheduled_service", False) else 0,
                1 if a.get("has_passenger_service", False) else 0,
                a["data_confidence"],
            ),
        )
    for o, d in routes:
        aa = next(x for x in airports if x["iata"] == o)
        bb = next(x for x in airports if x["iata"] == d)
        dist = haversine_km(aa["latitude"], aa["longitude"], bb["latitude"], bb["longitude"])
        w.execute("INSERT INTO routes VALUES(?,?,?)", (o, d, round(dist, 1)))
    for code, name in AIRLINES:
        w.execute("INSERT INTO airlines VALUES(?,?)", (code, name))
    for c in cities:
        w.execute(
            "INSERT INTO cities VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
            (
                c["city_id"], c["name_zh"], c["name_en"], c["country_id"], c["country_zh"],
                c["timezone"], c["short_description"], c["overview"], c["history_summary"],
                c["geography_summary"], c["economy_summary"], c["food_summary"], c["travel_note"],
                c["content_confidence"],
            ),
        )
    for p in products:
        w.execute(
            "INSERT INTO products VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
            (
                p["product_id"], p["name_zh"], p["category"], p["origin_city_id"], p["origin_country_id"],
                p["weight_kg"], p["volume_l"], p["base_reference_price"], p["reference_currency"],
                p["shelf_life_hours"], p["fragility"], p["rarity"], p["description"], p["price_confidence"],
            ),
        )
    for m in markets:
        w.execute(
            "INSERT INTO market_base VALUES(?,?,?,?)",
            (m["city_id"], m["product_id"], m["buy_base_usd"], m["sell_base_usd"]),
        )
    w.execute(
        "INSERT INTO fx_rates VALUES(?,?,?,?)",
        ("USD", eco["fx"]["USD_CNY"], eco["fx"]["effective_date"], "frozen_snapshot"),
    )
    w.execute(
        "INSERT INTO fx_rates VALUES(?,?,?,?)",
        ("CNY", 1.0, eco["fx"]["effective_date"], "frozen_snapshot"),
    )
    attributions = [
        ("OurAirports", "Unlicense / public domain", "Airport coordinates and metadata"),
        ("OpenFlights", "ODbL", "Route adjacency used to seed synthetic schedules"),
        ("Natural Earth", "public domain", "Globe visual inspiration; simplified procedural earth in Demo"),
        ("Airborne Trader Demo", "game content", "City blurbs and products are original game content"),
    ]
    for name, lic, note in attributions:
        w.execute("INSERT INTO attributions(name, license, note) VALUES(?,?,?)", (name, lic, note))
    w.commit()
    w.close()

    fdb = sqlite3.connect(flights_path)
    fdb.execute(
        """
        CREATE TABLE flight_instance(
          flight_instance_id TEXT PRIMARY KEY,
          marketing_flight_number TEXT,
          operating_airline_id TEXT,
          marketing_airline_id TEXT,
          airline_name TEXT,
          origin_airport_id TEXT,
          destination_airport_id TEXT,
          origin_iata TEXT,
          destination_iata TEXT,
          scheduled_departure_utc TEXT,
          scheduled_arrival_utc TEXT,
          distance_km REAL,
          duration_minutes INTEGER,
          aircraft_type TEXT,
          ticket_base_price_economy REAL,
          ticket_base_price_business REAL,
          baggage_allowance_economy REAL,
          baggage_allowance_business REAL,
          cabin_business_available INTEGER,
          data_source TEXT,
          data_confidence TEXT
        );
        """
    )
    fdb.execute(
        "CREATE INDEX idx_flight_origin_departure ON flight_instance(origin_airport_id, scheduled_departure_utc);"
    )
    for fl in flights:
        fdb.execute(
            "INSERT INTO flight_instance VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
            (
                fl["flight_instance_id"], fl["marketing_flight_number"], fl["operating_airline_id"],
                fl["marketing_airline_id"], fl["airline_name"], fl["origin_airport_id"],
                fl["destination_airport_id"], fl["origin_iata"], fl["destination_iata"],
                fl["scheduled_departure_utc"], fl["scheduled_arrival_utc"], fl["distance_km"],
                fl["duration_minutes"], fl["aircraft_type"], fl["ticket_base_price_economy"],
                fl["ticket_base_price_business"], fl["baggage_allowance_economy"],
                fl["baggage_allowance_business"], 1 if fl["cabin_business_available"] else 0,
                fl["data_source"], fl["data_confidence"],
            ),
        )
    fdb.commit()
    fdb.close()
    return world_path


def export_json_for_godot(airports, routes, flights, cities, products, markets, eco, meta,
                         tz_offsets, product_market_tags, transfer_edges,
                         coverage_report, real_airlines=None):
    import shutil

    GAME_DATA.mkdir(parents=True, exist_ok=True)

    # English city-text fields (Step 3 W5): Demo 20 hubs authored, rest templated.
    cities = apply_en_fields(cities)

    # ── world.json (lightweight core) ──
    economy_out = {
            "starting_cash_usd": eco["starting_cash_usd"],
            "fx_usd_cny": eco["fx"]["USD_CNY"],
            "baggage_extras": eco["baggage_extras"],
            "ticket": eco["ticket"],
            "market": eco["market"],
            "carry_on_kg": eco["ticket"]["carry_on_kg"],
        }
    if eco.get("mct"):
        economy_out["mct"] = eco["mct"]
    if eco.get("reliability"):
        economy_out["reliability"] = eco["reliability"]
    if eco.get("cold_chain"):
        economy_out["cold_chain"] = eco["cold_chain"]
    if eco.get("dynamics"):
        economy_out["dynamics"] = eco["dynamics"]

    # Curated airlines first (known alliance metadata), then every real operator
    # used by the generated flights. Resolve name/home_country from the flights
    # themselves (majority vote) so reused IATA codes (e.g. G3 = Gol + Sky
    # Express) match what players actually see in the schedule.
    airlines_out: list[dict] = []
    seen: set[str] = set()
    for row in _AIRLINE_ROWS or [{"id": a, "name": n, "alliance_id": "none"} for a, n in AIRLINES]:
        airlines_out.append({**row, "home_country": row.get("home_country", "")})
        seen.add(row["id"])
    flight_airlines: dict[str, Counter] = {}
    for fl in flights:
        flight_airlines.setdefault(str(fl.get("operating_airline_id", "")), Counter())[
            (str(fl.get("airline_name", "")), str(fl.get("airline_home_country", "")))
        ] += 1
    used_iatas = sorted(flight_airlines)
    for iata in used_iatas:
        if not iata or iata in seen:
            continue
        (name, home), _ = flight_airlines[iata].most_common(1)[0]
        airlines_out.append({
            "id": iata,
            "name": name or iata,
            "alliance_id": "none",
            "home_country": home,
        })
        seen.add(iata)
    payload = {
        "meta": meta,
        "economy": economy_out,
        "airports": airports,
        "routes": [{"origin": o, "destination": d} for o, d in sorted(routes)],
        "cities": cities,
        "products": products,
        "tz_offsets": tz_offsets,
        "airlines": airlines_out,
        "alliances": _ALLIANCES,
        "dangerous_goods": {
            "classes": (_DG_RULES.get("classes") or {}),
            "category_defaults": (_DG_RULES.get("category_defaults") or {}),
        },
        "attributions": [
            {"name": "OurAirports", "license": "Unlicense", "note": "Airport coordinates"},
            {"name": "OpenFlights", "license": "ODbL", "note": "Route seed for synthetic schedules"},
            {"name": "Game content", "license": "original", "note": "City and product texts"},
        ],
        "disclaimer": "航班网络基于公开航空数据重建，不代表真实购票信息。",
        "coverage_report": coverage_report,
    }
    (GAME_DATA / "world.json").write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")

    # ── markets/ (per-city files, O(1) lazy load) ──
    markets_dir = GAME_DATA / "markets"
    markets_dir.mkdir(parents=True, exist_ok=True)
    # Clear stale files
    for old in markets_dir.glob("*.json"):
        old.unlink()
    markets_by_city: dict[str, list] = {}
    for m in markets:
        cid = m["city_id"]
        entry = {"p": m["product_id"], "b": m["buy_base_usd"], "s": m["sell_base_usd"]}
        markets_by_city.setdefault(cid, []).append(entry)
    for cid, entries in markets_by_city.items():
        (markets_dir / f"{cid}.json").write_text(
            json.dumps(entries, ensure_ascii=False, separators=(",", ":")), encoding="utf-8"
        )
    # Clean up old monolithic file if present
    old_mk = GAME_DATA / "markets.json"
    if old_mk.exists():
        old_mk.unlink()
    print(f"Exported {len(markets_by_city)} market files to {markets_dir}")

    # ── product_market_tags.json ──
    (GAME_DATA / "product_market_tags.json").write_text(
        json.dumps(product_market_tags, ensure_ascii=False, separators=(",", ":")), encoding="utf-8"
    )

    # ── transfers/ (per-origin files, lazy load on flight search) ──
    transfers_dir = GAME_DATA / "transfers"
    transfers_dir.mkdir(parents=True, exist_ok=True)
    for old in transfers_dir.glob("*.json"):
        old.unlink()
    # Batch by origin IATA: {dest_iata: [edges, ...], ...}
    by_origin_xfer: dict[str, dict] = {}
    for key, edges in transfer_edges.items():
        # key format: "origin_iata|dest_iata"
        parts = key.split("|", 1)
        if len(parts) != 2:
            continue
        origin, dest = parts
        by_origin_xfer.setdefault(origin, {})[dest] = edges
    for origin, edges_map in by_origin_xfer.items():
        (transfers_dir / f"{origin}.json").write_text(
            json.dumps(edges_map, ensure_ascii=False, separators=(",", ":")), encoding="utf-8"
        )
    # Clean up old monolithic file
    old_te = GAME_DATA / "transfer_edges.json"
    if old_te.exists():
        old_te.unlink()
    print(f"Exported {len(by_origin_xfer)} transfer files to {transfers_dir}")

    # ── flights/ (per-origin files, lazy-loadable) ──
    flights_dir = GAME_DATA / "flights"
    flights_dir.mkdir(parents=True, exist_ok=True)
    by_origin: dict[str, list] = {}
    for fl in flights:
        by_origin.setdefault(fl["origin_airport_id"], []).append(fl)
    for lst in by_origin.values():
        lst.sort(key=lambda x: x["scheduled_departure_utc"])
    for origin_id, fl_list in by_origin.items():
        (flights_dir / f"{origin_id}.json").write_text(
            json.dumps(fl_list, ensure_ascii=False, separators=(",", ":")),
            encoding="utf-8",
        )
    # Write index manifest
    manifest = {k: len(v) for k, v in by_origin.items()}
    manifest["_total"] = len(flights)
    (flights_dir / "_manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, separators=(",", ":")), encoding="utf-8"
    )
    print(f"Exported {len(by_origin)} flight files ({len(flights)} total)")
    # Also remove old monolithic flights.json if it exists
    old_flights = GAME_DATA / "flights.json"
    if old_flights.exists():
        old_flights.unlink()

    # also copy sqlite
    shutil.copy2(OUT / "world.sqlite", GAME_DATA / "world.sqlite")
    shutil.copy2(OUT / "flights_2025_03.sqlite", GAME_DATA / "flights_2025_03.sqlite")


def build_transfer_edges(routes: set[tuple[str, str]], airports_by_iata: dict[str, dict],
                         iatas: list[str], eco: dict | None = None) -> dict:
    """Build single-hop transfer edges for city pairs without direct routes.

    Returns dict keyed by "origin_iata|dest_iata" →
    [{hub, total_distance_km, seg1_duration_avg, seg2_duration_avg, mct_minutes}].
    Hubs must have degree >= 8. Total 5 shortest edges per O/D pair.
    MCT is per-hub (economy.mct / airport.mct_minutes).
    """
    eco = eco or {}
    transfer_edges: dict[str, list] = {}
    direct = set(routes)
    CRUISE = 13.5  # km/min
    TAXI = 40  # minutes
    max_conn = int((eco.get("mct") or {}).get("max_connection_min", 480))

    neighbor_of: dict[str, set[str]] = {}
    for o, d in direct:
        neighbor_of.setdefault(o, set()).add(d)

    hub_set = {iata for iata in iatas if len(neighbor_of.get(iata, set())) >= 8}

    hub_dists: dict[str, dict[str, float]] = {}
    for hub in hub_set:
        ha = airports_by_iata[hub]
        hub_dists[hub] = {}
        for iata in iatas:
            if iata == hub:
                continue
            ia = airports_by_iata[iata]
            hub_dists[hub][iata] = haversine_km(ha["latitude"], ha["longitude"],
                                                 ia["latitude"], ia["longitude"])

    for origin in iatas:
        oa = airports_by_iata[origin]
        for dest in iatas:
            if origin == dest:
                continue
            if (origin, dest) in direct:
                continue
            da = airports_by_iata[dest]
            international = oa.get("country_id") != da.get("country_id")
            edges = []
            for hub in hub_set:
                if hub == origin or hub == dest:
                    continue
                o_neighbors = neighbor_of.get(origin, set())
                if hub not in o_neighbors:
                    continue
                if dest not in neighbor_of.get(hub, set()):
                    continue
                hub_ap = airports_by_iata[hub]
                mct = airport_mct_minutes(hub_ap, eco, international=international)
                d1 = hub_dists[hub][origin]
                d2 = hub_dists[hub][dest]
                total_dist = d1 + d2
                seg1_dur = int(d1 / CRUISE + TAXI)
                seg2_dur = int(d2 / CRUISE + TAXI)
                if seg1_dur + mct + seg2_dur > 1440:
                    continue
                if mct > max_conn:
                    continue
                edges.append({
                    "hub": hub,
                    "total_distance_km": round(total_dist, 1),
                    "seg1_duration_avg": seg1_dur,
                    "seg2_duration_avg": seg2_dur,
                    "mct_minutes": mct,
                })
            if edges:
                # Deterministic ordering: distance first, then hub IATA as tie-break.
                # Without the hub key, equal-distance hubs (e.g. HAM/DUS both 3625.7 km)
                # keep their set-iteration order, which is randomized per process and
                # makes every pipeline run dirty every tracked transfer file.
                edges.sort(key=lambda e: (e["total_distance_km"], e["hub"]))
                key = f"{origin}|{dest}"
                transfer_edges[key] = edges[:5]
    return transfer_edges


def build_coverage_report(cities, airports, products, product_market_tags, transfer_edges,
                          flights: list | None = None) -> dict:
    """Generate coverage report for CI gating."""
    l2_cities = len(cities)
    l1_airports = sum(1 for a in airports if a.get("has_passenger_service", False))
    l0_airports = len(airports)
    missing_content = [c["city_id"] for c in cities if c.get("content_confidence") == "C"]
    total_products = len(products)
    product_market_pairs = len(product_market_tags)
    transfer_pairs = len(transfer_edges)
    categories = len(set(p.get("category", "") for p in products))
    flights = flights or []
    stopover_count = sum(1 for f in flights if int(f.get("stops", 0)) > 0)
    cold_products = sum(1 for p in products if p.get("requires_cold_chain"))
    hazmat_restricted = sum(
        1 for p in products if p.get("hazmat_class") in ("restricted_cabin", "forbidden")
    )
    mct_overrides = sum(1 for a in airports if "mct_minutes" in a)

    report = {
        "l2_cities": l2_cities,
        "l1_passenger_airports": l1_airports,
        "l0_total_airports": l0_airports,
        "total_products": total_products,
        "product_market_tag_pairs": product_market_pairs,
        "transfer_edge_pairs": transfer_pairs,
        "product_categories": categories,
        "missing_content_cities": missing_content,
        "missing_content_count": len(missing_content),
        "has_souvenir_category": any(p.get("category") == "纪念品" for p in products),
        "stopover_flights": stopover_count,
        "cold_chain_products": cold_products,
        "hazmat_restricted_products": hazmat_restricted,
        "mct_override_airports": mct_overrides,
        "etl_version": "0.3.0",
    }
    return report


def _check_hot_win_rate(product_market_tags: dict, market_index: dict, samples: int = 200) -> None:
    """Sample hot-tag pairs and estimate win rate under runtime noise.

    Simulates ±6% daily noise on buy and sell prices independently (uniform).
    Reports the percentage of hot pairs that remain profitable (sell > buy).
    Target: ≥85% at quality=1.0, ≥70% at quality=0.8.
    """
    import random as _rnd

    hot_pairs = []
    for key, tags in product_market_tags.items():
        origin_city, product_id = key.split("|")
        hot_cities = tags.get("hot", [])
        for dest_city in hot_cities:
            hot_pairs.append((origin_city, dest_city, product_id))

    if not hot_pairs:
        print("HOT-WIN: No hot pairs to sample")
        return

    n = min(samples, len(hot_pairs))
    sampled = _rnd.sample(hot_pairs, n)

    # Test at quality=1.0 (no quality penalty)
    wins_q10 = 0
    wins_q08 = 0
    for origin_city, dest_city, product_id in sampled:
        buy_base = market_index[(origin_city, product_id)]["buy"]
        sell_base = market_index[(dest_city, product_id)]["sell"]

        # Simulate 10 random noise scenarios and check if all are profitable
        all_profitable_q10 = True
        all_profitable_q08 = True
        for _ in range(10):
            noise_buy = 1.0 + _rnd.uniform(-0.06, 0.06)
            noise_sell = 1.0 + _rnd.uniform(-0.06, 0.06)
            buy = buy_base * noise_buy
            sell_q10 = sell_base * noise_sell * 1.0  # quality=1.0
            sell_q08 = sell_base * noise_sell * 0.75  # quality=0.8
            if sell_q10 <= buy:
                all_profitable_q10 = False
            if sell_q08 <= buy:
                all_profitable_q08 = False

        if all_profitable_q10:
            wins_q10 += 1
        if all_profitable_q08:
            wins_q08 += 1

    rate_q10 = 100.0 * wins_q10 / n
    rate_q08 = 100.0 * wins_q08 / n
    status_q10 = "PASS" if rate_q10 >= 85 else "FAIL"
    status_q08 = "PASS" if rate_q08 >= 70 else "FAIL"
    print(f"HOT-WIN rate (q=1.0): {rate_q10:.1f}% [{status_q10}] (target ≥85%)")
    print(f"HOT-WIN rate (q=0.8): {rate_q08:.1f}% [{status_q08}] (target ≥70%)")
    print(f"HOT-WIN sampled {n}/{len(hot_pairs)} hot pairs, {len(hot_pairs)} total hot dests")


def validate(
    airports, routes, flights, cities, products,
    route_airlines: dict[tuple[str, str], set[str]] | None = None,
    active_iatas: set[str] | None = None,
    real_airlines: dict[str, dict] | None = None,
) -> None:
    iatas = {a["iata"] for a in airports}
    assert len(iatas) >= 20, f"Expected >=20 airports, got {len(iatas)}"
    for a in airports:
        assert -90 <= a["latitude"] <= 90, f"{a['iata']} lat out of range"
        assert -180 <= a["longitude"] <= 180, f"{a['iata']} lon out of range"
        if a["latitude"] == 0 and a["longitude"] == 0:
            print(f"WARN: {a['iata']} at (0,0)")
    # degree check only for airports used in routes
    active_iatas_r = {o for o, d in routes}
    for a in active_iatas_r:
        deg = sum(1 for o, d in routes if o == a)
        if deg < 3:
            print(f"WARN: {a} low degree {deg}")
    assert len(flights) > 0, "No flights generated"
    for fl in flights:
        assert fl["origin_iata"] != fl["destination_iata"]
        assert fl["scheduled_arrival_utc"] > fl["scheduled_departure_utc"]
        assert fl["ticket_base_price_economy"] > 0
        assert abs(fl["ticket_base_price_business"] - fl["ticket_base_price_economy"] * 10) < 0.02
    assert len(cities) >= 20, f"Expected >=20 cities, got {len(cities)}"
    by_city: dict[str, int] = {}
    for p in products:
        cid = p["origin_city_id"]
        by_city[cid] = by_city.get(cid, 0) + 1
    low_products = {cid: n for cid, n in by_city.items() if n < 3}
    if low_products:
        print(f"WARN: cities with <3 products: {low_products}")
    authored = [c for c in cities if c.get("content_confidence") != "C"]
    for c in authored:
        assert len(c.get("short_description", "")) >= 60, f"{c['city_id']} short desc too short"
    # i18n gate (Step 3 W5): every city must carry the full *_en set.
    missing_en = [
        c["city_id"] for c in cities
        if any(not str(c.get(k, "")).strip() for k in FIELD_EN_MAP.values())
    ]
    assert not missing_en, f"cities missing *_en fields: {missing_en}"
    no_category_souvenir = any(p.get("category") == "纪念品" for p in products)
    if no_category_souvenir:
        print("WARN: souvenir ('纪念品') category still present")

    by_iata_v = {a["iata"]: a for a in airports}

    # Real-airline gates (fail hard — the whole point of the aviation overhaul):
    if route_airlines and active_iatas and real_airlines:
        # 1) Every flight on a real route must be operated by a real operator.
        fabricated: list[str] = []
        for fl in flights:
            ops = route_airlines.get((fl["origin_iata"], fl["destination_iata"]), set())
            if not ops or not (ops & active_iatas):
                continue  # no active real operator → documented fallback allowed
            if fl["operating_airline_id"] not in ops:
                fabricated.append(
                    f"{fl['marketing_flight_number']} {fl['origin_iata']}→{fl['destination_iata']} "
                    f"by {fl['operating_airline_id']} (real: {sorted(ops)})"
                )
        assert not fabricated, (
            f"{len(fabricated)} flights use an airline not recorded on the route in routes.dat, e.g.:\n  "
            + "\n  ".join(fabricated[:8])
        )
        # 2) Fallback/synthetic routes: operating airline must be a real active
        #    airline based on the same continent as an endpoint (regional carrier).
        bad_fill: list[str] = []
        for fl in flights:
            ops = route_airlines.get((fl["origin_iata"], fl["destination_iata"]), set())
            if ops & active_iatas:
                continue
            o_c = by_iata_v[fl["origin_iata"]]["country_id"]
            d_c = by_iata_v[fl["destination_iata"]]["country_id"]
            airline_iso = str(fl.get("airline_home_country", "")) or _resolved_country(
                fl["operating_airline_id"], real_airlines, (o_c, d_c)
            )
            airline_cont = country_continent(airline_iso)
            o_cont = country_continent(o_c)
            d_cont = country_continent(d_c)
            if not airline_cont or airline_cont not in (o_cont, d_cont):
                bad_fill.append(
                    f"{fl['marketing_flight_number']} {fl['origin_iata']}→{fl['destination_iata']} "
                    f"by {fl['operating_airline_id']}({airline_cont}) not in {o_cont}/{d_cont}"
                )
        assert not bad_fill, (
            f"{len(bad_fill)} fallback flights use an airline from a third continent, e.g.:\n  "
            + "\n  ".join(bad_fill[:8])
        )
        # 3) Domestic routes: when a real operator from the route country exists,
        #    the flight must use one of them (blocks defunct/foreign fillers such
        #    as JAS on CN domestic). Foreign operators are only allowed when the
        #    route has no domestic operator in routes.dat.
        foreign_domestic: list[str] = []
        for fl in flights:
            o, d = fl["origin_iata"], fl["destination_iata"]
            route_country = by_iata_v[o]["country_id"]
            if route_country != by_iata_v[d]["country_id"]:
                continue
            ops = route_airlines.get((o, d), set())
            domestic_ops = [a for a in (ops & active_iatas) if route_country in _entry_countries(a, real_airlines)]
            if not domestic_ops:
                continue  # no domestic operator on this real route → foreign allowed
            if fl["operating_airline_id"] not in domestic_ops:
                foreign_domestic.append(
                    f"{fl['marketing_flight_number']} {o}→{d} by {fl['operating_airline_id']} "
                    f"(domestic ops: {sorted(domestic_ops)})"
                )
        assert not foreign_domestic, (
            f"{len(foreign_domestic)} domestic flights use a foreign airline although a "
            f"domestic operator exists, e.g.:\n  " + "\n  ".join(foreign_domestic[:8])
        )
        # 4) Every passenger airport must have a direct international route.
        no_intl = [
            a["iata"] for a in airports
            if a.get("has_passenger_service", False)
            and not any(
                by_iata_v[o]["country_id"] != by_iata_v[d]["country_id"]
                for o, d in routes if o == a["iata"]
            )
        ]
        assert not no_intl, f"airports without any international route: {sorted(no_intl)}"

        real_route_flights = sum(
            1 for fl in flights
            if fl["operating_airline_id"] in (route_airlines.get((fl["origin_iata"], fl["destination_iata"]), set()) & active_iatas)
        )
        print(
            f"VALIDATION OK (aviation): {real_route_flights}/{len(flights)} "
            f"flights operated by real route operators "
            f"({100.0 * real_route_flights / len(flights):.1f}%)"
        )

    print(f"VALIDATION OK: {len(airports)} airports ({len(active_iatas_r)} active), "
          f"{len(routes)} directed routes, {len(flights)} flights, "
          f"{len(cities)} cities, {len(products)} products")


def main() -> int:
    global _CITY_NAME_ZH, _AIRLINE_ROWS, _ALLIANCES, _DG_RULES
    _CITY_NAME_ZH = _load_city_names()
    _AIRLINE_ROWS, _ALLIANCES, _DG_RULES = load_aviation_config()
    hubs_cfg = load_yaml(CFG / "hubs_20.yaml")
    eco = load_yaml(CFG / "economy.yaml")
    oa = read_ourairports_by_iata(RAW / "airports.csv")

    # Build passenger IATA set from OpenFlights routes
    openflights_iatas: set[str] = set()
    rf_path = RAW / "routes.dat"
    if rf_path.exists():
        with rf_path.open(encoding="utf-8", newline="") as f:
            for line in f:
                parts = line.strip().split(",")
                if len(parts) >= 5:
                    src = parts[2].strip()
                    dst = parts[4].strip()
                    if src:
                        openflights_iatas.add(src)
                    if dst:
                        openflights_iatas.add(dst)

    # Expand to 500+ cities from OurAirports data
    auto_limit = 30  # Default: manageable for dev iteration
    if "--full" in sys.argv:
        auto_limit = 480  # Full 500+ city scale
    additional = build_cities_500_from_ourairports(oa, hubs_cfg["hubs"], openflights_iatas)
    additional = additional[:auto_limit]
    all_hub_configs = list(hubs_cfg["hubs"]) + additional
    # Combine into a single config-like structure
    hubs_cfg_expanded = {"hubs": all_hub_configs, "fallback_coords": hubs_cfg.get("fallback_coords", {})}

    print(f"Total hub configs: {len(all_hub_configs)} (20 authored + {len(additional)} auto)")

    airports = build_airports(hubs_cfg_expanded, oa, openflights_iatas)
    by_iata = {a["iata"]: a for a in airports}
    iatas = [a["iata"] for a in airports]

    # Build routes: use OpenFlights edges where both airports exist
    # For expanded sets, limit route degree and flight count
    min_deg = max(2, min(6, len(iatas) // 10))
    edges = read_openflights_routes(rf_path, set(iatas))
    # Real airline/route data (OpenFlights) — replaces the 18-airline random pool.
    real_airlines = read_real_airlines(RAW / "airlines.dat")
    active_iatas = {
        i for i, entries in real_airlines.items()
        if any(e.get("active") == "Y" for e in entries)
    }
    curated_alliance = {r["id"]: r.get("alliance_id", "none") for r in _AIRLINE_ROWS}
    route_airlines = read_route_airlines(rf_path, set(iatas), active_iatas)
    routes = ensure_route_degree(edges, iatas, min_deg, by_iata)
    # Guarantee every airport has a direct international route (PRD plan-A 补齐).
    routes = ensure_intl_routes(routes, iatas, by_iata, route_airlines, active_iatas)

    # For expanded sets, reduce flight density
    if len(additional) > 0:
        eco = dict(eco)
        eco["flight_synth"] = dict(eco["flight_synth"])
        eco["flight_synth"]["flights_per_day_min"] = 1
        eco["flight_synth"]["flights_per_day_max"] = 2
    flights = synth_flights(routes, by_iata, eco, route_airlines, active_iatas,
                            real_airlines, curated_alliance)
    cities, products, markets = build_cities_products(hubs_cfg_expanded, eco)
    # *_en fields are required by validate() and the export; apply before both.
    cities = apply_en_fields(cities)

    # Build product_market_tags: only origin-city products (O(n*m) vs O(n*n*m))
    product_market_tags: dict[str, dict] = {}
    market_index: dict[tuple, dict] = {}
    for m in markets:
        market_index[(m["city_id"], m["product_id"])] = {
            "buy": m["buy_base_usd"],
            "sell": m["sell_base_usd"],
        }

    city_ids = [c["city_id"] for c in cities]
    # Only build tags for (origin_city, product_id) where the product originates
    # from origin_city — this is what matters for gameplay (buy here, sell there).
    # v0.2: raised thresholds so hot Tag means ≥85% win rate under reasonable noise
    for product in products:
        product_id = product["product_id"]
        origin_city = product["origin_city_id"]
        key = f"{origin_city}|{product_id}"
        product_market_tags[key] = {"hot": [], "normal": [], "cold": []}
        buy_origin = market_index[(origin_city, product_id)]["buy"]

        dest_ratios = []
        for dest_city in city_ids:
            sell_remote = market_index[(dest_city, product_id)]["sell"]
            sell_buy_ratio = sell_remote / buy_origin if buy_origin > 0 else 1.0
            dest_ratios.append((sell_buy_ratio, dest_city))

        # Sort by ratio descending so hot[0] is best destination
        dest_ratios.sort(key=lambda x: -x[0])

        for sell_buy_ratio, dest_city in dest_ratios:
            if sell_buy_ratio >= 1.40:
                tag = "hot"
            elif sell_buy_ratio >= 1.10:
                tag = "normal"
            else:
                tag = "cold"

            product_market_tags[key][tag].append(dest_city)
    print(f"Built {len(product_market_tags)} product-market tag entries")

    # Hot-tag profit-rate sampling
    _check_hot_win_rate(product_market_tags, market_index)

    transfer_edges = build_transfer_edges(routes, by_iata, iatas, eco)

    coverage_report = build_coverage_report(
        cities, airports, products, product_market_tags, transfer_edges, flights
    )

    tz_offsets = build_tz_offsets(hubs_cfg_expanded, int(eco["flight_synth"]["schedule_days"]))
    meta = {
        "etl_version": "0.3.0",
        "baseline_date": "2025-03-01",
        "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "flight_count": len(flights),
        "route_count": len(routes),
        "airport_count": len(airports),
        "city_count": len(cities),
        "product_count": len(products),
        "transfer_edge_pairs": len(transfer_edges),
        "disclaimer": "real airlines/routes from OpenFlights; synthesized schedules",
    }
    validate(airports, routes, flights, cities, products, route_airlines, active_iatas, real_airlines)
    write_sqlite(airports, routes, flights, cities, products, markets, eco, meta)

    # Write coverage report
    (OUT / "coverage_report.json").write_text(
        json.dumps(coverage_report, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    print(f"Coverage report: {json.dumps(coverage_report, ensure_ascii=False)}")

    export_json_for_godot(airports, routes, flights, cities, products, markets, eco, meta,
                          tz_offsets, product_market_tags, transfer_edges, coverage_report,
                          real_airlines)
    digest = hashlib.sha256((OUT / "world.sqlite").read_bytes()).hexdigest()
    print(f"Wrote {OUT}/world.sqlite and flights; world hash={digest[:16]}...")
    print(f"Godot data -> {GAME_DATA}")
    print(f"Transfer edges: {len(transfer_edges)} pairs")
    # sanity: US DST flip around 2025-03-09
    ny = tz_offsets.get("America/New_York", {})
    if "2025-03-08" in ny and "2025-03-10" in ny:
        print(f"America/New_York offset Mar8={ny['2025-03-08']} Mar10={ny['2025-03-10']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
