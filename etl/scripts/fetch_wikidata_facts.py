#!/usr/bin/env python3
"""Fetch real Wikidata facts for all cities (airport IATA -> serviced place).

Resolution: SPARQL on wdt:P238 (IATA code) -> airport item -> wdt:P931 (place
served).  Facts and Chinese/English labels are pulled in the same SPARQL
passes.  Nothing is invented here: every value below comes from a Wikidata
claim.  Population uses the newest dated P1082 claim.

Output: etl/content/wikidata_facts.json
  city_id -> {
    "qid", "airport_qid", "name_zh",
    "population", "population_year", "elevation_m", "lat", "lon",
    "region_id", "region_zh", "country_wd_id", "country_zh",
    "water_id", "water_zh", "inception_year",
    "capital_of_zh", "timezone_zh", "language_zh", "resolved": bool
  }

Usage:
  python scripts/fetch_wikidata_facts.py            # full run
  python scripts/fetch_wikidata_facts.py --dry-run  # resolve only, no writes
"""
from __future__ import annotations

import json
import sqlite3
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONTENT = ROOT / "content"
FACTS_PATH = CONTENT / "wikidata_facts.json"
GAME_DATA = ROOT.parents[0] / "game" / "data"

UA = ("flyyy-etl/0.1 (game content authoring; contact via project issues; "
      "reads structured CC0 facts from Wikidata)")
SPARQL = "https://query.wikidata.org/sparql"

def _http(url: str, data: bytes | None = None, headers: dict | None = None,
          tries: int = 6) -> dict:
    hdrs = {"User-Agent": UA, "Accept": "application/json"}
    if headers:
        hdrs.update(headers)
    last: Exception | None = None
    for attempt in range(tries):
        try:
            req = urllib.request.Request(url, data=data, headers=hdrs)
            with urllib.request.urlopen(req, timeout=90) as r:
                return json.load(r)
        except Exception as e:  # 403 rate-limit, 5xx, network blips
            last = e
            time.sleep(7 * (attempt + 1))
    raise RuntimeError(f"request failed after {tries} tries: {last}")


def sparql(query: str) -> list[dict]:
    body = urllib.parse.urlencode({"query": query}).encode()
    data = _http(SPARQL, data=body, headers={
        "Accept": "application/sparql-results+json",
        "Content-Type": "application/x-www-form-urlencoded"})
    return data["results"]["bindings"]


def resolve_cities(iata_map: dict[str, str]) -> dict[str, dict]:
    """iata -> {airport_qid, city_qid, city_label_zh}."""
    out: dict[str, dict] = {}
    items = list(iata_map.items())
    for i in range(0, len(items), 40):
        chunk = items[i:i + 40]
        values = " ".join(f'"{iata}"' for iata, _ in chunk)
        q = f"""SELECT ?airport ?iata ?city ?cityLabel WHERE {{
  VALUES ?iata {{ {values} }}
  ?airport wdt:P238 ?iata.
  OPTIONAL {{ ?airport wdt:P931 ?city. }}
  SERVICE wikibase:label {{ bd:serviceParam wikibase:language "zh,en". }}
}}"""
        for row in sparql(q):
            iata = row["iata"]["value"]
            entry = {
                "airport_qid": row["airport"]["value"].rsplit("/", 1)[-1],
                "city_qid": "",
                "city_label_zh": "",
            }
            if "city" in row:
                entry["city_qid"] = row["city"]["value"].rsplit("/", 1)[-1]
                entry["city_label_zh"] = row.get("cityLabel", {}).get("value", "")
            if iata not in out or (entry["city_qid"] and not out[iata]["city_qid"]):
                out[iata] = entry
        time.sleep(2.0)
    return out


def _entity(qid: str) -> str:
    return f"wd:{qid}"


def _year_from_time(t: str | None) -> int | None:
    """Extract a CE year from a Wikidata time literal; None for BCE/odd cases.

    SPARQL returns CE dates without a sign ("1342-06-16T00:00:00Z"); the raw
    wbgetentities form may carry "+1342-..." — both are handled.
    """
    if not t:
        return None
    body = t[1:] if t[0] in "+-" else t
    digits = body[:4]
    if not digits.isdigit():
        return None
    year = int(digits)
    if t[0] == "-" or year < 1000:
        return None  # BCE or ancient dates — too fragile for prose
    return year


def fetch_facts(qids: list[str]) -> dict[str, dict]:
    """qid -> fact dict (single-valued claims + labels)."""
    out: dict[str, dict] = {}
    for i in range(0, len(qids), 40):
        chunk = qids[i:i + 40]
        values = " ".join(_entity(q) for q in chunk)
        q = f"""SELECT ?city ?elev ?inception ?loc
  ?region ?regionLabel ?country ?countryLabel ?water ?waterLabel
  ?cap ?capLabel ?tz ?tzLabel ?lang ?langLabel WHERE {{
  VALUES ?city {{ {values} }}
  OPTIONAL {{ ?city wdt:P2044 ?elev. }}
  OPTIONAL {{ ?city wdt:P571 ?inception. }}
  OPTIONAL {{ ?city wdt:P625 ?loc. }}
  OPTIONAL {{ ?city wdt:P131 ?region. }}
  OPTIONAL {{ ?city wdt:P17 ?country. }}
  OPTIONAL {{ ?city wdt:P206 ?water. }}
  OPTIONAL {{ ?city wdt:P1376 ?cap. }}
  OPTIONAL {{ ?city wdt:P421 ?tz. }}
  OPTIONAL {{ ?city wdt:P37 ?lang. }}
  SERVICE wikibase:label {{ bd:serviceParam wikibase:language "zh,en". }}
}}"""
        for row in sparql(q):
            cid = row["city"]["value"].rsplit("/", 1)[-1]
            if cid in out:
                continue
            lat = lon = None
            if row.get("loc"):
                # WKT point literal: "Point(<lon> <lat>)".
                raw = row["loc"]["value"].removeprefix("Point(").rstrip(")")
                parts = raw.split()
                if len(parts) == 2:
                    try:
                        lon, lat = float(parts[0]), float(parts[1])
                    except ValueError:
                        pass
            out[cid] = {
                "elevation_m": float(row["elev"]["value"]) if row.get("elev") else None,
                "inception": row["inception"]["value"] if row.get("inception") else None,
                "lat": lat,
                "lon": lon,
                "region_zh": row.get("regionLabel", {}).get("value", ""),
                "country_zh": row.get("countryLabel", {}).get("value", ""),
                "water_zh": row.get("waterLabel", {}).get("value", ""),
                "capital_of_zh": row.get("capLabel", {}).get("value", ""),
                "timezone_zh": row.get("tzLabel", {}).get("value", ""),
                "language_zh": row.get("langLabel", {}).get("value", ""),
                "region_id": row.get("region", {}).get("value", "").rsplit("/", 1)[-1],
                "country_wd_id": row.get("country", {}).get("value", "").rsplit("/", 1)[-1],
                "water_id": row.get("water", {}).get("value", "").rsplit("/", 1)[-1],
            }
        time.sleep(2.0)
    return out


def fetch_populations(qids: list[str]) -> dict[str, dict]:
    """qid -> {population, population_year} using the newest dated P1082."""
    out: dict[str, dict] = {}
    for i in range(0, len(qids), 40):
        chunk = qids[i:i + 40]
        values = " ".join(_entity(q) for q in chunk)
        q = f"""SELECT ?city ?pop ?t WHERE {{
  VALUES ?city {{ {values} }}
  ?city p:P1082 ?st.
  ?st ps:P1082 ?pop; pq:P585 ?t.
}}"""
        rows = sparql(q)
        seen: dict[str, tuple[int, float]] = {}
        for row in rows:
            cid = row["city"]["value"].rsplit("/", 1)[-1]
            year = _year_from_time(row["t"]["value"])
            if year is None:
                continue
            pop = float(row["pop"]["value"])
            cur = seen.get(cid)
            if cur is None or year > cur[0]:
                seen[cid] = (year, pop)
        for cid, (year, pop) in seen.items():
            out[cid] = {"population": pop, "population_year": str(year)}
        time.sleep(2.0)
    return out


def main() -> int:
    dry = "--dry-run" in sys.argv
    db = GAME_DATA / "world.sqlite"
    if not db.exists():
        print(f"missing {db} — run the pipeline first")
        return 1
    con = sqlite3.connect(db)
    rows = con.execute(
        "SELECT city_id, iata FROM airports WHERE iata IS NOT NULL AND iata != ''"
    ).fetchall()
    con.close()
    iata_map = {r[1]: r[0] for r in rows}
    print(f"cities to resolve: {len(iata_map)}")

    resolved = resolve_cities(iata_map)
    hit = sum(1 for i in iata_map if i in resolved and resolved[i].get("city_qid"))
    print(f"SPARQL resolved {hit}/{len(iata_map)} with a serviced-place item")

    city_to_iata = {v: k for k, v in iata_map.items()}

    # Entity per city: the serviced-place item, or the airport item itself.
    qid_to_city: dict[str, str] = {}
    for iata, city_id in iata_map.items():
        r = resolved.get(iata, {})
        qid = r.get("city_qid") or r.get("airport_qid", "")
        if qid:
            qid_to_city.setdefault(qid, city_id)
    qids = list(qid_to_city.keys())

    facts = fetch_facts(qids)
    pops = fetch_populations(qids)

    final: dict[str, dict] = {}
    unresolved: list[str] = []
    for qid, city_id in qid_to_city.items():
        f = facts.get(qid, {})
        r_info = resolved.get(city_to_iata.get(city_id, ""), {})
        if not f:
            unresolved.append(city_id)
            continue
        pop = pops.get(qid, {})
        final[city_id] = {
            "qid": qid,
            "airport_qid": r_info.get("airport_qid", ""),
            "name_zh": r_info.get("city_label_zh", ""),
            "population": pop.get("population"),
            "population_year": pop.get("population_year"),
            "elevation_m": f.get("elevation_m"),
            "lat": f.get("lat"),
            "lon": f.get("lon"),
            "region_id": f.get("region_id", ""),
            "region_zh": f.get("region_zh", ""),
            "country_wd_id": f.get("country_wd_id", ""),
            "country_zh": f.get("country_zh", ""),
            "water_id": f.get("water_id", ""),
            "water_zh": f.get("water_zh", ""),
            "inception_year": _year_from_time(f.get("inception")),
            "capital_of_zh": f.get("capital_of_zh", ""),
            "timezone_zh": f.get("timezone_zh", ""),
            "language_zh": f.get("language_zh", ""),
            "resolved": True,
        }

    print(f"facts for {len(final)} cities; unresolved: {len(unresolved)} {unresolved[:20]}")
    for key, label in (("population", "population"), ("elevation_m", "elevation"),
                       ("inception_year", "inception"), ("water_zh", "waterbody"),
                       ("capital_of_zh", "capital-of"), ("region_zh", "admin region")):
        n = sum(1 for f in final.values() if f.get(key))
        print(f"  {label}: {n}")

    if not dry:
        FACTS_PATH.parent.mkdir(parents=True, exist_ok=True)
        FACTS_PATH.write_text(json.dumps(final, ensure_ascii=False, indent=1),
                              encoding="utf-8")
        print(f"wrote {FACTS_PATH}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
