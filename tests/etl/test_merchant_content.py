"""The two clients ship the same complete, authored journey catalog."""
import json
from pathlib import Path
from etl.content.runtime_data import export_runtime_data

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'etl/config/runtime'

def test_merchant_catalog_export(tmp_path):
    export_runtime_data(tmp_path)
    events = json.loads((tmp_path / 'journey_events.json').read_text())
    rules = json.loads((tmp_path / 'merchant_rules.json').read_text())
    assert len(events) == len({e['id'] for e in events}) == 30
    assert len({e['kind'] for e in events}) == 10
    assert rules['min_hours'] >= 24
    assert rules['max_chain'] == 3
    for e in events:
        for language in ('zh', 'en'):
            for field in ('title', 'body', 'action'):
                assert e[f'{field}_{language}'].strip()
        assert e['kind'] in {'lock', 'speculate', 'insurance', 'buyer', 'extend', 'rush', 'advance', 'fare', 'supply', 'tip'}
    assert events == json.loads((SOURCE / 'journey_events.json').read_text())

def test_mobile_snapshot_uses_authored_catalog():
    from tools.export_expo_data import build_snapshot
    snapshot = build_snapshot()
    assert snapshot['journey_events'] == json.loads((SOURCE / 'journey_events.json').read_text())
    assert snapshot['merchant_rules'] == json.loads((SOURCE / 'merchant_rules.json').read_text())
