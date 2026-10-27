import re
import unittest

import toolhelpers
from structure_cli import buildinfo, paths, rooms


class BuildInfoTest(unittest.TestCase):
    def test_clean_tags_are_version_and_commit(self):
        tag = buildinfo.image_tag({"build_version": "0.1.0", "git_commit": "abcdef1234567890", "git_dirty": False})
        self.assertEqual(tag, "0.1.0-abcdef1")

    def test_dirty_tags_are_unique_per_build(self):
        tag = buildinfo.image_tag({"build_version": "0.1.0", "git_commit": "abcdef1234567890", "git_dirty": True})
        self.assertRegex(tag, r"^0\.1\.0-abcdef1-dirty\.\d{8}T\d{6}Z$")

    def test_project_versions_are_read_from_project_godot(self):
        v = buildinfo.project_versions()
        self.assertRegex(v["build_version"], r"^\d+\.\d+\.\d+$")
        self.assertGreaterEqual(v["protocol_version"], 1)
        self.assertLessEqual(v["min_world_schema_version"], v["world_schema_version"])

    def test_manifest_contains_required_identity(self):
        m = buildinfo.manifest()
        for key in ("build_version", "git_commit", "godot_version", "protocol_version", "world_schema_version",
                    "asset_manifest_sha256", "integrated_systems"):
            self.assertIn(key, m)


class RoomToolsTest(unittest.TestCase):
    def test_tree_hash_ignores_line_endings(self):
        tmp = toolhelpers.temp_dir("hash")
        try:
            (tmp / "a").mkdir()
            (tmp / "b").mkdir()
            (tmp / "a" / "x.gd").write_bytes(b"extends RefCounted\nvar v := 1\n")
            (tmp / "b" / "x.gd").write_bytes(b"extends RefCounted\r\nvar v := 1\r\n")
            (tmp / "b" / "x.gd.uid").write_text("uid://whatever")
            self.assertEqual(rooms.tree_hash(tmp / "a"), rooms.tree_hash(tmp / "b"))
            (tmp / "b" / "x.gd").write_bytes(b"extends RefCounted\nvar v := 2\n")
            self.assertNotEqual(rooms.tree_hash(tmp / "a"), rooms.tree_hash(tmp / "b"))
        finally:
            toolhelpers.cleanup(tmp)

    def test_template_scaffold_blocks_promotion_until_contract_is_written(self):
        tmp = toolhelpers.temp_dir("rooms")
        try:
            folder = rooms.new_room("weather", tmp)
            self.assertNotIn("{{ROOM_NAME}}", (folder / "room.json").read_text())
            self.assertIn('"weather"', (folder / "room.json").read_text())
            problems = rooms.contract_problems("weather", tmp)
            self.assertTrue(any("placeholder" in p for p in problems), problems)
            with self.assertRaises(rooms.RoomError):
                rooms.new_room("Bad Name", tmp)
        finally:
            toolhelpers.cleanup(tmp)

    def test_movement_room_contract_is_complete_and_in_sync(self):
        self.assertEqual(rooms.contract_problems("movement"), [])
        status = rooms.integration_status("movement")
        self.assertTrue(status["integrated"])
        self.assertFalse(status["drift"], "sandbox copy must not be edited directly")

    def test_every_workshop_reference_in_agents_md_exists(self):
        text = (paths.REPO / "AGENTS.md").read_text(encoding="utf-8")
        for ref in set(re.findall(r"\]\(([^)#]+)\)", text)):
            self.assertTrue((paths.REPO / ref).exists(), f"AGENTS.md links to missing {ref}")


if __name__ == "__main__":
    unittest.main()
