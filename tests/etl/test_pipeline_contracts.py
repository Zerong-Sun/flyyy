"""Pipeline-contract regression tests (GDLC Playtest #2 ratchet).

Every test in this file was authored RED before its fix landed:

- test_margin_per_kg_bound / test_margin_cap_in_config — P0: light high-rarity
  proxies paid up to $53.5k/kg (a $1.07M 20kg hold on two real scheduled legs).
  Fix: `market.margin_per_kg_cap_usd` clamp in the pricing formula.
- test_stopover_legs_real_and_bounded — P1: the stopover mint fabricated
  airline-leg pairs (144/144 first legs unoperated in the dev snapshot) and
  could exceed the antipodal bound; `synthetic_stopover` must imply the OD is
  a real route.
- test_mct_transfer_edges — P2: flat 75-min authored-hub overrides killed
  `international_min: 120` on 87% of transfer edges.
- test_challenge_config_in_data — P2: caps/thresholds must live in
  world.json `economy.challenge`, not as literals in three places.
- test_expo_export_carries_challenge_block / test_expo_declared_mapping —
  P1: the Expo demo economy drifted 3.5x on fares with zero guard; the export
  must carry the challenge block and the demo must declare its mapping.
- test_pipeline_double_run_byte_identical — P0: salted `hash()` flight
  numbers and set-order stopover hub selection made every run dirty
  (53/158 files drifted). Only `meta.generated_at` (UI provenance timestamp)
  is exempted, explicitly documented here.
"""
from __future__ import annotations

import filecmp
import json
import math
import os
import shutil
import sqlite3
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
GAME = ROOT / "game"
DATA = GAME / "data"
WORLD = json.loads((DATA / "world.json").read_text(encoding="utf-8"))

CAP_MARGIN_PER_KG = 500.0
ANTIPODAL_KM = 20037.0


def _haversine_km(origin: str, dest: str) -> float:
    airports = {a["iata"]: a for a in WORLD["airports"]}
    oa, da = airports[origin], airports[dest]
    la1, lo1 = math.radians(float(oa["latitude"])), math.radians(float(oa["longitude"]))
    la2, lo2 = math.radians(float(da["latitude"])), math.radians(float(da["longitude"]))
    h = math.sin((la2 - la1) / 2) ** 2 + math.cos(la1) * math.cos(la2) * math.sin((lo2 - lo1) / 2) ** 2
    return 6371.0088 * 2 * math.asin(math.sqrt(h))


def _openflights_route_set() -> set[tuple[str, str, str]]:
    """(airline_iata, origin_iata, dest_iata) from raw OpenFlights data."""
    raw = ROOT / "etl" / "raw"
    iata_by_id: dict[str, str] = {}
    for line in (raw / "airlines.dat").read_text(encoding="utf-8", errors="replace").splitlines():
        f = line.split(",")
        if len(f) >= 8 and f[7] == "Y" and f[3] != "\\N":
            iata_by_id[f[0]] = f[3]
    out: set[tuple[str, str, str]] = set()
    for line in (raw / "routes.dat").read_text(encoding="utf-8", errors="replace").splitlines():
        f = line.split(",")
        if len(f) < 6:
            continue
        code = f[0]
        airline = iata_by_id.get(code, code if (code.isalpha() and 2 <= len(code) <= 3) else "")
        if not airline:
            continue
        out.add((airline, f[2], f[4]))
    return out


def test_margin_per_kg_bound():
    """No (product, destination) may exceed margin_per_kg_cap_usd vs origin buy."""
    from collections import defaultdict

    products = {p["product_id"]: p for p in WORLD["products"]}
    origin_buy: dict[str, float] = {}
    # Single pass over every market file (never per-product file reads — that
    # is O(products × files) and cost 23 minutes on the full 500-city set).
    sell_rows: dict[str, list[tuple[str, float]]] = defaultdict(list)
    for fpath in (DATA / "markets").glob("*.json"):
        city = fpath.stem
        for r in json.loads(fpath.read_text(encoding="utf-8")):
            pid = r["p"]
            sell_rows[pid].append((city, float(r["s"])))
            p = products.get(pid)
            if p is not None and city == p["origin_city_id"]:
                origin_buy[pid] = float(r["b"])
    worst = 0.0
    worst_pair = ""
    for pid, rows in sell_rows.items():
        p = products[pid]
        w_kg = float(p["weight_kg"])
        ob = origin_buy.get(pid)
        if not ob or w_kg <= 0.0:
            continue
        for city, s in rows:
            margin = (s - ob) / w_kg
            if margin > worst:
                worst = margin
                worst_pair = f"{pid} -> {city}: sell {s} - buy {ob} / {w_kg}kg"
    # +0.05 tolerance: the clamp is exact but market rows round to 2 decimals,
    # so a clamped value can land a few cents over the cap per kg.
    assert worst <= CAP_MARGIN_PER_KG + 0.05, (
        f"max margin {worst:.2f} $/kg > cap {CAP_MARGIN_PER_KG} at {worst_pair}"
    )


def test_margin_cap_in_config():
    mkt = WORLD["economy"].get("market", {})
    assert float(mkt.get("margin_per_kg_cap_usd", 0.0)) == CAP_MARGIN_PER_KG, (
        f"economy.market.margin_per_kg_cap_usd = {mkt.get('margin_per_kg_cap_usd')!r}, "
        f"want {CAP_MARGIN_PER_KG}"
    )


def test_stopover_legs_real_and_bounded():
    """Every stopover flight: airline operates both legs; distance sane; label honest."""
    routes = _openflights_route_set()
    violations: list[str] = []
    n = 0
    for ffile in (DATA / "flights").glob("*.json"):
        if ffile.stem == "_manifest":
            continue
        for f in json.loads(ffile.read_text(encoding="utf-8")):
            stops = f.get("stop_airports") or []
            if not stops:
                continue
            n += 1
            al = str(f.get("operating_airline_id", ""))
            origin, dest, hub = str(f["origin_iata"]), str(f["destination_iata"]), str(stops[0])
            src = str(f.get("data_source", ""))
            if not ((al, origin, hub) in routes and (al, hub, dest) in routes):
                violations.append(f"{al} {origin}-{hub}-{dest} legs not operated ({src})")
            if float(f.get("distance_km", 0.0)) > ANTIPODAL_KM:
                violations.append(f"{origin}-{dest} distance {f.get('distance_km')} > antipodal {ANTIPODAL_KM}")
            if src == "synthetic_stopover" and (al, origin, dest) not in routes:
                violations.append(f"{al} {origin}-{dest} labeled synthetic_stopover without real OD route")
    assert not violations, f"{len(violations)}/{n} stopover contract violations, e.g. {violations[:5]}"


def test_mct_transfer_edges():
    """International transfer edges must honor international_min (120); domestic 75/90."""
    airports = {a["iata"]: a for a in WORLD["airports"]}
    violations: list[str] = []
    n = 0
    for ffile in (DATA / "transfers").glob("*.json"):
        origin = ffile.stem.upper()
        oc = airports[origin].get("country_id")
        for dest, edge_list in json.loads(ffile.read_text(encoding="utf-8")).items():
            dc = airports[dest].get("country_id")
            for e in edge_list:
                hub = str(e["hub"])
                hc = airports[hub].get("country_id")
                n += 1
                international = (oc != hc) or (hc != dc)
                mct = int(e["mct_minutes"])
                if international and mct < 120:
                    violations.append(f"{origin}->{dest} via {hub}: mct {mct} < 120 (international)")
                if not international and mct not in (75, 90):
                    violations.append(f"{origin}->{dest} via {hub}: mct {mct} not in {{75, 90}} (domestic)")
    assert not violations, f"{len(violations)}/{n} MCT edge violations, e.g. {violations[:5]}"


def test_challenge_config_in_data():
    """Caps + thresholds live in world.json economy.challenge; Godot reads them from data."""
    ch = WORLD["economy"].get("challenge", {})
    expected = {
        "days": 15, "cap_net_worth": 200000, "cap_cities": 60, "cap_countries": 30,
        "cap_products": 350, "cap_distance_km": 40075, "cap_single_profit": 10000,
        "cap_profit_per_hour": 200, "grade_a": 80, "grade_b": 60, "grade_c": 40,
    }
    for key, want in expected.items():
        assert ch.get(key) == want, f"economy.challenge.{key} = {ch.get(key)!r}, want {want!r}"
    src = (GAME / "scripts" / "systems" / "ChallengeSystem.gd").read_text(encoding="utf-8")
    assert '"challenge"' in src, "ChallengeSystem.gd must read caps/thresholds from economy data"


def test_expo_export_carries_challenge_block():
    from tools.export_expo_data import build_snapshot

    snap = build_snapshot()
    ch = snap.get("economy", {}).get("challenge", {})
    assert ch.get("days") == 15 and ch.get("cap_products") == 350 and ch.get("grade_a") == 80, (
        f"expo snapshot missing economy.challenge block: {ch}"
    )


def test_expo_declared_mapping():
    """The demo economy must declare its mapping to world.json so drift fails CI."""
    gd = (ROOT / "ios" / "expo" / "src" / "gameData.js").read_text(encoding="utf-8")
    assert "DEMO_SCALE" in gd, (
        "expo demo must declare DEMO_SCALE mapping to world.json economy "
        "(see ios/expo/src/gameData.js economy mapping block)"
    )


def test_pipeline_double_run_byte_identical():
    """P0 ratchet: two pipeline runs with different PYTHONHASHSEED must produce
    byte-identical artifacts. Exemption (documented): meta.generated_at — the
    UI-displayed provenance timestamp — is normalized before comparison.

    The pipeline writes to the repo's fixed game/data + etl/out paths, so the
    pre-test state is snapshotted and restored afterward — a 50-city regen
    must not clobber the full dataset other tests read.
    """
    with tempfile.TemporaryDirectory(prefix="gdlc-det-") as tmp:
        tmp_path = Path(tmp)
        data_snap = tmp_path / "repo-data"
        out_snap = tmp_path / "repo-out"
        shutil.copytree(DATA, data_snap)
        shutil.copytree(ROOT / "etl" / "out", out_snap)
        try:
            for tag, seed in (("run1", "1"), ("run2", "424242")):
                env = dict(os.environ, PYTHONHASHSEED=seed)
                proc = subprocess.run(
                    [sys.executable, "etl/scripts/run_pipeline.py"],
                    cwd=ROOT, env=env, capture_output=True, text=True, timeout=900,
                )
                assert proc.returncode == 0, f"pipeline run failed ({tag}): {proc.stderr[-800:]}"
                snap = tmp_path / tag
                shutil.copytree(DATA, snap / "data")
                shutil.copytree(ROOT / "etl" / "out", snap / "out")
        finally:
            shutil.rmtree(DATA)
            shutil.rmtree(ROOT / "etl" / "out")
            shutil.copytree(data_snap, DATA)
            shutil.copytree(out_snap, ROOT / "etl" / "out")

        _normalize_generated_at(tmp_path / "run1" / "data" / "world.json")
        _normalize_generated_at(tmp_path / "run2" / "data" / "world.json")

        differing = []
        for root, _, files in os.walk(tmp_path / "run1"):
            for name in files:
                if name == ".DS_Store":  # macOS Finder artifact, not pipeline output
                    continue
                rel = Path(root).relative_to(tmp_path / "run1") / name
                other = tmp_path / "run2" / rel
                if name == "world.json":
                    a = json.loads((Path(root) / name).read_text(encoding="utf-8"))
                    b = json.loads(other.read_text(encoding="utf-8"))
                    if a != b:
                        differing.append(str(rel))
                elif name.endswith(".sqlite") and name == "world.sqlite":
                    if not _sqlite_equal_except_meta(Path(root) / name, other):
                        differing.append(str(rel))
                elif not filecmp.cmp(Path(root) / name, other, shallow=False):
                    differing.append(str(rel))
        assert not differing, (
            f"{len(differing)} artifacts drift across runs with different PYTHONHASHSEED, "
            f"e.g. {differing[:8]}"
        )


def _normalize_generated_at(path: Path) -> None:
    data = json.loads(path.read_text(encoding="utf-8"))
    data.setdefault("meta", {})["generated_at"] = ""
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")


def _sqlite_equal_except_meta(a: Path, b: Path) -> bool:
    def tables(con: sqlite3.Connection) -> list[str]:
        return [r[0] for r in con.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name != 'meta'"
        ).fetchall()]

    con_a, con_b = sqlite3.connect(a), sqlite3.connect(b)
    try:
        ta, tb = tables(con_a), tables(con_b)
        if ta != tb:
            return False
        for table in ta:
            rows_a = con_a.execute(f"SELECT * FROM {table}").fetchall()
            rows_b = con_b.execute(f"SELECT * FROM {table}").fetchall()
            if rows_a != rows_b:
                return False
        return True
    finally:
        con_a.close()
        con_b.close()
