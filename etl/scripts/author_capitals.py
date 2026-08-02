#!/usr/bin/env python3
"""Author high-priority city content into etl/content/cities/*.json.

Reads CONTENT dict (city_id -> seven fields + source_ids) from
author_data.py, rewrites the JSON files, and sets content_confidence to A.
Template-filler cities absent from CONTENT remain untouched (pipeline marks
them C).

Usage:
  python scripts/author_capitals.py                 # apply all authored content
  python scripts/author_capitals.py --dry-run       # print what would change
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONTENT_DIR = ROOT / "content" / "cities"

sys.path.insert(0, str(ROOT / "content"))
from author_data import CONTENT  # noqa: E402
from author_expand import EXTEND  # noqa: E402
from author_short2 import SHORT2  # noqa: E402
from author_short3 import SHORT3  # noqa: E402

FIELDS = [
    "short_description",
    "overview",
    "history_summary",
    "geography_summary",
    "economy_summary",
    "food_summary",
    "travel_note",
]


def merged(cid: str, data: dict) -> dict:
    out = dict(data)
    extra = EXTEND.get(cid, {})
    for f in FIELDS:
        if f in extra and not (f == "short_description" and cid in SHORT2):
            base = str(out.get(f, ""))
            out[f] = base + extra[f]
    if cid in SHORT2:
        # SHORT2 is the additive second sentence; drop EXTEND's short_description
        # (which duplicated the base) to avoid repetition.
        out["short_description"] = str(out.get("short_description", "")) + SHORT2[cid]
    if cid in SHORT3:
        clause = SHORT3[cid].lstrip("，").lstrip()
        out["short_description"] = str(out.get("short_description", "")) + clause
    return out


def main() -> int:
    dry = "--dry-run" in sys.argv
    changed = []
    for cid, data in CONTENT.items():
        path = CONTENT_DIR / f"{cid}.json"
        if not path.exists():
            print(f"MISSING file for {cid}")
            continue
        data = merged(cid, data)
        blob = json.loads(path.read_text(encoding="utf-8"))
        dirty = False
        for f in FIELDS:
            if f in data and blob.get(f) != data[f]:
                blob[f] = data[f]
                dirty = True
        if "source_ids" in data and blob.get("source_ids") != data["source_ids"]:
            blob["source_ids"] = data["source_ids"]
            dirty = True
        if blob.get("content_confidence") != "A":
            blob["content_confidence"] = "A"
            dirty = True
        if dirty:
            changed.append(cid)
            if not dry:
                path.write_text(json.dumps(blob, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"Would rewrite {len(changed)} cities" if dry else f"Rewrote {len(changed)} cities")
    for c in sorted(changed):
        print("  " + c)
    return 0


if __name__ == "__main__":
    sys.exit(main())
