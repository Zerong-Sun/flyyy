"""Unit tests for the deterministic per-(product, city) remote demand factor.

Guards the ETL change that stops every product's best market from collapsing to
a single city (the highest COUNTRY_PRICE_LEVEL, GB=1.20). The factor must be
deterministic across pipeline runs and stay within its configured bounds.
"""
from __future__ import annotations


def test_remote_demand_is_deterministic():
    from etl.scripts import run_pipeline as rp

    assert rp._remote_demand("p1", "c1") == rp._remote_demand("p1", "c1")
    assert rp._remote_demand("steel_pipes", "london") == rp._remote_demand("steel_pipes", "london")


def test_remote_demand_within_bounds():
    from etl.scripts import run_pipeline as rp

    for pid in ("a", "b", "c", "d"):
        for cid in ("x", "y", "z"):
            v = rp._remote_demand(pid, cid)
            assert 0.75 <= v <= 1.30, f"_remote_demand({pid!r}, {cid!r}) = {v} out of bounds"


def test_remote_demand_varies_across_products():
    from etl.scripts import run_pipeline as rp

    vals = {rp._remote_demand(f"p{i}", "london") for i in range(100)}
    assert len(vals) >= 20, f"demand factor nearly constant: only {len(vals)} distinct values"
