import unittest

import toolhelpers  # noqa: F401  (sets sys.path)
from structure_cli import compat

BUILD = {"build_version": "0.2.0", "protocol_version": 3, "world_schema_version": 4, "min_world_schema_version": 2}


class CompatTest(unittest.TestCase):
    def test_same_protocol_is_compatible_even_with_different_builds(self):
        ok, reason = compat.protocol_compatible({"protocol_version": 3, "build_version": "0.1.9"}, BUILD)
        self.assertTrue(ok)
        self.assertIn("builds differ", reason)

    def test_protocol_mismatch_is_incompatible(self):
        ok, reason = compat.protocol_compatible({"protocol_version": 2, "build_version": "0.2.0"}, BUILD)
        self.assertFalse(ok)
        self.assertIn("v2", reason)

    def test_world_schema_rules(self):
        self.assertEqual(compat.world_loadable(4, BUILD)[0], True)
        ok, reason = compat.world_loadable(3, BUILD)
        self.assertTrue(ok)
        self.assertIn("migration", reason)
        self.assertFalse(compat.world_loadable(5, BUILD)[0], "newer worlds are refused")
        self.assertFalse(compat.world_loadable(1, BUILD)[0], "worlds older than the migration floor are refused")


if __name__ == "__main__":
    unittest.main()
