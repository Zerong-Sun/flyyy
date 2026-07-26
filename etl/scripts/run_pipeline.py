#!/usr/bin/env python3
"""Full Demo ETL: hubs → routes → flights → cities/products → markets → SQLite + JSON for Godot."""
from __future__ import annotations

import csv
import hashlib
import json
import math
import random
import sqlite3
import sys
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[1]
CFG = ROOT / "config"
RAW = ROOT / "raw"
OUT = ROOT / "out"
CONTENT = ROOT / "content"
GAME_DATA = ROOT.parents[0] / "game" / "data"

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
            }
    return out


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


# Products authored in etl/content/products/{city_id}.yaml (trade contracts for Demo).


def load_city_product_rows(city_id: str) -> list[dict]:
    path = CONTENT / "products" / f"{city_id}.yaml"
    data = load_yaml(path)
    rows = data.get("products") or []
    assert len(rows) >= 5, f"{city_id}: need >=5 products in {path}"
    return rows


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


def build_airports(hubs_cfg: dict, oa: dict[str, dict]) -> list[dict]:
    airports = []
    fallback = hubs_cfg["fallback_coords"]
    for h in hubs_cfg["hubs"]:
        iata = h["iata"]
        src = oa.get(iata, {})
        fb = fallback[iata]
        lat = float(src.get("lat", fb["lat"]))
        lon = float(src.get("lon", fb["lon"]))
        elev = float(src.get("elev_ft", fb["elev_ft"]))
        if abs(lat) < 1e-6 and abs(lon) < 1e-6:
            lat, lon, elev = fb["lat"], fb["lon"], fb["elev_ft"]
        airports.append(
            {
                "airport_id": iata.lower(),
                "iata": iata,
                "icao": h["icao"],
                "name_zh": h["name_zh"],
                "name_en": h["name_en"],
                "city_id": h["city_id"],
                "city_zh": h["city_zh"],
                "city_en": h["city_en"],
                "country_id": h["country_id"],
                "country_zh": h["country_zh"],
                "timezone": h["timezone"],
                "latitude": lat,
                "longitude": lon,
                "elevation_ft": elev,
                "type": src.get("type", "large_airport"),
                "has_scheduled_service": True,
                "data_confidence": "B",
            }
        )
    return airports


def ensure_route_degree(
    edges: set[tuple[str, str]], iatas: list[str], min_deg: int, airports_by_iata: dict[str, dict]
) -> set[tuple[str, str]]:
    # undirected complement then orient both ways for travel
    undirected = {frozenset(e) for e in edges}
    for a in iatas:
        neighbors = {b for b in iatas if b != a and frozenset((a, b)) in undirected}
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
    # materialize directed both ways
    out: set[tuple[str, str]] = set()
    for pair in undirected:
        x, y = tuple(pair)
        out.add((x, y))
        out.add((y, x))
    return out


def synth_flights(
    routes: set[tuple[str, str]],
    airports_by_iata: dict[str, dict],
    eco: dict,
) -> list[dict]:
    tcfg = eco["ticket"]
    fcfg = eco["flight_synth"]
    start = date.fromisoformat(fcfg["schedule_start"])
    days = int(fcfg["schedule_days"])
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
        airline = AIRLINES[rr.randrange(len(AIRLINES))]
        demand = rr.uniform(tcfg["demand_factor_min"], tcfg["demand_factor_max"])
        base = (
            tcfg["c_route"]
            + dist * tcfg["c_km"]
            + tcfg["airport_fee_default"] * 2
        ) * tcfg["airline_factor_default"] * demand
        for day_i in range(days):
            day = start + timedelta(days=day_i)
            for slot in range(per_day):
                rng = stable_rand("flight", origin, dest, day.isoformat(), slot)
                hour = 6 + (slot * (14 // max(1, per_day))) + rng.randint(0, 2)
                minute = rng.choice([0, 10, 20, 30, 40, 50])
                hour = min(22, hour)
                dep_local_naive = datetime(day.year, day.month, day.day, hour, minute)
                # store as UTC-ish naive ISO; game applies timezone display separately
                # Use approximate fixed offsets via zoneinfo if available
                dep_utc = localize_to_utc(dep_local_naive, oa["timezone"])
                arr_utc = dep_utc + timedelta(minutes=duration)
                rnd = rng.uniform(tcfg["random_factor_min"], tcfg["random_factor_max"])
                p_eco = round(base * rnd, 2)
                p_biz = round(p_eco * tcfg["business_multiplier"], 2)
                fn = f"{airline[0]}{100 + (hash((origin, dest, day_i, slot)) % 900)}"
                fid += 1
                flights.append(
                    {
                        "flight_instance_id": f"F{fid:06d}",
                        "marketing_flight_number": fn,
                        "operating_airline_id": airline[0],
                        "marketing_airline_id": airline[0],
                        "airline_name": airline[1],
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
                        "baggage_allowance_economy": tcfg["baggage_economy_kg"],
                        "baggage_allowance_business": tcfg["baggage_business_kg"],
                        "cabin_business_available": True,
                        "data_source": "synthetic_openflights",
                        "data_confidence": "C",
                    }
                )
    return flights


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


def load_city_blurb(city_id: str) -> dict:
    path = CONTENT / "cities" / f"{city_id}.json"
    data = json.loads(path.read_text(encoding="utf-8"))
    return data


def build_cities_products(hubs_cfg: dict, eco: dict) -> tuple[list[dict], list[dict], list[dict]]:
    cities = []
    products = []
    markets = []
    for h in hubs_cfg["hubs"]:
        cid = h["city_id"]
        blur = load_city_blurb(cid)
        cities.append(
            {
                "city_id": cid,
                "name_zh": blur.get("name_zh", h["city_zh"]),
                "name_en": blur.get("name_en", h["city_en"]),
                "country_id": blur.get("country_id", h["country_id"]),
                "country_zh": blur.get("country_zh", h["country_zh"]),
                "timezone": blur.get("timezone", h["timezone"]),
                "short_description": blur["short_description"][:150],
                "overview": blur["overview"],
                "history_summary": blur["history_summary"],
                "geography_summary": blur["geography_summary"],
                "economy_summary": blur["economy_summary"],
                "food_summary": blur["food_summary"],
                "travel_note": blur["travel_note"],
                "content_confidence": blur.get("content_confidence", "B"),
            }
        )
        for p in load_city_product_rows(cid):
            weight = float(p["weight_kg"])
            products.append(
                {
                    "product_id": p["product_id"],
                    "name_zh": p["name_zh"],
                    "category": p["category"],
                    "origin_city_id": cid,
                    "origin_country_id": h["country_id"],
                    "weight_kg": weight,
                    "volume_l": round(weight * 1.2, 2),
                    "base_reference_price": float(p["base_reference_price"]),
                    "reference_currency": p.get("reference_currency", "USD"),
                    "shelf_life_hours": p["shelf_life_hours"],
                    "fragility": float(p.get("fragility", 0.0)),
                    "rarity": float(p["rarity"]),
                    "description": p["description"],
                    "price_confidence": "C",
                }
            )
    # markets: every product in every city
    mcfg = eco["market"]
    city_ids = [h["city_id"] for h in hubs_cfg["hubs"]]
    city_country = {h["city_id"]: h["country_id"] for h in hubs_cfg["hubs"]}
    for city_id in city_ids:
        cpl = COUNTRY_PRICE_LEVEL.get(city_country[city_id], 1.0)
        for prod in products:
            origin = prod["origin_city_id"]
            is_origin = origin == city_id
            supply = mcfg["origin_supply_bonus"] if is_origin else 1.0
            scarcity = 1.0
            if not is_origin:
                scarcity = 1.0 + (prod["rarity"] * (mcfg["scarcity_remote_bonus"] - 1.0))
                if city_country[city_id] == prod["origin_country_id"]:
                    scarcity *= 0.9
            buy = prod["base_reference_price"] * cpl * supply * mcfg["retail_markup"]
            sell = prod["base_reference_price"] * cpl * scarcity * (1.0 - mcfg["buy_sell_spread"] * 0.5)
            if is_origin:
                sell = buy * (1.0 - mcfg["buy_sell_spread"])
            else:
                # ensure remote sell can exceed origin buy on average
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
          has_scheduled_service INTEGER, data_confidence TEXT
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
            "INSERT INTO airports VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
            (
                a["airport_id"], a["iata"], a["icao"], a["name_zh"], a["name_en"],
                a["city_id"], a["city_zh"], a["city_en"], a["country_id"], a["country_zh"],
                a["timezone"], a["latitude"], a["longitude"], a["elevation_ft"], a["type"],
                1 if a["has_scheduled_service"] else 0, a["data_confidence"],
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


def export_json_for_godot(airports, routes, flights, cities, products, markets, eco, meta, tz_offsets, product_market_tags):
    GAME_DATA.mkdir(parents=True, exist_ok=True)
    payload = {
        "meta": meta,
        "economy": {
            "starting_cash_usd": eco["starting_cash_usd"],
            "fx_usd_cny": eco["fx"]["USD_CNY"],
            "baggage_extras": eco["baggage_extras"],
            "ticket": eco["ticket"],
            "market": eco["market"],
            "carry_on_kg": eco["ticket"]["carry_on_kg"],
        },
        "airports": airports,
        "routes": [{"origin": o, "destination": d} for o, d in sorted(routes)],
        "cities": cities,
        "products": products,
        "markets": markets,
        "product_market_tags": product_market_tags,
        "tz_offsets": tz_offsets,
        "airlines": [{"id": a, "name": n} for a, n in AIRLINES],
        "attributions": [
            {"name": "OurAirports", "license": "Unlicense", "note": "Airport coordinates"},
            {"name": "OpenFlights", "license": "ODbL", "note": "Route seed for synthetic schedules"},
            {"name": "Game content", "license": "original", "note": "City and product texts"},
        ],
        "disclaimer": "航班网络基于公开航空数据重建，不代表真实购票信息。",
    }
    (GAME_DATA / "world.json").write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    by_origin: dict[str, list] = {}
    for fl in flights:
        by_origin.setdefault(fl["origin_airport_id"], []).append(fl)
    for lst in by_origin.values():
        lst.sort(key=lambda x: x["scheduled_departure_utc"])
    (GAME_DATA / "flights.json").write_text(
        json.dumps({"by_origin": by_origin, "flight_count": len(flights)}, ensure_ascii=False),
        encoding="utf-8",
    )
    # also copy sqlite
    import shutil

    shutil.copy2(OUT / "world.sqlite", GAME_DATA / "world.sqlite")
    shutil.copy2(OUT / "flights_2025_03.sqlite", GAME_DATA / "flights_2025_03.sqlite")


def validate(airports, routes, flights, cities, products) -> None:
    iatas = {a["iata"] for a in airports}
    assert len(airports) == 20
    assert len(iatas) == 20
    for a in airports:
        assert -90 <= a["latitude"] <= 90
        assert -180 <= a["longitude"] <= 180
        assert not (abs(a["latitude"]) < 1e-6 and abs(a["longitude"]) < 1e-6)
    # degree
    for a in iatas:
        deg = sum(1 for o, d in routes if o == a)
        assert deg >= 8, f"{a} degree {deg}"
    for fl in flights:
        assert fl["origin_iata"] != fl["destination_iata"]
        assert fl["scheduled_arrival_utc"] > fl["scheduled_departure_utc"]
        assert fl["ticket_base_price_economy"] > 0
        assert abs(fl["ticket_base_price_business"] - fl["ticket_base_price_economy"] * 10) < 0.02
    assert len(cities) == 20
    by_city = {}
    for p in products:
        by_city.setdefault(p["origin_city_id"], 0)
        by_city[p["origin_city_id"]] += 1
    for cid, n in by_city.items():
        assert n >= 5, cid
    for c in cities:
        assert len(c["short_description"]) >= 80, c["city_id"]
        assert len(c["overview"]) >= 150, c["city_id"]
    print(f"VALIDATION OK: {len(airports)} airports, {len(routes)} directed routes, {len(flights)} flights")


def main() -> int:
    hubs_cfg = load_yaml(CFG / "hubs_20.yaml")
    eco = load_yaml(CFG / "economy.yaml")
    oa = read_ourairports_by_iata(RAW / "airports.csv")
    airports = build_airports(hubs_cfg, oa)
    by_iata = {a["iata"]: a for a in airports}
    iatas = [a["iata"] for a in airports]
    edges = read_openflights_routes(RAW / "routes.dat", set(iatas))
    routes = ensure_route_degree(edges, iatas, eco["flight_synth"]["min_destinations_per_hub"], by_iata)
    flights = synth_flights(routes, by_iata, eco)
    cities, products, markets = build_cities_products(hubs_cfg, eco)

    # Build product_market_tags: for each (origin_city, product_id), classify
    # every destination city as hot / normal / cold based on sell_buy_ratio.
    product_market_tags: dict[str, dict] = {}
    market_index: dict[tuple, dict] = {}
    for m in markets:
        market_index[(m["city_id"], m["product_id"])] = {
            "buy": m["buy_base_usd"],
            "sell": m["sell_base_usd"],
        }

    city_ids = [c["city_id"] for c in cities]
    for origin_city in city_ids:
        for product in products:
            product_id = product["product_id"]
            key = f"{origin_city}|{product_id}"
            product_market_tags[key] = {"hot": [], "normal": [], "cold": []}
            buy_origin = market_index[(origin_city, product_id)]["buy"]

            for dest_city in city_ids:
                sell_remote = market_index[(dest_city, product_id)]["sell"]
                sell_buy_ratio = sell_remote / buy_origin if buy_origin > 0 else 1.0

                if sell_buy_ratio >= 1.15:
                    tag = "hot"
                elif sell_buy_ratio >= 1.0:
                    tag = "normal"
                else:
                    tag = "cold"

                product_market_tags[key][tag].append(dest_city)

    tz_offsets = build_tz_offsets(hubs_cfg, int(eco["flight_synth"]["schedule_days"]))
    meta = {
        "etl_version": "0.2.0",
        "baseline_date": "2025-03-01",
        "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "flight_count": len(flights),
        "route_count": len(routes),
        "disclaimer": "synthetic schedules from open route data",
    }
    validate(airports, routes, flights, cities, products)
    write_sqlite(airports, routes, flights, cities, products, markets, eco, meta)
    export_json_for_godot(airports, routes, flights, cities, products, markets, eco, meta, tz_offsets, product_market_tags)
    digest = hashlib.sha256((OUT / "world.sqlite").read_bytes()).hexdigest()
    print(f"Wrote {OUT}/world.sqlite and flights; world hash={digest[:16]}...")
    print(f"Godot data -> {GAME_DATA}")
    # sanity: US DST flip around 2025-03-09
    ny = tz_offsets.get("America/New_York", {})
    if "2025-03-08" in ny and "2025-03-10" in ny:
        print(f"America/New_York offset Mar8={ny['2025-03-08']} Mar10={ny['2025-03-10']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
