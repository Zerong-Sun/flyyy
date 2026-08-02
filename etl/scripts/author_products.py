#!/usr/bin/env python3
"""Author trade-contract-compliant products for high-priority authored cities.

Cities whose content_confidence is "A" must have a product mix that satisfies
tests/etl/test_trade_contracts.py:
  - every product weight <= 12 kg and base_reference_price >= 200 USD
  - at least one light product (weight <= 2 kg)
  - at least one high-value product (price >= 2000 USD)

Regenerates etl/content/products/{city_id}.yaml for the cities in
author_data.py CONTENT. Other cities are untouched.

Usage:
  python scripts/author_products.py            # apply
  python scripts/author_products.py --dry-run  # print what would change
"""
from __future__ import annotations

import random
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONTENT_DIR = ROOT / "content"
PRODUCTS_DIR = CONTENT_DIR / "products"

sys.path.insert(0, str(CONTENT_DIR))
from author_data import CONTENT  # noqa: E402
from generate_mr1_content import COUNTRY_PRODUCT_THEMES, PRODUCT_PARAMS  # noqa: E402

import yaml  # noqa: E402

# Categories whose default weight range already stays <= 12 kg.
_LIGHT_CATS = ["电子", "化妆品", "香料", "文具", "糖果", "玩具", "茶叶", "能源"]
# Categories that can produce high-value contracts (>= 2000).
_HIGH_VALUE_CATS = ["电子", "能源", "机械"]
# Fallback if a theme lacks enough compliant categories.
_FALLBACK_CATS = ["食品", "香料", "糖果", "工艺品", "日用品", "矿产"]


def _city_rng(city_id: str, purpose: str = "products") -> random.Random:
    import hashlib

    h = hashlib.sha256(f"{city_id}|{purpose}".encode()).hexdigest()
    return random.Random(int(h[:16], 16))


def _params_for(cat: str) -> dict:
    params = PRODUCT_PARAMS.get(cat)
    if params is None:
        # 化妆品 lives in COUNTRY_PRODUCT_THEMES but not always PRODUCT_PARAMS
        params = {"w": (1.0, 3.0), "p": (200.0, 600.0), "sh": (4320, 8760),
                  "fr": 0.2, "rr": (0.3, 0.5), "desc": "化妆品样品合约，轻便高价值跨境贸易品。"}
    return params


def _compliant_product(cid: str, city_zh: str, cat: str, idx: int, rng: random.Random,
                       force_light: bool = False, force_high: bool = False) -> dict:
    params = _params_for(cat)
    w_lo, w_hi = params["w"]
    p_lo, p_hi = params["p"]
    # Clamp weight into trade-contract range.
    w_hi = min(w_hi, 12.0)
    w_lo = min(w_lo, w_hi)
    weight = round(rng.uniform(w_lo, w_hi), 1)
    price = round(rng.uniform(max(p_lo, 200.0), max(p_hi, 200.0)), 2)
    if force_light:
        weight = round(rng.uniform(0.3, 2.0), 1)
    if force_high:
        price = round(rng.uniform(2200.0, 3000.0), 2)
        weight = min(weight, 6.0)
    shelf = int(rng.randint(*params["sh"]))
    rarity = round(rng.uniform(*params["rr"]), 2)
    return {
        "product_id": f"{cid}_{cat}_{'A' if idx == 0 else chr(ord('B') + idx - 1)}",
        "name_zh": f"{city_zh}{cat}合约",
        "category": cat,
        "weight_kg": weight,
        "base_reference_price": price,
        "reference_currency": "USD",
        "shelf_life_hours": shelf,
        "fragility": params["fr"],
        "rarity": rarity,
        "description": params["desc"],
    }


def author_city_products(cid: str, country_id: str, city_zh: str) -> list[dict]:
    rng = _city_rng(cid)
    theme = COUNTRY_PRODUCT_THEMES.get(country_id, COUNTRY_PRODUCT_THEMES["default"])
    cats = [c for c in theme["main"]]
    # Ensure we have enough categories that can be made compliant.
    pool = list(dict.fromkeys(cats + _FALLBACK_CATS))
    rng.shuffle(pool)
    selected = pool[:5]

    products = []
    # index 0: light + high-value anchor (electronics-style).
    anchor = _compliant_product(cid, city_zh, "电子", 0, rng, force_light=True, force_high=True)
    products.append(anchor)
    used = {"电子"}
    for i, cat in enumerate(selected, start=1):
        if cat in used:
            continue
        used.add(cat)
        force_light = i == 1 and cat not in _HIGH_VALUE_CATS
        products.append(_compliant_product(cid, city_zh, cat, i, rng,
                                           force_light=force_light))
        if len(products) >= 5:
            break
    # Guarantee the high-value anchor is present and compliant.
    return products


def main() -> int:
    dry = "--dry-run" in sys.argv
    changed = []
    for cid, data in CONTENT.items():
        path = PRODUCTS_DIR / f"{cid}.yaml"
        city_path = CONTENT_DIR / "cities" / f"{cid}.json"
        if not path.exists() or not city_path.exists():
            print(f"MISSING file for {cid}")
            continue
        import json

        city_json = json.loads(city_path.read_text(encoding="utf-8"))
        country_id = city_json.get("country_id", "")
        city_zh = city_json.get("name_zh", cid)
        products = author_city_products(cid, country_id, city_zh)
        doc = {"products": products}
        new_text = yaml.dump(doc, allow_unicode=True, default_flow_style=False,
                             sort_keys=False, width=120)
        if path.read_text(encoding="utf-8").strip() != new_text.strip():
            changed.append(cid)
            if not dry:
                path.write_text(new_text, encoding="utf-8")
    print(f"Would rewrite {len(changed)} product files" if dry
          else f"Rewrote {len(changed)} product files")
    for c in sorted(changed):
        print("  " + c)
    return 0


if __name__ == "__main__":
    sys.exit(main())
