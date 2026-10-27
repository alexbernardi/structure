"""Multiplayer integration tests: a native headless server and headless bot clients.

Covers: headless server startup, connectivity, two-client synchronisation, server-authoritative
interactions (incl. cheating clients), protocol checks, persistence across graceful and crash restarts,
and data-safety refusals. Run: python TOOLS/cli/structure.py test multiplayer
"""
from __future__ import annotations

import datetime
import json
import re
import shutil
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "TOOLS" / "cli"))

from structure_cli import buildinfo, godot, paths, procs  # noqa: E402

RUN_ROOT = paths.TEST_RUNS / f"multiplayer-{buildinfo.utc_stamp()}"
# Engine errors that are expected because a test provokes them on purpose.
FORGED_RPC_ERROR = re.compile(r"RPC '_rpc_event' is not allowed|not allowed on node")


def _epoch(event: dict) -> float:
    return datetime.datetime.strptime(event["ts"], "%Y-%m-%dT%H:%M:%S.%fZ").replace(tzinfo=datetime.timezone.utc).timestamp()


def setUpModule() -> None:
    godot.import_project(paths.SANDBOX_PROJECT)
    buildinfo.write_sandbox_manifest()


class MultiplayerTest(unittest.TestCase):
    def setUp(self) -> None:
        self.run_dir = RUN_ROOT / self._testMethodName
        shutil.rmtree(self.run_dir, ignore_errors=True)
        self.data_dir = self.run_dir / "data"
        self.data_dir.mkdir(parents=True)
        self.port = procs.free_udp_port()
        self.servers: list[procs.ServerProcess] = []

    def tearDown(self) -> None:
        for server in self.servers:
            server.kill()

    def start_server(self, **kwargs) -> procs.ServerProcess:
        server = procs.ServerProcess(self.data_dir, self.port, log_path=self.run_dir / f"server-{len(self.servers)}.log", **kwargs)
        self.servers.append(server)
        server.start_and_wait_ready()
        return server

    def world_doc(self) -> dict:
        return json.loads((self.data_dir / "world" / "world.json").read_text(encoding="utf-8"))

    def assert_no_engine_errors(self, proc: procs.GodotProcess, allowed: re.Pattern | None = None) -> None:
        lines = proc.lines()
        unexpected = []
        for i, line in enumerate(lines):
            if line.startswith(("ERROR:", "SCRIPT ERROR:")):
                context = " ".join(lines[i:i + 2])
                if allowed is None or not allowed.search(context):
                    unexpected.append(context)
        self.assertEqual(unexpected, [], f"{proc.name} logged unexpected engine errors")

    # ---------------------------------------------------------------------------------------------- tests

    def test_two_clients_cooperate_and_observe_each_other(self) -> None:
        server = self.start_server()
        a = procs.start_bot(self.run_dir, self.port, "alice", "gather:1", wait_players=2, until_progress=2)
        b = procs.start_bot(self.run_dir, self.port, "bob", "gather:1", wait_players=2, until_progress=2)
        code_a, rep_a = procs.finish_bot(*a)
        code_b, rep_b = procs.finish_bot(*b)
        self.assertEqual((code_a, code_b), (0, 0), f"bots failed: {rep_a.get('errors')} {rep_b.get('errors')}")
        for rep, other in ((rep_a, "bob"), (rep_b, "alice")):
            self.assertEqual(rep["final_progress"], 2, "both contributions visible to every client")
            self.assertIn(other, rep["players_seen"], "clients see each other")
            self.assertGreater(rep["moves_seen"].get(other, 0), 5, "remote movement is replicated")
            self.assertEqual(rep["corrections"], 0, "honest movement is never corrected")
        server.wait_for_event("site.progress", 5, lambda e: e["deposited"] == 2)
        server.stop()
        self.assertEqual(self.world_doc()["sites"][0]["deposited"], 2)
        self.assertEqual(sorted(self.world_doc()["sites"][0]["contributors"]), ["alice", "bob"])
        self.assert_no_engine_errors(server)

    def test_server_rejects_cheating_client(self) -> None:
        server = self.start_server()
        code, rep = procs.run_bot(self.run_dir, self.port, "mallory", "cheat")
        failed = [c for c in rep.get("cheats", []) if not c["ok"]]
        self.assertEqual(code, 0, f"cheat checks failed: {failed} errors={rep.get('errors')}")
        self.assertGreaterEqual(len(rep["cheats"]), 8)
        observer_code, observer = procs.run_bot(self.run_dir, self.port, "observer", "observe")
        self.assertEqual(observer_code, 0)
        self.assertEqual(observer["final_progress"], 0, "no cheat changed construction progress")
        violations = server.events("net.violation")
        self.assertGreaterEqual(len(violations), 4, "malformed RPCs were detected as violations")
        server.stop()
        self.assertEqual(self.world_doc()["sites"][0]["deposited"], 0)
        self.assert_no_engine_errors(server, allowed=FORGED_RPC_ERROR)

    def test_protocol_mismatch_is_rejected(self) -> None:
        server = self.start_server()
        code, rep = procs.run_bot(self.run_dir, self.port, "oldclient", "observe", timeout=15, extra=["--protocol-override=999"])
        self.assertNotEqual(code, 0)
        self.assertEqual(rep["connection_failed"], "protocol_mismatch")
        rejected = server.wait_for_event("net.auth_rejected", 5)
        self.assertEqual(rejected["reason"], "protocol_mismatch")
        self.assertEqual(server.events("player.joined"), [], "mismatched client never joined the world")

    def test_server_full_is_rejected(self) -> None:
        self.start_server(extra=["--max-players=1"])
        first = procs.start_bot(self.run_dir, self.port, "first", "observe", hold=4)
        self.servers[0].wait_for_event("player.joined", 15)
        code, rep = procs.run_bot(self.run_dir, self.port, "second", "observe", timeout=15)
        self.assertEqual(rep["connection_failed"], "server_full")
        self.assertEqual(procs.finish_bot(*first)[0], 0)

    def test_progress_persists_across_graceful_restart(self) -> None:
        server = self.start_server(world_id="persist")
        self.assertEqual(procs.run_bot(self.run_dir, self.port, "builder", "gather:1")[0], 0)
        self.assertEqual(server.stop(), 0, "graceful exit code")
        self.assertTrue(server.events("server.stopped"), "shutdown is logged")
        self.assertFalse((self.data_dir / "runtime" / "status.json").exists(), "lease released")
        server2 = self.start_server(world_id="persist")
        self.assertEqual(server2.events("world.loaded")[0]["site_progress"], 1)
        code, rep = procs.run_bot(self.run_dir, self.port, "visitor", "observe")
        self.assertEqual((code, rep["initial_progress"]), (0, 1), "a new client sees remembered progress")
        server2.stop()

    def test_progress_survives_server_crash(self) -> None:
        server = self.start_server(world_id="crash")
        self.assertEqual(procs.run_bot(self.run_dir, self.port, "builder", "gather:1")[0], 0)
        server.kill()  # no graceful save: relies on save-on-change
        server2 = self.start_server(world_id="crash")
        self.assertTrue(server2.events("server.stale_lease_ignored"), "stale lease from the crashed server detected")
        self.assertEqual(server2.events("world.loaded")[0]["site_progress"], 1)
        server2.stop()

    def test_second_server_on_same_data_dir_is_refused(self) -> None:
        self.start_server()
        intruder = procs.ServerProcess(self.data_dir, procs.free_udp_port(), log_path=self.run_dir / "intruder.log")
        intruder.start()
        self.assertEqual(intruder.wait(30), 3)
        self.assertEqual(intruder.events("server.start_failed")[0]["reason"], "data_dir_in_use")

    def test_client_presentation_follows_server_and_exits_cleanly(self) -> None:
        """Runs the real client (world view, avatars, HUD, close path) headless while a bot plays.
        Regression for playtest 0002: closing the window sent an RPC after the session was closed."""
        server = self.start_server()
        viewer = procs.GodotProcess("client:viewer", ["--allow-headless", f"--connect=127.0.0.1:{self.port}",
                                                      "--name=viewer", "--quit-after=15"], self.run_dir / "client-viewer.log")
        viewer.start()
        server.wait_for_event("player.joined", 20, lambda e: e["name"] == "viewer")
        code, rep = procs.run_bot(self.run_dir, self.port, "builder", "gather:1", wait_players=2)
        self.assertEqual(code, 0, rep.get("errors"))
        self.assertEqual(viewer.wait(60), 0)
        sessions = viewer.events("client.session")
        self.assertEqual(len(sessions), 1, "session summary logged exactly once")
        summary = sessions[0]
        self.assertEqual(summary["reason"], "automation")
        self.assertIn("builder", summary["players_seen"], "client saw the other player join")
        self.assertEqual(summary["final_site_progress"], 1, "client presentation applied the live deposit")
        self.assertEqual(summary["corrections"], 0)
        self.assert_no_engine_errors(viewer)
        left = server.wait_for_event("player.left", 10, lambda e: e["name"] == "viewer")
        self.assertLess(_epoch(left) - _epoch(summary), 2.0, "server learns about the exit immediately, not by timeout")
        self.assert_no_engine_errors(server)

    def test_refuses_world_from_newer_schema(self) -> None:
        world = self.data_dir / "world"
        world.mkdir(parents=True)
        doc = {"schema_version": 99, "world_id": "test", "seed": 1, "spawn_counter": 0, "resources": [], "sites": []}
        (world / "world.json").write_text(json.dumps(doc), encoding="utf-8")
        before = (world / "world.json").read_bytes()
        server = procs.ServerProcess(self.data_dir, self.port, log_path=self.run_dir / "server.log")
        server.start()
        self.assertEqual(server.wait(30), 4)
        self.assertIn("newer", server.events("server.start_failed")[0]["detail"])
        self.assertEqual((world / "world.json").read_bytes(), before, "world file untouched")


if __name__ == "__main__":
    unittest.main(verbosity=2)
