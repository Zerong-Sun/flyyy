#!/usr/bin/env python3
"""Select and import 100 city photos linked from Wikidata P18.

Images come from Commons file pages. The output manifest retains each file's
author, license, original page and download URL for visible in-game credit.
Run after fetch_wikidata_facts.py and fill_current_city_gaps.py.
"""
from __future__ import annotations

import html
import json
import re
import time
import urllib.parse
import urllib.request
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WORLD = ROOT / "game/data/world.json"
FACTS = ROOT / "etl/content/wikidata_facts.json"
CITIES = ROOT / "etl/content/cities"
ASSETS = ROOT / "game/assets/cities"
MANIFEST = ASSETS / "photo_credits.json"
UA = "flyyy-city-content/0.2 (Wikimedia Commons attribution audit)"
ALLOWED = ("cc by", "cc0", "public domain", "pd-")
MANUAL_TITLES = {"tianjin": "天津天际线202507.jpg"}


def api(url: str, params: dict) -> dict:
    full = url + "?" + urllib.parse.urlencode(params)
    for attempt in range(5):
        try:
            request = urllib.request.Request(full, headers={"User-Agent": UA})
            with urllib.request.urlopen(request, timeout=50) as response:
                return json.load(response)
        except Exception:
            if attempt == 4:
                raise
            time.sleep(3 * (attempt + 1))
    raise AssertionError("unreachable")


def download(url: str, target: Path) -> None:
    for attempt in range(5):
        try:
            request = urllib.request.Request(url, headers={"User-Agent": UA})
            with urllib.request.urlopen(request, timeout=75) as response:
                data = response.read(8_000_001)
                if len(data) > 8_000_000:
                    raise ValueError("image exceeds 8 MB")
                target.write_bytes(data)
                return
        except Exception:
            if attempt == 4:
                raise
            time.sleep(3 * (attempt + 1))


def chunks(items: list, n: int):
    for i in range(0, len(items), n):
        yield items[i:i + n]


def image_titles(qids: list[str]) -> dict[str, list[str]]:
    out: dict[str, list[str]] = {}
    for batch in chunks(qids, 65):
        values = " ".join("wd:" + qid for qid in batch)
        query = f"SELECT ?city ?image WHERE {{ VALUES ?city {{ {values} }} ?city wdt:P18 ?image. }}"
        data = api("https://query.wikidata.org/sparql", {
            "query": query, "format": "json"})
        for row in data["results"]["bindings"]:
            qid = row["city"]["value"].rsplit("/", 1)[-1]
            title = urllib.parse.unquote(row["image"]["value"].rsplit("/", 1)[-1]).replace("_", " ")
            out.setdefault(qid, []).append(title)
        time.sleep(1)
    return out


def image_info(titles: list[str]) -> dict[str, dict]:
    out = {}
    for batch in chunks(titles, 35):
        data = api("https://commons.wikimedia.org/w/api.php", {
            "action": "query", "titles": "|".join("File:" + x for x in batch),
            "prop": "imageinfo", "iiprop": "url|size|mime|extmetadata",
            "iiurlwidth": "960", "format": "json", "formatversion": "2",
        })
        for page in data.get("query", {}).get("pages", []):
            info = (page.get("imageinfo") or [None])[0]
            if info:
                out[page["title"].removeprefix("File:")] = info
        time.sleep(1)
    return out


def metadata(info: dict) -> dict | None:
    ext = info.get("extmetadata", {})
    value = lambda key: html.unescape(re.sub(r"<[^>]+>", "", ext.get(key, {}).get("value", ""))).strip()
    license_name = value("LicenseShortName")
    low = license_name.lower()
    if not any(low.startswith(x) for x in ALLOWED) or "nc" in low or "nd" in low:
        return None
    mime = info.get("mime", "")
    if mime not in ("image/jpeg", "image/png", "image/webp"):
        return None
    if int(info.get("width", 0)) < 640 or int(info.get("height", 0)) < 360:
        return None
    artist = value("Artist") or value("Attribution") or value("Credit")
    if not artist:
        return None
    return {
        "author": artist, "license": license_name,
        "license_url": ext.get("LicenseUrl", {}).get("value", ""),
        "source_url": info.get("descriptionurl", ""),
        "download_url": info.get("thumburl") or info.get("url", ""),
        "mime": mime,
    }


def main() -> None:
    world = json.loads(WORLD.read_text(encoding="utf-8"))
    facts = json.loads(FACTS.read_text(encoding="utf-8"))
    airports = {a["iata"]: a["city_id"] for a in world["airports"]}
    scores: Counter[str] = Counter()
    for route in world["routes"]:
        for key in ("origin", "destination"):
            cid = airports.get(route.get(key, ""))
            if cid:
                scores[cid] += 1
    cities = {c["city_id"]: c for c in world["cities"]}
    qids = [f["qid"] for cid, f in facts.items() if cid in cities and f.get("qid")]
    titles_by_qid = image_titles(list(dict.fromkeys(qids)))
    titles = list(dict.fromkeys(
        [t for group in titles_by_qid.values() for t in group]
        + list(MANUAL_TITLES.values())))
    info_by_title = image_info(titles)
    print(f"Wikidata photos: {len(titles_by_qid)} city items, {len(titles)} files", flush=True)
    selected = {}
    for cid in sorted(cities, key=lambda c: (0 if c == "tianjin" else 1, -scores[c], c)):
        qid = facts.get(cid, {}).get("qid", "")
        options = [MANUAL_TITLES[cid]] if cid in MANUAL_TITLES else list(titles_by_qid.get(qid, []))
        options.sort(key=lambda x: (bool(re.search(r"montage|collage|locator|map|flag|coat", x, re.I)), x))
        for title in options:
            info = info_by_title.get(title, {})
            credit = metadata(info)
            if credit is None:
                continue
            credit["commons_file"] = title
            credit["wikidata_qid"] = qid
            credit["route_score"] = scores[cid]
            selected[cid] = credit
            break
        if len(selected) >= 100:
            break
    if len(selected) < 100:
        raise RuntimeError(f"Only {len(selected)} cities have eligible P18 photos")

    ASSETS.mkdir(parents=True, exist_ok=True)
    done = {}
    for i, (cid, credit) in enumerate(selected.items(), 1):
        ext = {"image/jpeg": ".jpg", "image/png": ".png", "image/webp": ".webp"}[credit["mime"]]
        stem = f"city_{cid}_photo_720"
        path = ASSETS / (stem + ext)
        try:
            if not path.exists():
                download(credit["download_url"], path)
        except Exception as exc:
            print(f"SKIP {cid}: {exc}", flush=True)
            continue
        source = CITIES / (cid + ".json")
        city = json.loads(source.read_text(encoding="utf-8"))
        city["image_asset_id"] = stem
        source.write_text(json.dumps(city, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        done[cid] = {k: v for k, v in credit.items() if k not in ("download_url", "mime")}
        print(f"{i:3d}/100 {cid}: {credit['license']}", flush=True)
        time.sleep(0.7)
    MANIFEST.write_text(json.dumps(done, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    if len(done) != 100:
        raise RuntimeError(f"Downloaded {len(done)}/100 photos; rerun after checking failures")
    print(f"Wrote {MANIFEST}")


if __name__ == "__main__":
    main()
