import json
import os
import time
import unittest
from unittest import mock

import toolhelpers
from structure_cli import envs, paths, snapshots

BUILD = {"build_version": "0.1.0", "protocol_version": 1, "world_schema_version": 1, "min_world_schema_version": 1}


def world_doc(world_id="snapworld", schema=1, progress=3):
    return {"schema_version": schema, "world_id": world_id, "seed": 9, "spawn_counter": 12, "revision": 20,
            "resources": [], "sites": [{"id": "site_0", "pos": [0, 0, 0], "deposited": progress, "contributors": {}}],
            "server_build": {"build": "0.1.0"}}


class SnapshotTest(unittest.TestCase):
    def setUp(self):
        self.tmp = toolhelpers.temp_dir("snap")
        self.patches = [mock.patch.object(paths, "SNAPSHOTS", self.tmp / "snapshots"),
                        mock.patch.object(envs, "container_state", return_value=None)]
        for p in self.patches:
            p.start()
        self.env = envs.ephemeral("snaptest", 25999, "snapworld", 9, self.tmp / "env")
        self.write_world(world_doc())

    def tearDown(self):
        for p in self.patches:
            p.stop()
        toolhelpers.cleanup(self.tmp)

    def write_world(self, doc):
        self.env.world_file.parent.mkdir(parents=True, exist_ok=True)
        self.env.world_file.write_text(json.dumps(doc), encoding="utf-8")

    def progress(self):
        return json.loads(self.env.world_file.read_text(encoding="utf-8"))["sites"][0]["deposited"]

    def test_create_and_list(self):
        meta = snapshots.create(self.env, "Before Big Change!")
        self.assertTrue(meta["id"].endswith("before-big-change"))
        self.assertEqual((meta["schema_version"], meta["site_progress"]), (1, 3))
        self.assertEqual([m["id"] for m in snapshots.list_snapshots("snaptest")], [meta["id"]])

    def test_restore_requires_confirmation_and_backs_up_current_world(self):
        snap = snapshots.create(self.env, "three")
        self.write_world(world_doc(progress=7))
        (self.env.world_file.parent / "world.json.bak").write_text("{}", encoding="utf-8")
        with self.assertRaisesRegex(snapshots.SnapshotError, "--yes"):
            snapshots.restore(self.env, snap["id"], BUILD)
        self.assertEqual(self.progress(), 7, "nothing changed without --yes")
        result = snapshots.restore(self.env, snap["id"], BUILD, yes=True)
        self.assertEqual(self.progress(), 3)
        backup_dir = paths.SNAPSHOTS / "snaptest" / result["backup"]
        self.assertEqual(json.loads((backup_dir / "world.json").read_text())["sites"][0]["deposited"], 7, "replaced world kept")
        self.assertTrue((backup_dir / "world.json.bak").is_file(), "stale backup moved out of the data dir")
        self.assertFalse((self.env.world_file.parent / "world.json.bak").exists())

    def test_restore_refuses_newer_schema(self):
        self.write_world(world_doc(schema=2))
        snap = snapshots.create(self.env, "future")
        with self.assertRaisesRegex(snapshots.SnapshotError, "newer"):
            snapshots.restore(self.env, snap["id"], BUILD, yes=True)

    def test_restore_refuses_other_world_unless_allowed(self):
        self.write_world(world_doc(world_id="elsewhere"))
        snap = snapshots.create(self.env, "foreign")
        with self.assertRaisesRegex(snapshots.SnapshotError, "elsewhere"):
            snapshots.restore(self.env, snap["id"], BUILD, yes=True)
        snapshots.restore(self.env, snap["id"], BUILD, yes=True, allow_other_world=True)

    def test_restore_refuses_while_server_runs(self):
        snap = snapshots.create(self.env, "live")
        self.env.status_file.parent.mkdir(parents=True, exist_ok=True)
        self.env.status_file.write_text("{}", encoding="utf-8")
        os.utime(self.env.status_file, (time.time(), time.time()))
        with self.assertRaisesRegex(snapshots.SnapshotError, "running"):
            snapshots.restore(self.env, snap["id"], BUILD, yes=True)

    def test_restore_refuses_tampered_snapshot(self):
        snap = snapshots.create(self.env, "tampered")
        (paths.SNAPSHOTS / "snaptest" / snap["id"] / "world.json").write_text(json.dumps(world_doc(progress=999)))
        with self.assertRaisesRegex(snapshots.SnapshotError, "integrity"):
            snapshots.restore(self.env, snap["id"], BUILD, yes=True)

    def test_snapshot_of_corrupt_world_is_refused(self):
        self.env.world_file.write_text("{ nope", encoding="utf-8")
        with self.assertRaisesRegex(snapshots.SnapshotError, "not valid JSON"):
            snapshots.create(self.env, "corrupt")


if __name__ == "__main__":
    unittest.main()
