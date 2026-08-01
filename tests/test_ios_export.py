import unittest
from pathlib import Path

from tools.export_ios_data import (
    BEGIN_MARKER,
    END_MARKER,
    HTML_PATH,
    WORLD_PATH,
    build_snapshot,
    load_json,
    validate,
)


class IOSExportContractTest(unittest.TestCase):
    def test_snapshot_contract_and_embedded_html(self):
        snapshot = build_snapshot()
        validate(snapshot)

        self.assertEqual(snapshot["meta"]["city_count"], 30)
        self.assertEqual(snapshot["meta"]["product_count"], 200)
        self.assertEqual(snapshot["meta"]["route_count"], len(snapshot["routes"]))
        self.assertEqual(snapshot["meta"]["flight_count"], len(snapshot["flights"]))
        world = load_json(WORLD_PATH)
        world_pairs = {(route["origin"], route["destination"]) for route in world["routes"]}
        snapshot_pairs = {(route["origin_iata"], route["destination_iata"]) for route in snapshot["routes"]}
        self.assertTrue(snapshot_pairs <= world_pairs)
        self.assertTrue(all(product["home"] for product in snapshot["products"]))
        self.assertTrue(all(product["category"] for product in snapshot["products"]))
        self.assertTrue(all(product["w"] > 0 for product in snapshot["products"]))

        html = HTML_PATH.read_text(encoding="utf-8")
        self.assertEqual(html.count(BEGIN_MARKER), 1)
        self.assertEqual(html.count(END_MARKER), 1)
        self.assertNotIn("const C=", html)
        self.assertNotIn("const AIRLINE=", html)
        self.assertNotIn("const FACTORS=", html)
        self.assertNotIn("function factorFor", html)

        for city in snapshot["cities"]:
            asset = Path(HTML_PATH.parent, city["hero"])
            self.assertTrue(asset.exists(), f"missing city asset: {asset}")
        for product in snapshot["products"]:
            asset = Path(HTML_PATH.parent, product["icon"])
            self.assertTrue(asset.exists(), f"missing product asset: {asset}")
