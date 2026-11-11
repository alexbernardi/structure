"""Package rooms and laboratories (ADR-0010): version compatibility, content hashing, install / drift refusal,
the lab scaffold, and the shape of the movement_core room."""
import json
import shutil
import tempfile
import unittest
from pathlib import Path

import toolhelpers  # noqa: F401  (puts TOOLS/cli on sys.path)
from structure_cli import labs, packages, paths, rooms


class CompatibilityTest(unittest.TestCase):
    def test_same_version_is_current(self):
        self.assertEqual(packages.compatibility("1.2.3", "1.2.3"), "current")

    def test_older_minor_or_patch_is_a_compatible_update(self):
        self.assertEqual(packages.compatibility("1.0.0", "1.4.0"), "behind_compatible")
        self.assertEqual(packages.compatibility("1.4.0", "1.4.2"), "behind_compatible")

    def test_older_major_is_breaking(self):
        self.assertEqual(packages.compatibility("1.9.9", "2.0.0"), "behind_breaking")

    def test_newer_than_approved_is_ahead(self):
        self.assertEqual(packages.compatibility("1.1.0", "1.0.0"), "ahead")


class HashTest(unittest.TestCase):
    def test_text_line_endings_do_not_change_the_hash(self):
        self.assertEqual(packages.files_hash({"a.gd": b"x\r\ny\r\n"}), packages.files_hash({"a.gd": b"x\ny\n"}))

    def test_binary_content_is_hashed_raw(self):
        self.assertNotEqual(packages.files_hash({"a.glb": b"x\r\n"}), packages.files_hash({"a.glb": b"x\n"}))

    def test_paths_are_part_of_the_hash(self):
        self.assertNotEqual(packages.files_hash({"a.gd": b"x"}), packages.files_hash({"b.gd": b"x"}))


class MovementCoreRoomTest(unittest.TestCase):
    def test_room_is_a_package_with_a_contract(self):
        self.assertTrue(packages.is_package("movement_core"))
        self.assertEqual(rooms.contract_problems("movement_core"), [])
        self.assertTrue((packages.source_dir("movement_core") / "movement_character.gd").is_file())
        self.assertEqual(packages.mount("movement_core"), "systems/movement_core")

    def test_declared_consumers_are_installed_without_drift(self):
        st = packages.status("movement_core")
        self.assertEqual(st["missing_consumers"], [])
        for consumer in st["consumers"]:
            self.assertFalse(consumer["drift"], consumer)

    def test_workbench_cannot_install_into_itself(self):
        with self.assertRaises(packages.PackageError):
            packages.install("movement_core", packages.workbench("movement_core"))


class InstallAndScaffoldTest(unittest.TestCase):
    def setUp(self):
        paths.RUNTIME.mkdir(parents=True, exist_ok=True)
        self.tmp = Path(tempfile.mkdtemp(dir=paths.RUNTIME))

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_scaffold_installs_pins_and_refuses_hand_edits(self):
        folder = self.tmp / "unit_lab"
        pins = labs.scaffold("unit_lab", ["movement_core"], folder)
        self.assertEqual(pins, {"movement_core": packages._room("movement_core")["version"]})
        self.assertIn("unit_lab laboratory", (folder / "project.godot").read_text(encoding="utf-8"))
        record = json.loads((folder / "systems/movement_core/INTEGRATION.json").read_text(encoding="utf-8"))
        self.assertEqual(record["sha256"], packages.files_hash(packages.files_on_disk(folder / "systems/movement_core")))
        # A hand edit of the installed copy is refused on re-install unless forced.
        (folder / "systems/movement_core/movement_character.gd").write_text("# edited\n", encoding="utf-8")
        with self.assertRaises(packages.PackageError):
            packages.install("movement_core", folder)
        packages.install("movement_core", folder, force=True)
        self.assertNotIn("# edited", (folder / "systems/movement_core/movement_character.gd").read_text(encoding="utf-8"))

    def test_unknown_release_is_reported(self):
        with self.assertRaises(packages.PackageError):
            packages.files_at("movement_core", "99.0.0")

    def test_lab_names_are_validated(self):
        with self.assertRaises(labs.LabError):
            labs.create("Bad Name", [])


if __name__ == "__main__":
    unittest.main()
