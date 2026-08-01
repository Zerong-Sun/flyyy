"""Contract tests for tools/export_expo_data.py (Expo 12-hub snapshot)."""
from __future__ import annotations

import unittest
from pathlib import Path

from tools.export_expo_data import HUBS_PATH, OUT_PATH, WORLD_PATH, build_snapshot, validate_assets


class ExpoExportContractTest(unittest.TestCase):
    def test_hubs_config_exists(self):
        self.assertTrue(HUBS_PATH.is_file())
        hubs = __import__("json").loads(HUBS_PATH.read_text(encoding="utf-8"))
        self.assertGreaterEqual(len(hubs), 12)

    def test_snapshot_has_cities_and_assets(self):
        self.assertTrue(WORLD_PATH.is_file())
        snapshot = build_snapshot()
        self.assertEqual(snapshot["meta"]["hub_count"], 12)
        self.assertGreater(snapshot["meta"]["product_count"], 0)
        warnings = validate_assets(snapshot)
        self.assertEqual(warnings, [], msg=warnings)
        # Optional on-disk artifact from a prior export run
        if OUT_PATH.is_file():
            data = __import__("json").loads(OUT_PATH.read_text(encoding="utf-8"))
            self.assertEqual(data["meta"]["schema_version"], "expo-demo-1")


if __name__ == "__main__":
    unittest.main()
