#!/usr/bin/env python3
"""Author every missing city file in the current 500-city game roster.

Existing authored files are preserved. New prose combines city-specific
Wikidata claims with explicitly labelled country context; no filler sentences
or arbitrary population figures are introduced.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

from author_cities_wikidata import CityWriter, _load_airports

ROOT = Path(__file__).resolve().parents[2]
WORLD = ROOT / "game/data/world.json"
FACTS = ROOT / "etl/content/wikidata_facts.json"
CITIES = ROOT / "etl/content/cities"
NAMES = ROOT / "etl/config/city_name_zh.json"
HISTORY = ROOT / "etl/config/city_history_overrides.json"

# Airport municipalities sometimes differ from the metropolis they serve.
# These names are attached to the actual playable airport, not to an invented
# second copy of the larger city.
NAME_OVERRIDES = {
    "tianjin": "天津", "narita": "成田", "taoyuan": "桃园",
    "rinas": "里纳斯", "ilinden": "伊林登",
    "shanghai_(minhang)": "上海（虹桥）",
    "paris_(orly,_val_de_marne)": "巴黎（奥利）",
    "london,_essex": "伦敦（斯坦斯特德）", "pendik,_istanbul": "彭迪克",
    "luton,_luton": "卢顿", "segrate_(mi)": "塞格拉泰",
    "treviso_(tv)": "特雷维索", "nyköping": "尼雪平",
    "nowy_dwór_mazowiecki": "诺维德武尔-马佐维茨基",
    "nossa_senhora_do_carmo": "澳门（氹仔）",
}

COUNTRY_NAME_OVERRIDES = {
    "MT": "马耳他", "PR": "波多黎各", "MO": "中国澳门", "LU": "卢森堡",
    "SX": "荷属圣马丁", "PF": "法属波利尼西亚", "SI": "斯洛文尼亚",
    "VI": "美属维尔京群岛", "TC": "特克斯和凯科斯群岛", "GP": "瓜德罗普",
}

# For places absent from the older country-context table, name the national or
# territorial dish as such. These are context for a traveller, not a claim that
# each dish originated within the airport municipality.
FOOD_CONTEXT = {
    "IL": "鹰嘴豆泥与沙拉三明治", "KW": "香料米饭马奇布斯",
    "MT": "酥皮点心帕斯蒂齐", "PA": "炖汤桑科乔",
    "OM": "慢烤肉舒瓦", "PR": "青蕉泥莫丰戈",
    "LV": "黑麦面包与培根卷皮拉吉", "MO": "葡式蛋挞",
    "CR": "米豆饭加洛平托", "LU": "熏猪颈肉配蚕豆",
    "LT": "土豆肉馅团塞佩利奈", "SX": "加勒比海鲜与海螺菜",
    "BY": "土豆煎饼德拉尼基", "SV": "玉米饼普普萨",
    "PG": "地炉蒸食穆穆", "AO": "棕榈油炖鸡穆安巴",
    "FJ": "椰奶腌鱼科科达", "MU": "鹰嘴豆薄饼多尔普里",
    "SD": "蚕豆泥富尔", "PF": "椰奶生鱼波瓦松克鲁",
    "EE": "黑麦面包与血肠", "AL": "酥皮馅饼拜雷克",
    "TT": "鹰嘴豆夹饼达布尔斯", "ZM": "玉米糊恩希马",
    "SI": "核桃卷波蒂察", "VI": "秋葵叶炖菜卡拉卢",
    "TC": "海螺料理", "GP": "炸面包夹馅博基特",
    "VU": "芋叶烤食拉普拉普", "MG": "木薯叶炖肉拉维托托",
    "GA": "棕榈果酱鸡肉", "MK": "烤豆塔夫切格拉夫切",
    "UY": "牛排三明治奇维托",
}

# Airport-led entries without a reliable municipality match in the automated
# Wikidata join need local, reviewed copy instead of national-level prose.
FEATURED_UPDATES = {
    "newark": {
        "short_description": "纽瓦克位于新泽西州，沿帕塞伊克河发展，距纽约都会区很近。工业、港口和移民社区共同塑造了它；铁界区的葡萄牙点心与烤肉，是在城里认识当地饮食的好入口。",
        "overview": "纽瓦克是新泽西州的重要城市，帕塞伊克河与纽瓦克湾连接了它的工业和运输史。1666年的聚落逐渐发展为皮革、金属加工和商业中心。今天从纽瓦克自由国际机场入城，可以把河滨公园、剧院与铁界区排在同一段行程里：一边看交通枢纽，一边看移民文化留下的餐桌和街巷。",
        "history_summary": "纽瓦克的建城故事可追溯到1666年。18世纪皮革加工兴起，随后又有金属制造、保险和商业活动。城市工业化与帕塞伊克河的运输位置密切相关；如今的市中心仍能看到旧产业和新文化场所并存。",
        "economy_summary": "纽瓦克早期以皮革、鞋靴和金属加工闻名，后来成为北新泽西的商业中心。机场、港口与城市交通维系着今天的物流功能，剧院和餐饮街区也为本地经济带来另一种活力。",
        "food_summary": "铁界区聚集了葡萄牙、巴西和西班牙风味餐馆。可以从葡式蛋挞配咖啡开始，再尝烤肉或海鲜；当地的葡萄牙节庆也让这一街区的饮食传统走出餐馆，来到街头。",
        "culture_note": "纽瓦克铁界区的葡萄牙节会把音乐、游行和食物带到街上。蛋挞与烤肉之所以成为城市名片，背后是数代移民把家乡习惯带进新泽西的过程。",
        "source_ids": ["https://www.newarknj.gov/462/City-Biography", "https://www.newarkhappening.com/things-to-do/tours-itineraries/taste-of-the-ironbound/"],
    },
    "dulles": {
        "short_description": "杜勒斯条目对应华盛顿杜勒斯国际机场所在的弗吉尼亚地区。1962年启用的机场以大跨度航站楼著称，连接首都圈与远程航线；这里的城市故事，首先是一部航空与郊区交通的扩展史。",
        "overview": "游戏中的杜勒斯以 IAD 机场为坐标，位于华盛顿首都圈的弗吉尼亚一侧。机场1962年启用，是面向喷气客机时代规划的重要交通设施。航站楼、专用道路与后来的轨道交通把原本较远的机场接入都会区。若把它当作行程起点，适合从机场建筑和周边交通理解首都圈怎样向西延伸。",
        "history_summary": "华盛顿杜勒斯国际机场于1962年11月17日开放，由肯尼迪总统主持启用。首架商业航班从新泽西州纽瓦克飞来；当时机场只有少量航空公司。此后航空网络和地面交通逐步扩大，改变了机场周围地区的联系方式。",
        "economy_summary": "杜勒斯机场承担首都圈的国际客运与航空货运。跑道、仓储和货运坡道使它成为弗吉尼亚地区的物流节点；航空服务还带动了附近的交通、办公和旅客服务。",
        "food_summary": "杜勒斯机场所在地区属于华盛顿都会区，餐饮选择受各地移民文化影响。转机时可留意航站楼餐饮，若时间充裕，进入弗吉尼亚社区寻找当地小店会比把机场食物当作城市特产更合适。",
        "source_ids": ["https://www.mwaa.com/news/40th-anniversary-washington-dulles-international-airport", "https://www.mwaa.com/business/facilities-and-land"],
    },
    "dubai(jebel_ali)": {
        "short_description": "杰贝阿里位于迪拜西部，港口、自由区和马克图姆国际机场相互靠近。1979年启用的港口与1985年设立的自由区，逐渐把这里发展成贸易和物流重镇。",
        "overview": "迪拜的杰贝阿里条目对应 DWC 机场及其周边地区。向海的一侧是杰贝阿里港，向内陆延伸的是自由区和物流园。港口于1979年启用，自由区从1985年的少量企业逐步发展。这里与老迪拜的市集气质不同，更适合从集装箱、仓储和机场观察一座城市怎样组织全球贸易。",
        "history_summary": "杰贝阿里的现代发展从大型港口建设开始。港口于1979年启用，自由区于1985年成立；工业和贸易企业随后在港口周边聚集。马克图姆国际机场的出现，让这一地区形成海运与空运并列的交通格局。",
        "economy_summary": "杰贝阿里港、自由区和马克图姆国际机场共同组成迪拜的重要物流带。自由区面向制造、仓储和转口贸易，货物可在港口、道路与航空之间转换；它是理解迪拜非石油经济的一处具体场景。",
        "food_summary": "杰贝阿里的餐饮反映迪拜多元社群的日常，阿拉伯香料饭与烤肉、南亚咖喱和各国餐馆并存。这里的特色更在于港区与自由区汇聚的跨文化食堂和小店，而非某一道独有的古老菜式。",
        "source_ids": ["https://www.jafza.ae/about/", "https://www.jafza.ae/resource-centre/guides/where-is-jafza-located/"],
    },
    "alexandria": {
        "short_description": "亚历山大位于埃及地中海岸，古代港口、灯塔和图书馆的故事至今仍与城市相连。海边的盖特贝城堡和2002年开放的新图书馆，让古典记忆与当代公共文化并置。",
        "overview": "埃及的亚历山大面向地中海，是一座因港口而兴盛的城市。古代的灯塔曾是地中海航行的地标，学者与藏书使图书馆成为知识交流的象征。灯塔已不存，盖特贝城堡位于其旧址一带；新亚历山大图书馆则在海边重新回应这段传统。走海滨线，可以同时看见港城生活和跨时代的文化记忆。",
        "history_summary": "亚历山大在古代迅速成为地中海商业与学术中心。灯塔被列为古代世界奇观，图书馆汇聚了多地学者；后来地震等变迁使古建筑逐渐消失。今天的盖特贝城堡和新亚历山大图书馆，用不同方式保存并讲述这段历史。",
        "geography_summary": "亚历山大位于埃及北部的地中海沿岸，城市发展与港口和海上交通紧密相连。与埃及内陆的沙漠地带相比，海风使这里的气候更温和；游览时可以沿海滨把港口、城堡和图书馆连起来。",
        "economy_summary": "港口贸易是亚历山大长期发展的基础。古代它连接地中海各地的商品与知识往来；今天，港口、城市服务和文化旅游继续塑造当地经济。",
        "food_summary": "作为地中海港城，亚历山大的餐桌有鱼类、海鲜与埃及传统豆类料理。海滨餐馆适合看当天渔获，街头则能找到富尔豆泥、炸豆饼等更日常的口味。",
        "culture_note": "亚历山大的古灯塔早已消失，但其遗址附近后来出现盖特贝城堡；古图书馆也以现代建筑得到回应。两个地标像城市给自己的两次回信，把传说中的光和书重新带回海岸。",
        "source_ids": ["https://whc.unesco.org/en/tentativelists/1822", "https://www.bibalex.org/en/news/details?documentid=211&page=1241"],
    },
}

TIANJIN = {
    "short_description": "天津处在海河入渤海的水陆交汇处，也是京津冀的重要港口城市。运河和海运留下的市井传统，与滨海新区的航运、制造业并列。你可以在海河边看近代街区，也能从早点摊的煎饼果子与锅巴菜认识津味日常。",
    "overview": "天津是中国北方的直辖市，海河穿城而过，东侧连接渤海。隋唐以来的漕运让这里成为粮食与绸缎北运的重要码头；近代开埠又留下多种风格的街区。如今城市同时承担港口航运、先进制造和区域商贸功能。游览时可把海河、古文化街和滨海新区放在同一条城市线索里：河岸讲述贸易往来，老街保留手艺与小吃，港区呈现当代货物流通。天津滨海国际机场的三字码是 TSN。",
    "history_summary": "天津的城市脉络与大运河密切相关。金代三岔河口一带出现直沽寨，元代设海津镇，明永乐二年（1404）设天津卫。此后漕运、盐业与港口贸易推动城市扩大。近代开埠带来工业和金融活动，也留下今天仍可辨认的历史街区。走过海河两岸，不同年代的建筑像一册摊开的城市年表。",
    "geography_summary": "天津位于华北平原东北部、海河流域下游，东临渤海，地势总体低平。这里四季分明，属暖温带半湿润季风气候；夏季降雨较集中，春季风较大。海河与沿海港区共同塑造了它的水运位置。出行看天气时，沿海与内陆城区的风感也会有所不同。",
    "economy_summary": "天津的港口、航运服务与制造业彼此支撑。天津港连接海上贸易，滨海新区聚集临港产业；城市还发展航空航天、装备制造和金融服务。这里适合把贸易叙事放在‘河、港、厂’三条线上理解：漕运形成老商埠，现代港区处理大宗货物，制造业把材料变成设备。",
    "food_summary": "清晨的天津可以从一套煎饼果子开始：绿豆面饼裹上鸡蛋、馃子和酱料，做法与外地改良版并不完全一样。锅巴菜、面茶、卷圈也是街头常见的津味早点。十八街麻花和耳朵眼炸糕适合作为小吃线索；一些老店的俗名来自街巷、掌柜绰号，叫法比正式字号更容易被记住。",
    "travel_note": "天津滨海国际机场代码 TSN。想看民间工艺，可留意泥人张彩塑和杨柳青年画；年画里的‘莲年有余’借谐音寄托丰收与团圆。海河沿岸与古文化街适合步行，夏季记得预留避雨时间。食品运输应注意保质期与包装，易碎的泥塑则需要防震。",
    "culture_note": "天津老字号常有一个正式商号和一个更响亮的街坊俗名。‘十八街’麻花、‘耳朵眼’炸糕便是例子：人们按街道或店铺位置叫得顺口，久而久之反倒成了城市记忆。杨柳青年画里的‘莲年有余’又用谐音寄托新年祝愿。",
    "source_ids": [
        "https://www.tj.gov.cn/sq/tjgk/tjls/lsyg/",
        "https://whly.tj.gov.cn/TJSWHHLYJ/gabsycs/mtjjgh/202509/t20250901_7123094.html",
        "https://www.tj.gov.cn/sy/tjxw/202504/t20250408_6902335.html",
        "https://whly.tj.gov.cn/WZWSREL3Rqc3dsenh3L2pnYm4vd2h0ai9qZ3p0LzIwMjMwOC90MjAyMzA4MDFfNjM2NzA1My5odG1s",
    ],
}


def extend_short(blob: dict) -> None:
    """Meet the game copy floor with sourced facts already in this city file."""
    short = blob["short_description"].strip()
    if len(short) >= 60:
        return
    for field in ("history_summary", "food_summary", "geography_summary", "travel_note"):
        for sentence in blob.get(field, "").split("。"):
            sentence = sentence.strip()
            if not sentence or "结构化资料" in sentence or sentence in short:
                continue
            addition = sentence + "。"
            if len(short) + len(addition) > 150:
                continue
            short += addition
            if len(short) >= 70:
                blob["short_description"] = short
                return
    blob["short_description"] = short


def main() -> None:
    world = json.loads(WORLD.read_text(encoding="utf-8"))
    facts = json.loads(FACTS.read_text(encoding="utf-8"))
    names = json.loads(NAMES.read_text(encoding="utf-8"))
    histories = json.loads(HISTORY.read_text(encoding="utf-8"))
    writer = CityWriter(facts, _load_airports())
    airports = {a["city_id"]: a for a in world["airports"]}
    created = []
    for current in world["cities"]:
        cid = current["city_id"]
        path = CITIES / (cid + ".json")
        if path.exists() and current.get("content_confidence") != "C":
            if "--refresh-b" in sys.argv and current.get("content_confidence") == "B":
                existing = json.loads(path.read_text(encoding="utf-8"))
                existing.update(writer.compose(existing))
                extend_short(existing)
                qid = facts.get(cid, {}).get("qid")
                if qid:
                    existing["source_ids"] = list(dict.fromkeys(
                        existing.get("source_ids", []) + [f"wikidata:{qid}"]))
                if cid in FEATURED_UPDATES:
                    extra = FEATURED_UPDATES[cid]
                    existing["source_ids"] = list(dict.fromkeys(
                        [s for s in existing.get("source_ids", []) if not s.startswith("wikidata:")]
                        + extra["source_ids"]))
                    existing.update({k: v for k, v in extra.items() if k != "source_ids"})
                path.write_text(json.dumps(existing, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
                created.append(cid)
            continue
        f = facts.get(cid, {})
        candidate = f.get("name_zh", "")
        if not re.search(r"[\u4e00-\u9fff]", candidate):
            candidate = ""
        name = NAME_OVERRIDES.get(cid) or names.get(current["name_en"]) or candidate or current["name_zh"]
        country_zh = COUNTRY_NAME_OVERRIDES.get(current["country_id"], current["country_zh"])
        blob = {
            "city_id": cid, "name_zh": name,
            "name_en": current["name_en"], "country_id": current["country_id"],
            "country_zh": country_zh, "timezone": current["timezone"],
        }
        blob.update(writer.compose(blob))
        if current["country_id"] in FOOD_CONTEXT:
            dish = FOOD_CONTEXT[current["country_id"]]
            blob["food_summary"] = (
                f"在{country_zh}的饮食传统中，{dish}是值得留意的风味。"
                "这些是国家或地区层面的饮食线索；具体到这座城市，可以从市场与街头小店观察当地做法，"
                "留意食材、香料与节庆时令的变化。"
            )
        if cid == "tianjin":
            blob.update(TIANJIN)
        if cid in histories:
            note = histories[cid]
            blob["history_summary"] = note["history_summary"]
            if note.get("culture_note"):
                blob["culture_note"] = note["culture_note"]
            blob["source_ids"] = list(dict.fromkeys(blob.get("source_ids", []) + note["source_ids"]))
        extend_short(blob)
        blob["content_confidence"] = "B" if f.get("qid") else "C"
        blob["source_ids"] = list(dict.fromkeys(
            ([f"wikidata:{f['qid']}"] if f.get("qid") else [])
            + [f"ourairports:{airports[cid]['iata']}"]
            + blob.get("source_ids", [])
        ))
        previous = json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}
        blob["image_asset_id"] = previous.get("image_asset_id", f"city_{cid}_hero_720")
        path.write_text(json.dumps(blob, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        created.append(cid)
    print(f"Created {len(created)} current-roster city files; {len(world['cities'])} playable cities now have files")


if __name__ == "__main__":
    main()
