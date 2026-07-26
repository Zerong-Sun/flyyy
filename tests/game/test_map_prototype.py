"""Phase-1 map & data prototype gates (PRD §26.1)."""
from __future__ import annotations

import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WORLD = ROOT / "game" / "data" / "world.json"
CAS = ROOT / "docs" / "CONTENT_ASSET_SPEC.md"

HUB_IATAS = {
    "ATL", "DXB", "DFW", "DEN", "LHR", "ORD", "IST", "LAX", "HND", "PVG",
    "CDG", "AMS", "CAN", "FRA", "PEK", "SIN", "ICN", "HKG", "BKK", "MIA",
}


def _load_world() -> dict:
    assert WORLD.is_file(), f"missing {WORLD}"
    return json.loads(WORLD.read_text(encoding="utf-8"))


def test_world_has_twenty_hub_airports():
    world = _load_world()
    airports = world["airports"]
    assert len(airports) == 20
    iatas = {str(a["iata"]).upper() for a in airports}
    assert iatas == HUB_IATAS
    for a in airports:
        assert a.get("icao"), a
        lat = float(a["latitude"])
        lon = float(a["longitude"])
        assert -90.0 <= lat <= 90.0
        assert -180.0 <= lon <= 180.0
        assert abs(lat) > 0.01 or abs(lon) > 0.01


def test_routes_have_no_self_loops_and_valid_endpoints():
    world = _load_world()
    iatas = {str(a["iata"]).upper() for a in world["airports"]}
    routes = world.get("routes", [])
    assert len(routes) >= 20
    for r in routes:
        o = str(r["origin"]).upper()
        d = str(r["destination"]).upper()
        assert o != d, r
        assert o in iatas and d in iatas, r


def test_great_circle_hub_hemispheres():
    """Sanity: PVG east Asia, LAX west Americas, LHR Europe, SIN near equator."""
    world = _load_world()
    by_iata = {str(a["iata"]).upper(): a for a in world["airports"]}
    pvg, lax = by_iata["PVG"], by_iata["LAX"]
    lhr, sin = by_iata["LHR"], by_iata["SIN"]
    assert float(pvg["longitude"]) > 100.0
    assert float(lax["longitude"]) < -100.0
    assert float(lhr["latitude"]) > 40.0
    assert abs(float(sin["latitude"])) < 5.0
    # Chord distance on unit sphere should be significant for PVG-LAX
    def unit(a: dict) -> tuple[float, float, float]:
        la = math.radians(float(a["latitude"]))
        lo = math.radians(float(a["longitude"]))
        return (math.cos(la) * math.cos(lo), math.sin(la), math.cos(la) * math.sin(lo))

    u0, u1 = unit(pvg), unit(lax)
    dot = max(-1.0, min(1.0, u0[0] * u1[0] + u0[1] * u1[1] + u0[2] * u1[2]))
    assert math.acos(dot) > 1.0  # > ~57° apart


def test_cas_section_0_5_inventory_present():
    text = CAS.read_text(encoding="utf-8")
    assert "### 0.5 仓库现状盘点" in text
    assert "EARTH_ALBEDO" in text
    assert "阶段一验收不依赖" in text or "不依赖美术包 D1" in text
