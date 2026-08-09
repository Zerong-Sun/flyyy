#!/usr/bin/env python3
"""Rewrite product descriptions in etl/content/products/*.yaml from real data.

Each description is composed from the product's real fields (name, weight,
shelf life, fragility, rarity, price), its real origin (city + country), and a
curated real per-category fact.  No padding, no repeated filler sentences,
nothing invented: weight/shelf-life/fragility/rarity/price all come straight
from the YAML row.

Target length 40-120 Chinese characters (CAS §3.2.4 / §3.6).

Usage:
  python scripts/author_product_descriptions.py            # apply
  python scripts/author_product_descriptions.py --dry-run  # preview 3 samples
"""
from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from etl.scripts.run_pipeline import load_yaml  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
PRODUCTS = ROOT / "content" / "products"
CITIES = ROOT / "content" / "cities"

CATEGORY_FACTS: dict[str, str] = {
    "纺织品": "纺织与服装是国际贸易的传统大宗品类",
    "能源": "能源类合约跟踪油气与电力等大宗商品行情",
    "机械": "机械设备与工业部件是跨境物流的重要品类",
    "工艺品": "工艺品带有鲜明的地方工艺与审美传统",
    "电子": "电子元件与消费电子是贸易量最大的品类之一",
    "矿产": "矿产品价格与全球大宗商品行情联动",
    "食品": "食品类货物对仓储条件与保质期敏感",
    "日用品": "日用品需求平稳，适合作为常备贸易品",
    "糖果": "糖果点心类商品包装轻巧，礼品属性强",
    "咖啡": "咖啡是国际大宗农产品，产地风味差异明显",
    "香料": "香料贸易历史悠久，单价与风味并重",
    "茶叶": "茶叶是历史悠久的国际饮品贸易品",
    "玩具": "玩具类商品批量贸易活跃，季节性强",
    "陶瓷": "陶瓷制品易碎，包装与搬运需小心",
    "文具": "文具用品需求稳定，轻便易携带",
    "化妆品": "化妆品属高价值轻量品类，对包装要求高",
}


def _rng(s: str) -> int:
    return int(hashlib.sha256(s.encode()).hexdigest()[:8], 16)


def _compose(row: dict, city: dict) -> str:
    name = row.get("name_zh", "")
    weight = float(row.get("weight_kg", 1.0))
    shelf = float(row.get("shelf_life_hours", 99999))
    frag = float(row.get("fragility", 0.0))
    rare = float(row.get("rarity", 0.5))
    price = float(row.get("base_reference_price", 100.0))
    cat = row.get("category", "")

    clauses: list[str] = []

    if weight <= 2.0:
        clauses.append(f"单件约{weight:g}kg，轻便易携")
    elif weight <= 8.0:
        clauses.append(f"单件约{weight:g}kg，分量适中")
    else:
        clauses.append(f"单件约{weight:g}kg，分量较重，占行李配额多")

    if shelf <= 48:
        clauses.append("保质期仅数小时，需尽快出手")
    elif shelf <= 168:
        clauses.append(f"保质期约{shelf:g}小时，宜尽快周转")
    elif shelf <= 720:
        clauses.append(f"保质期约{shelf:g}小时")
    else:
        clauses.append("性质耐久，长途运输不易变质")

    if frag >= 0.5:
        clauses.append("质地易碎，运输需防震包装")
    if rare >= 0.7:
        clauses.append("市面较为稀缺，在需求地有溢价")
    elif rare <= 0.35:
        clauses.append("货源常见，走量为主")

    if price >= 2000:
        clauses.append(f"单件报价${price:g}，属高值商品")
    elif price < 500:
        clauses.append(f"单件报价${price:g}，入手门槛不高")

    origin = ""
    city_zh = city.get("name_zh", "")
    country_zh = city.get("country_zh", "")
    if country_zh:
        if city_zh and city_zh not in name:
            origin = f"产自{country_zh}{city_zh}"
        else:
            origin = f"产自{country_zh}"

    fact = CATEGORY_FACTS.get(cat, "")

    # Assemble with stable per-product ordering variation.
    parts = [name + "。"]
    seed = _rng(row.get("product_id", name))
    rest = clauses[:]
    if origin:
        rest.append(origin)
    if fact:
        rest.append(fact)
    if seed % 3 == 0:
        rest = rest[1:] + rest[:1]  # rotate
    elif seed % 3 == 1:
        rest = rest[-1:] + rest[:-1]
    parts.extend(c + "。" for c in rest)

    text = "".join(parts)
    # Trim to 120 chars at a sentence boundary.
    if len(text) > 120:
        cut = text.rfind("。", 0, 120)
        if cut > 40:
            text = text[:cut + 1]
        else:
            text = text[:120].rsplit("。", 1)[0] + "。"
    return text


def main() -> int:
    dry = "--dry-run" in sys.argv
    changed = 0
    samples = 0
    for ypath in sorted(PRODUCTS.glob("*.yaml")):
        city_id = ypath.stem
        city_path = CITIES / f"{city_id}.json"
        city = json.loads(city_path.read_text(encoding="utf-8")) if city_path.exists() else {}
        lines = ypath.read_text(encoding="utf-8").splitlines(keepends=True)
        desc_idx = [i for i, ln in enumerate(lines)
                    if ln.startswith("  description:")]
        if not desc_idx:
            continue
        data = load_yaml(ypath)
        rows = data.get("products") or []
        assert len(rows) == len(desc_idx), (ypath.name, len(rows), len(desc_idx))
        for row, idx in zip(rows, desc_idx):
            new = _compose(row, city)
            old = row.get("description", "")
            if new == old:
                continue
            changed += 1
            if dry and samples < 3:
                print("=" * 60)
                print(row.get("product_id"), "|", row.get("category"))
                print("old:", old[:60])
                print("new:", new)
                print("len:", len(new))
                samples += 1
            if not dry:
                indent = lines[idx][:len(lines[idx]) - len(lines[idx].lstrip())]
                lines[idx] = f"{indent}description: {new}\n"
        if not dry:
            ypath.write_text("".join(lines), encoding="utf-8")
    print(f"done: {changed} descriptions rewritten ({'dry-run' if dry else 'written'})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
