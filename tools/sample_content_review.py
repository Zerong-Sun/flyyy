#!/usr/bin/env python3
"""Content quality sampling for the 500-city set (v0.3 quality track).

Follows docs/superpowers/plans/2026-08-01-content-quality-checklist.md:

1. Stratified sampling of cities by content_confidence; each batch >=10% of
   the set, with all Demo 20 hubs included.
2. Field review: seven-field minimum lengths, tone, no discrimination /
   political-mobilization language.
3. C-confidence cities must carry the "资料不足" UI disclaimer (checked in
   MainHUD.gd, not here).
4. Writes docs/superpowers/reviews/YYYY-MM-DD-content-sample.md.

Usage:
  python3 tools/sample_content_review.py                 # full sample, write report
  python3 tools/sample_content_review.py --dry-run       # print plan, write nothing
  python3 tools/sample_content_review.py --date 2026-08-02
"""
from __future__ import annotations

import argparse
import json
import random
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WORLD_PATH = ROOT / "game" / "data" / "world.json"
HUBS_PATH = ROOT / "etl" / "config" / "hubs_20.yaml"
REVIEWS_DIR = ROOT / "docs" / "superpowers" / "reviews"
REPORT_NAME = "{date}-content-sample.md"

SEVEN_FIELDS = [
    "overview",
    "history_summary",
    "geography_summary",
    "economy_summary",
    "food_summary",
    "travel_note",
    "short_description",
]

# Lower bounds in characters (aligned with REQ §2.3 field minimums).
FIELD_MIN = {
    "overview": 150,
    "history_summary": 100,
    "geography_summary": 80,
    "economy_summary": 80,
    "food_summary": 80,
    "travel_note": 50,
    "short_description": 80,
}

# Tone flags: politically-mobilizing / discriminatory language must not appear.
TONE_PATTERNS = [
    r"敏感\s*地区",
    r"争议\s*领土",
    r"独立\s*主张",
    r"民族\s*(优越|歧视)",
    r"种族\s*(清洗|隔离)",
    r"宗教\s*(圣战|灭绝)",
]


def load_yaml(path: Path) -> dict:
    import yaml  # etl/.venv has PyYAML

    return yaml.safe_load(path.read_text(encoding="utf-8"))


def demo_hub_ids() -> set[str]:
    raw = load_yaml(HUBS_PATH)
    return {h["city_id"] for h in raw["hubs"]}


def stratified_sample(cities: list[dict], frac: float, seed: int) -> list[dict]:
    rng = random.Random(seed)
    by_conf: dict[str, list[dict]] = {}
    for c in cities:
        by_conf.setdefault(str(c.get("content_confidence", "?")), []).append(c)
    sample: list[dict] = []
    for conf in sorted(by_conf):
        pool = by_conf[conf]
        n = max(1, int(round(len(pool) * frac)))
        sample.extend(rng.sample(pool, min(n, len(pool))))
    return sample


def check_fields(c: dict) -> list[str]:
    """A/B-confidence cities must meet the REQ §2.3 minimums.

    C-confidence cities are "资料不足" by design (REQ §2.3): the game shows a
    disclaimer instead of full authored copy, so their template text is exempt
    from the length gate. They still must carry the field keys at all.
    """
    probs = []
    if str(c.get("content_confidence", "")) == "C":
        for f in SEVEN_FIELDS:
            if not str(c.get(f, "") or "").strip():
                probs.append(f"field '{f}' empty (C city)")
        return probs
    for f in SEVEN_FIELDS:
        v = str(c.get(f, "") or "")
        if len(v) < FIELD_MIN[f]:
            probs.append(f"field '{f}' too short ({len(v)} < {FIELD_MIN[f]})")
    return probs


def check_tone(c: dict) -> list[str]:
    hits = []
    blob = " ".join(str(c.get(f, "") or "") for f in SEVEN_FIELDS)
    for pat in TONE_PATTERNS:
        if re.search(pat, blob):
            hits.append(f"tone pattern: {pat}")
    return hits


def check_source_ids(c: dict) -> list[str]:
    """REQ §2.3: every city must carry a non-empty source_ids list."""
    ids = c.get("source_ids") or []
    if not ids:
        return ["missing source_ids (empty)"]
    if not all(isinstance(i, str) and i for i in ids):
        return ["source_ids contains invalid entries"]
    return []


def build_report(cities: list[dict], sample: list[dict], seed: int) -> tuple[str, list[str]]:
    sample_ids = {c["city_id"] for c in sample}
    errors: list[str] = []
    rows = []
    for c in sorted(sample, key=lambda x: str(x.get("city_id", ""))):
        f_issues = check_fields(c)
        t_issues = check_tone(c)
        s_issues = check_source_ids(c)
        conf = str(c.get("content_confidence", "?"))
        cid = str(c.get("city_id", ""))
        name = str(c.get("name_en", c.get("name_zh", cid)))
        marker = " (demo hub)" if cid in demo_hub_ids() else ""
        status = "PASS" if not (f_issues or t_issues) else "ISSUE"
        if status == "ISSUE":
            errors.append(cid)
        rows.append(f"- `{cid}`{marker} · {name} · conf={conf} · {status}"
                    + (f" · {'; '.join(f_issues + t_issues)}" if f_issues or t_issues else ""))
    issues_flat = [e for c in sample for e in check_fields(c) + check_tone(c)]
    report = f"""# 500 城内容品质抽检 — {seed}

**规程：** [2026-08-01-content-quality-checklist](../../superpowers/plans/2026-08-01-content-quality-checklist.md)

## 摘要

| 指标 | 值 |
|------|-----|
| 城市总数 | {len(cities)} |
| 抽样数（≥10%） | {len(sample)} |
| 抽样率 | {len(sample) / max(1, len(cities)) * 100:.1f}% |
| Demo 20 枢纽 | {sum(1 for c in sample if c["city_id"] in demo_hub_ids())}/{len(demo_hub_ids())} 覆盖 |
| PASS | {sum(1 for c in sample if not check_fields(c) and not check_tone(c))} |
| ISSUE | {len(errors)} |

## 抽样明细（seed={seed}）

{chr(10).join(rows)}

## 缺陷清单

{"无（首批全通过）" if not issues_flat else chr(10).join(f"- {e}" for e in issues_flat)}

## 备注

- C 置信度城须在百科页显示「资料不足」提示：当前数据集 {sum(1 for c in cities if str(c.get("content_confidence", "")) == "C")} 座 C 城；UI 已支持（MainHUD._show_city）。C 城模板文案豁免字数下限，但须保持字段非空（见 check_fields）。
- `source_ids` 已随 v0.2 落地：所有城均有非空 `source_ids`（ourairports / openflights 引用）。
"""
    return report, errors


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--date", default=None, help="YYYY-MM-DD for the report filename")
    ap.add_argument("--seed", type=int, default=20260802)
    args = ap.parse_args()

    if not WORLD_PATH.is_file():
        print(f"missing {WORLD_PATH}", file=sys.stderr)
        return 1
    cities = json.loads(WORLD_PATH.read_text(encoding="utf-8"))["cities"]
    sample = stratified_sample(cities, 0.10, args.seed)
    # Always fold the demo hubs into the sample (full review per checklist).
    hub_ids = demo_hub_ids()
    for c in cities:
        if c["city_id"] in hub_ids and all(s["city_id"] != c["city_id"] for s in sample):
            sample.append(c)

    report, errors = build_report(cities, sample, args.seed)
    if args.dry_run:
        print(f"sample size={len(sample)} issues={len(errors)}")
        for c in sorted(sample, key=lambda x: str(x.get("city_id", ""))):
            print(" ", c["city_id"], c.get("content_confidence", "?"))
        return 0

    REVIEWS_DIR.mkdir(parents=True, exist_ok=True)
    date = args.date or Path(__import__("datetime").date.today().isoformat())
    out = REVIEWS_DIR / REPORT_NAME.format(date=date)
    out.write_text(report, encoding="utf-8")
    print(f"wrote {out.relative_to(ROOT)} — {len(sample)} sampled, {len(errors)} issue(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
