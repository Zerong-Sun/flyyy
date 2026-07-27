#!/usr/bin/env python3
"""Extract all candidate cities from OurAirports to produce a city list."""
from __future__ import annotations

import csv
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RAW = ROOT / "raw"

# Country code -> Chinese name (same as run_pipeline.py)
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
    "LU": "卢森堡", "MT": "马耳他", "CY": "塞浦路斯", "SK": "斯洛伐克",
    "SI": "斯洛文尼亚", "TN": "突尼斯", "SN": "塞内加尔", "CM": "喀麦隆",
    "AO": "安哥拉", "MZ": "莫桑比克", "ZW": "津巴布韦", "ZM": "赞比亚",
    "UG": "乌干达", "SD": "苏丹", "SY": "叙利亚", "IQ": "伊拉克",
    "AF": "阿富汗", "KZ": "哈萨克斯坦", "UZ": "乌兹别克斯坦",
    "GE": "格鲁吉亚", "AM": "亚美尼亚", "AZ": "阿塞拜疆",
    "CR": "哥斯达黎加", "PA": "巴拿马", "DO": "多米尼加",
    "CU": "古巴", "JM": "牙买加", "EC": "厄瓜多尔",
    "BO": "玻利维亚", "UY": "乌拉圭", "PY": "巴拉圭",
    "AM": "亚美尼亚", "AZ": "阿塞拜疆", "GE": "格鲁吉亚",
    "BY": "白俄罗斯",
}

def _guess_timezone(continent: str, country_id: str) -> str:
    zone_map = {
        "NA": {"US": "America/Chicago", "CA": "America/Toronto", "MX": "America/Mexico_City"},
        "SA": {"BR": "America/Sao_Paulo", "AR": "America/Argentina/Buenos_Aires",
               "CL": "America/Santiago", "CO": "America/Bogota", "PE": "America/Lima",
               "VE": "America/Caracas", "EC": "America/Guayaquil", "BO": "America/La_Paz",
               "UY": "America/Montevideo"},
        "EU": {
            "GB": "Europe/London", "DE": "Europe/Berlin", "FR": "Europe/Paris",
            "IT": "Europe/Rome", "ES": "Europe/Madrid", "NL": "Europe/Amsterdam",
            "RU": "Europe/Moscow", "TR": "Europe/Istanbul", "PL": "Europe/Warsaw",
            "SE": "Europe/Stockholm", "NO": "Europe/Oslo", "DK": "Europe/Copenhagen",
            "FI": "Europe/Helsinki", "AT": "Europe/Vienna", "BE": "Europe/Brussels",
            "IE": "Europe/Dublin", "PT": "Europe/Lisbon", "GR": "Europe/Athens",
            "CZ": "Europe/Prague", "HU": "Europe/Budapest", "CH": "Europe/Zurich",
            "UA": "Europe/Kyiv", "RO": "Europe/Bucharest", "BG": "Europe/Sofia",
            "IS": "Atlantic/Reykjavik", "HR": "Europe/Zagreb", "RS": "Europe/Belgrade",
            "LT": "Europe/Vilnius", "LV": "Europe/Riga", "EE": "Europe/Tallinn",
            "LU": "Europe/Luxembourg", "MT": "Europe/Malta", "CY": "Asia/Nicosia",
            "SK": "Europe/Bratislava", "SI": "Europe/Ljubljana",
        },
        "AS": {
            "CN": "Asia/Shanghai", "JP": "Asia/Tokyo", "KR": "Asia/Seoul",
            "IN": "Asia/Kolkata", "SG": "Asia/Singapore", "TH": "Asia/Bangkok",
            "AE": "Asia/Dubai", "HK": "Asia/Hong_Kong", "TW": "Asia/Taipei",
            "MY": "Asia/Kuala_Lumpur", "ID": "Asia/Jakarta", "PH": "Asia/Manila",
            "VN": "Asia/Ho_Chi_Minh", "SA": "Asia/Riyadh", "IL": "Asia/Jerusalem",
            "QA": "Asia/Qatar", "KW": "Asia/Kuwait", "OM": "Asia/Muscat",
            "BH": "Asia/Bahrain", "LB": "Asia/Beirut", "JO": "Asia/Amman",
            "PK": "Asia/Karachi", "BD": "Asia/Dhaka", "MM": "Asia/Yangon",
            "KH": "Asia/Phnom_Penh", "LA": "Asia/Vientiane", "MN": "Asia/Ulaanbaatar",
            "LK": "Asia/Colombo", "NP": "Asia/Kathmandu", "AM": "Asia/Yerevan",
            "AZ": "Asia/Baku", "GE": "Asia/Tbilisi", "KZ": "Asia/Almaty",
            "UZ": "Asia/Tashkent", "SY": "Asia/Damascus", "IQ": "Asia/Baghdad",
            "IR": "Asia/Tehran", "CY": "Asia/Nicosia",
        },
        "AF": {"ZA": "Africa/Johannesburg", "EG": "Africa/Cairo", "NG": "Africa/Lagos",
               "KE": "Africa/Nairobi", "MA": "Africa/Casablanca", "ET": "Africa/Addis_Ababa",
               "GH": "Africa/Accra", "TZ": "Africa/Dar_es_Salaam", "DZ": "Africa/Algiers",
               "TN": "Africa/Tunis", "SN": "Africa/Dakar", "CM": "Africa/Douala",
               "AO": "Africa/Luanda", "MZ": "Africa/Maputo", "ZW": "Africa/Harare",
               "ZM": "Africa/Lusaka", "UG": "Africa/Kampala", "SD": "Africa/Khartoum",
               "CI": "Africa/Abidjan"},
        "OC": {"AU": "Australia/Sydney", "NZ": "Pacific/Auckland"},
    }
    cont = zone_map.get(continent, {})
    return cont.get(country_id, "UTC")

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

EXISTING_HUBS = {
    "ATL", "DXB", "DFW", "DEN", "LHR", "ORD", "IST", "LAX", "HND", "PVG",
    "CDG", "AMS", "CAN", "FRA", "PEK", "SIN", "ICN", "HKG", "BKK", "MIA"
}

def main():
    oa = read_ourairports_by_iata(RAW / "airports.csv")
    rf_path = RAW / "routes.dat"
    openflights_iatas: set[str] = set()
    if rf_path.exists():
        with rf_path.open(encoding="utf-8", newline="") as f:
            for line in f:
                parts = line.strip().split(",")
                if len(parts) >= 5:
                    src = parts[2].strip()
                    dst = parts[4].strip()
                    if src: openflights_iatas.add(src)
                    if dst: openflights_iatas.add(dst)

    candidates = []
    for iata, info in oa.items():
        if iata in EXISTING_HUBS:
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
        if atype == "large_airport": score += 50
        elif atype == "medium_airport": score += 30
        candidates.append((score, iata, info))

    candidates.sort(key=lambda x: (-x[0], x[1]))

    seen_city_ids: set[str] = set()
    results = []
    for score, iata, info in candidates:
        municipality = info["municipality"] or info["name"] or iata
        city_id = municipality.lower().replace(" ", "_").replace("/", "_").replace("-", "_")[:30]
        if city_id in seen_city_ids:
            continue
        seen_city_ids.add(city_id)
        country_id = info.get("iso_country", "XX")
        country_zh = COUNTRY_ZH.get(country_id, "未知")
        timezone = _guess_timezone(info.get("continent", ""), country_id)
        
        results.append({
            "city_id": city_id,
            "iata": iata,
            "municipality": municipality,
            "country_id": country_id,
            "country_zh": country_zh,
            "continent": info.get("continent", ""),
            "timezone": timezone,
            "has_routes": iata in openflights_iatas,
        })
        if len(results) >= 480:
            break

    import json
    out_path = Path(__file__).parent / "city_list.json"
    out_path.write_text(json.dumps(results, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"Wrote {len(results)} cities to {out_path}")
    
    # Stats
    by_country = {}
    for r in results:
        c = r["country_zh"]
        by_country[c] = by_country.get(c, 0) + 1
    for country, count in sorted(by_country.items(), key=lambda x: -x[1])[:20]:
        print(f"  {country}: {count}")

if __name__ == "__main__":
    main()
