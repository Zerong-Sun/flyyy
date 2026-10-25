"""Contract tests for tools/export_expo_data.py (Expo 20-hub snapshot)."""
from __future__ import annotations

import unittest
from pathlib import Path

from tools.export_expo_data import HUBS_PATH, OUT_PATH, WORLD_PATH, build_snapshot, validate_assets


class ExpoExportContractTest(unittest.TestCase):
    def test_hubs_config_exists(self):
        self.assertTrue(HUBS_PATH.is_file())
        hubs = __import__("json").loads(HUBS_PATH.read_text(encoding="utf-8"))
        self.assertGreaterEqual(len(hubs), 20)

    def test_snapshot_has_cities_and_assets(self):
        self.assertTrue(WORLD_PATH.is_file())
        snapshot = build_snapshot()
        self.assertGreaterEqual(snapshot["meta"]["hub_count"], 20)
        self.assertGreater(snapshot["meta"]["product_count"], 0)
        warnings = validate_assets(snapshot)
        self.assertEqual(warnings, [], msg=warnings)
        # Every hub needs a hero asset registered in src/assets.js (Metro literal).
        assets_js = Path("ios/expo/src/assets.js")
        if assets_js.is_file():
            text = assets_js.read_text(encoding="utf-8")
            for city in snapshot["cities"]:
                self.assertIn(city["hero"].replace("assets/", ""), text, msg=city["hero"])
        # Optional on-disk artifact from a prior export run
        if OUT_PATH.is_file():
            data = __import__("json").loads(OUT_PATH.read_text(encoding="utf-8"))
            self.assertEqual(data["meta"]["schema_version"], "expo-demo-1")
            self.assertGreaterEqual(data["meta"]["hub_count"], 20)


if __name__ == "__main__":
    unittest.main()


def test_mobile_runtime_matches_generated_contract():
    import json
    snapshot = build_snapshot()
    runtime_path = HUBS_PATH.parents[1] / 'expo/src/worldContent.js'
    text = runtime_path.read_text(encoding='utf-8')
    runtime = json.loads(text.split('export const WORLD_CONTENT = ', 1)[1].rstrip(';\n'))
    expected = {key: snapshot[key] for key in ('cities', 'routes', 'mobile_balance', 'journey_events', 'merchant_rules')}
    assert runtime == json.loads(json.dumps(expected))
    assert all(isinstance(c['lat'], (float, int)) and isinstance(c['lon'], (float, int)) for c in runtime['cities'])
    assert 'hong_kong' in {c['id'] for c in runtime['cities']}
    assert all(a != b for a, b in runtime['routes'])
