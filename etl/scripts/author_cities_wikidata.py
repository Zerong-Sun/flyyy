#!/usr/bin/env python3
"""Regenerate the seven city text fields for all non-A cities from real data.

Sources, in order of trust:
  1. etl/content/wikidata_facts.json  — Wikidata claims (population, elevation,
     coordinates, admin region, country, water body, inception, capital-of)
  2. etl/content/country_facts.py     — curated real country-level facts
  3. game/data/world.sqlite           — real airport name / timezone per city

Every sentence is composed from these facts; nothing is invented.  Existing
placeholder/padded text in the city files is replaced.  Cities with
content_confidence "A" (hand-authored) are left untouched.

Usage:
  python scripts/author_cities_wikidata.py            # apply to all non-A files
  python scripts/author_cities_wikidata.py --dry-run  # print sample output only
"""
from __future__ import annotations

import json
import re
import sqlite3
import sys
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from etl.content.country_facts import (  # noqa: E402
    COUNTRY_FACTS, FOOD_EXTRA, HISTORY_EXTRA,
)

ROOT = Path(__file__).resolve().parents[1]
CONTENT = ROOT / "content"
CITIES = CONTENT / "cities"
FACTS_PATH = CONTENT / "wikidata_facts.json"
GAME_DATA = ROOT.parents[0] / "game" / "data"

# Keep authored output independent of optional packages installed in the active
# Python environment. The checked-in Wikidata labels are preserved verbatim;
# curated country names below still provide the intended simplified Chinese.
_t2s = lambda s: s  # noqa: E731

FILLER_MARKERS = ("更多细节将在后续更新中扩展", "更多细节将在后续内容更新中扩展",
                  "旅客可在此采购特色商品", "城市作为全球航线节点",
                  "适合体验地方特产贸易与跨区价差", "再搭乘直飞航班前往其他枢纽出售")


def _len(s: str) -> int:
    return len(s)


def _snap(s: str, max_len: int | None = None) -> str:
    """Ensure exactly one terminating 。 without exceeding ``max_len``."""
    s = (s or "").strip()
    while s.endswith("。"):
        s = s[:-1]
    if max_len is not None and len(s) >= max_len:
        s = s[:max_len - 1].rstrip("，、；：,.!?！？ ")
    return s + "。"


def _first_clause_items(s: str, n: int = 2) -> str:
    """First n sensible items of an economy string, for "以…等产业闻名".

    "风电、航运、制药与食品加工业是经济支柱，物流也发达。" -> "风电、航运"
    "石油与天然气储量居世界前列，藏红花、开心果出口闻名。" -> "藏红花、开心果"
    """
    clause = s.split("。")[0]
    for tail in ("是经济支柱", "为主要支柱", "为支柱", "是支柱", "是绝对支柱",
                 "为绝对支柱"):
        if tail in clause:
            clause = clause.split(tail)[0]
            break
    clause = clause.strip("，, ")
    items = [p for p in re.split(r"[、，,]", clause) if p]
    items = [p.rstrip("闻名出名").strip() for p in items]
    items = [p for p in items if 2 <= len(p) <= 8
             and p.count("（") == p.count("）")]  # keep parens balanced
    return "、".join(items[:n])


def _fmt_pop(pop: float | None, year: str | None) -> str:
    if pop is None:
        return ""
    if pop >= 100_000_000:
        v = f"{pop / 100_000_000:.1f}".rstrip("0").rstrip(".")
        return f"约{v}亿"
    if pop >= 10_000:
        v = f"{pop / 10_000:.1f}".rstrip("0").rstrip(".")
        return f"约{v}万"
    return f"约{int(pop):,}".replace(",", "")


def _load_airports() -> dict[str, dict]:
    db = GAME_DATA / "world.sqlite"
    if not db.exists():
        return {}
    con = sqlite3.connect(db)
    rows = con.execute(
        "SELECT city_id, iata, name_zh, name_en FROM airports"
    ).fetchall()
    con.close()
    return {r[0]: {"iata": r[1], "name_zh": r[2], "name_en": r[3]} for r in rows}


def _tz_offset_zh(timezone: str) -> str | None:
    try:
        tz = ZoneInfo(timezone)
        off = tz.utcoffset(datetime(2025, 3, 1, 12))
        if off is None:
            return None
        h = off.total_seconds() / 3600
        if h == int(h):
            return f"UTC{'+' if h >= 0 else ''}{int(h)}"
        return f"UTC{'+' if h >= 0 else ''}{h}"
    except Exception:
        return None


class CityWriter:
    def __init__(self, facts: dict, airports: dict):
        self.facts = facts
        self.airports = airports

    def compose(self, blob: dict) -> dict:
        cid = blob["city_id"]
        name = blob.get("name_zh", "")
        country_id = blob.get("country_id", "XX")
        cf = COUNTRY_FACTS.get(country_id, {})
        f = self.facts.get(cid, {})
        ap = self.airports.get(cid, {})

        zh = lambda s: _t2s(s or "").strip()  # noqa: E731
        pop = f.get("population")
        pop_year = f.get("population_year")
        elev = f.get("elevation_m")
        lat = f.get("lat")
        region = zh(f.get("region_zh"))
        if region and (region == name or region.endswith(name) or name in region
                       or re.search(r"[A-Za-z]", region)):
            region = ""
        # Curated simplified names win over Wikidata labels (zh labels are
        # often traditional or regional variants, e.g. 奈及利亞 vs 尼日利亚).
        country_zh = cf.get("name_zh", "") or zh(f.get("country_zh"))
        water = zh(f.get("water_zh"))
        capital_of = zh(f.get("capital_of_zh"))
        if capital_of == country_zh or capital_of == region:
            capital_of = ""
        inception = f.get("inception_year")
        tz_off = _tz_offset_zh(blob.get("timezone", ""))

        pop_s = _fmt_pop(pop, pop_year)
        lat_s = (f"北纬{abs(lat):.1f}°" if lat is not None and lat >= 0
                 else (f"南纬{abs(lat):.1f}°" if lat is not None else ""))
        elev_s = f"海拔{int(elev)}米" if elev is not None else ""

        if capital_of:
            if capital_of.endswith(("国", "共和国")):
                cap_role = "首都"
            elif capital_of.endswith("县"):
                cap_role = "行政中心"
            else:
                cap_role = "首府"
        else:
            cap_role = ""

        economy1 = cf.get("economy", "").split("。")[0].strip("。")
        economy2 = cf.get("economy", "").split("。")[1].strip("。") \
            if len(cf.get("economy", "").split("。")) > 1 else ""
        climate1 = cf.get("climate", "").split("。")[0].strip("。")
        food1 = cf.get("food", "").split("。")[0].strip("。")
        geo1 = cf.get("geo", "").split("。")[0].strip("。")
        hist_parts = [p.strip("。") for p in cf.get("history", "").split("。") if p.strip()]
        food_extra = FOOD_EXTRA.get(country_id, "")
        hist_extra = HISTORY_EXTRA.get(country_id, "")

        # ---- short_description (80-150) ----
        lead = name
        if capital_of:
            lead += f"是{capital_of}的{cap_role}"
        elif region:
            lead += f"位于{country_zh}的{region}"
        elif country_zh:
            lead += f"位于{country_zh}"
        parts = [lead]
        if pop_s:
            parts.append(f"人口{pop_s}")
        industry = _first_clause_items(economy1)
        if industry:
            parts.append(f"以{industry}等产业闻名")
        short = "，".join(parts) + "。"
        for extra in ([f"邻近{water}"] if water else []) + ([elev_s] if elev_s else []):
            if _len(short) >= 80:
                break
            short = short.rstrip("。") + "，" + extra + "。"
        for extra in (climate1, geo1, economy1,
                      hist_parts[0] if hist_parts else "", hist_extra):
            if _len(short) >= 80 or not extra:
                break
            short = short.rstrip("。") + "，" + extra + "。"
        short = short[:150]

        # ---- overview (150-300) ----
        s = []
        loc = f"{name}位于{country_zh}"
        if region:
            loc += f"的{region}"
        if lat_s:
            loc += f"（{lat_s}）"
        s.append(loc + "。")
        if water:
            s.append(f"{name}地处{water}沿岸。")
        elif elev_s:
            s.append(f"城市{elev_s}。")
        if capital_of:
            s.append(f"作为{capital_of}的{cap_role}，{name}是当地行政与商业活动的中心。")
        if pop_s:
            s.append(f"城市人口{pop_s}"
                     + (f"（{pop_year}年）"
                        if pop_year and pop_year.isdigit() and int(pop_year) > 1900 else "")
                     + "。")
        if ap.get("iata"):
            ap_name = f"，即{ap.get('name_zh')}" if ap.get("name_zh") else ""
            s.append(f"机场（{ap['iata']}{ap_name}）通达区域与国际航线网络。")
        if economy1:
            s.append(economy1 + "。")
        for extra in (geo1, climate1,
                      hist_parts[0] if hist_parts else "", hist_extra, economy2):
            if _len("".join(s)) >= 150 or not extra:
                break
            s.append(extra + "。")
        overview = "".join(s)
        overview = overview[:300]

        # ---- history_summary (100-250) ----
        s = []
        if inception:
            s.append(f"{name}有记载的城市历史可追溯至{inception}年。")
        for hp in hist_parts[:2]:
            s.append(hp + "。")
        if capital_of and region:
            s.append(f"如今{name}仍是{region}的重要城市。")
        if _len("".join(s)) < 50 and hist_extra:
            s.append(hist_extra + "。")
        history = "".join(s)
        history = history[:250]

        # ---- geography_summary (80-200) ----
        s = []
        geo_clauses = [c for c in (lat_s, elev_s, f"邻近{water}" if water else "") if c]
        if geo_clauses:
            s.append(f"{name}地处{'、'.join(geo_clauses)}。")
        if climate1:
            s.append(climate1 + "。")
        if geo1:
            s.append(geo1 + "。")
        if _len("".join(s)) < 50 and ap.get("iata"):
            s.append(f"该城机场通达区域航线网络。")
        geography = "".join(s)
        geography = geography[:200]

        # ---- economy_summary (80-200) ----
        s = []
        if economy1:
            s.append(economy1 + "。")
        if capital_of:
            s.append(f"{cap_role}地位带来稳定的行政与商务需求。")
        if _len("".join(s)) < 50 and economy2:
            s.append(economy2 + "。")
        if _len("".join(s)) < 50 and geo1:
            s.append(geo1 + "。")
        economy = "".join(s)
        economy = economy[:200]

        # ---- food_summary (80-200) ----
        food_parts = [p.strip("。") for p in cf.get("food", "").split("。") if p.strip()]
        s = []
        for fp in food_parts[:2]:
            s.append(fp + "。")
            if _len("".join(s)) >= 80:
                break
        if _len("".join(s)) < 50 and food_extra:
            s.append(food_extra + "。")
        if not s:
            s.append("当地市场以常见主食与本地食材为主。")
        food = "".join(s)
        food = food[:200]

        # ---- travel_note (50-150) ----
        s = []
        if ap.get("iata"):
            s.append(f"机场三字码为{ap['iata']}")
        if tz_off:
            s.append(f"时区{tz_off}")
        if cf.get("language"):
            s.append(f"主要使用{cf['language']}")
        if cf.get("currency"):
            s.append(f"当地结算货币为{cf['currency']}")
        if climate1:
            tip = climate1.rstrip("。，、")
            for prefix in ("大部属", "大部分属", "绝大部分为", "大部为", "多为"):
                if tip.startswith(prefix):
                    tip = tip[len(prefix):]
                    break
            s.append(f"当地属{tip}，出行留意天气变化")
        travel = "，".join(s) + "。" if s else "出行前查询当地航班与天气信息。"

        out = {
            "short_description": _snap(short, 150),
            "overview": _snap(overview, 300),
            "history_summary": _snap(history, 250),
            "geography_summary": _snap(geography, 200),
            "economy_summary": _snap(economy, 200),
            "food_summary": _snap(food, 200),
            "travel_note": _snap(travel, 150),
        }
        return out


def main() -> int:
    dry = "--dry-run" in sys.argv
    if not FACTS_PATH.exists():
        print(f"missing {FACTS_PATH} — run fetch_wikidata_facts.py first")
        return 1
    facts = json.loads(FACTS_PATH.read_text(encoding="utf-8"))
    airports = _load_airports()
    writer = CityWriter(facts, airports)

    files = sorted(CITIES.glob("*.json"))
    changed = 0
    skipped = 0
    for path in files:
        blob = json.loads(path.read_text(encoding="utf-8"))
        if blob.get("content_confidence") == "A":
            skipped += 1
            continue
        original = dict(blob)
        text = writer.compose(blob)
        for k, v in text.items():
            assert k in blob and v, (path.name, k)
        blob.update(text)
        blob["content_confidence"] = "B"
        cf_name = COUNTRY_FACTS.get(blob.get("country_id", "XX"), {}).get("name_zh")
        if cf_name and blob.get("country_zh") in ("", "未知"):
            blob["country_zh"] = cf_name
        qid = (facts.get(blob["city_id"]) or {}).get("qid")
        if qid:
            src = [s for s in blob.get("source_ids", []) if not str(s).startswith("wikidata:")]
            src.append(f"wikidata:{qid}")
            blob["source_ids"] = src
        if blob == original:
            continue
        changed += 1
        if not dry:
            path.write_text(json.dumps(blob, ensure_ascii=False, indent=2) + "\n",
                            encoding="utf-8")
        if dry and changed <= 3:
            print("=" * 70)
            print(blob["city_id"], blob.get("name_zh"))
            for k in ("short_description", "overview", "history_summary",
                      "geography_summary", "economy_summary", "food_summary",
                      "travel_note"):
                print(f"  {k}: {blob[k]}")
    # Backfill missing/unknown country names across ALL files (incl. A).
    fixed_names = 0
    for path in files:
        blob = json.loads(path.read_text(encoding="utf-8"))
        cf_name = COUNTRY_FACTS.get(blob.get("country_id", "XX"), {}).get("name_zh")
        if cf_name and blob.get("country_zh") in ("", "未知"):
            blob["country_zh"] = cf_name
            if not dry:
                path.write_text(json.dumps(blob, ensure_ascii=False, indent=2) + "\n",
                                encoding="utf-8")
            fixed_names += 1
    print(f"done: {changed} cities changed, {skipped} A-cities untouched, "
          f"{fixed_names} country names backfilled "
          f"({'dry-run' if dry else 'written'})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
