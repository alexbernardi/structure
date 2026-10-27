"""Docker integration tests: the containerised dedicated server, restart persistence and Scenario B
(two isolated environments running concurrently). Native bots connect through the published UDP ports.

Run: python TOOLS/cli/structure.py test docker   (builds structure-server:test from the current tree)
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "TOOLS" / "cli"))

from structure_cli import buildinfo, builds, envs, godot, paths, procs  # noqa: E402

RUN_ROOT = paths.TEST_RUNS / f"docker-{buildinfo.utc_stamp()}"
IMAGE = os.environ.get("STRUCTURE_TEST_IMAGE", "")


def setUpModule() -> None:
    global IMAGE
    if subprocess.run(["docker", "info"], capture_output=True).returncode != 0:
        raise unittest.SkipTest("Docker daemon not available")
    godot.import_project(paths.SANDBOX_PROJECT)
    if not IMAGE:
        IMAGE = builds.build_server(tag=builds.TEST_TAG, overwrite=True)


class DockerServerTest(unittest.TestCase):
    def setUp(self) -> None:
        self.run_dir = RUN_ROOT / self._testMethodName
        shutil.rmtree(self.run_dir, ignore_errors=True)
        self.run_dir.mkdir(parents=True)
        self.started: list[envs.Environment] = []

    def tearDown(self) -> None:
        for env in self.started:
            try:
                envs.down(env)
            except envs.EnvError as exc:
                print(exc)

    def make_env(self, name: str, world: str, seed: int) -> envs.Environment:
        env = envs.ephemeral(name, procs.free_udp_port(), world, seed, self.run_dir / name)
        envs.up(env, IMAGE)
        self.started.append(env)
        envs.wait_for_log_event(env, "server.ready", 90)
        return env

    def progress(self, env: envs.Environment) -> int:
        return json.loads(env.world_file.read_text(encoding="utf-8"))["sites"][0]["deposited"]

    def test_container_serves_clients_and_persists_across_recreation(self) -> None:
        env = self.make_env("test-dock-a", "dock", 77)
        a = procs.start_bot(self.run_dir, env.port, "alice", "gather:1", wait_players=2, until_progress=2)
        b = procs.start_bot(self.run_dir, env.port, "bob", "gather:1", wait_players=2, until_progress=2)
        (code_a, rep_a), (code_b, rep_b) = procs.finish_bot(*a), procs.finish_bot(*b)
        self.assertEqual((code_a, code_b), (0, 0), f"{rep_a.get('errors')} {rep_b.get('errors')}")
        self.assertIn("bob", rep_a["players_seen"])
        self.assertEqual(rep_a["server"]["image"], IMAGE, "clients can identify the server build")
        state = envs.container_state(env)
        self.assertEqual(state["health"], "healthy")
        envs.down(env)  # docker stop -> entrypoint -> graceful save (logging verified in the next test)
        self.assertEqual(self.progress(env), 2, "progress on the bind-mounted volume")
        envs.up(env, IMAGE)  # brand-new container, same storage
        envs.wait_for_log_event(env, "server.ready", 90)
        self.assertEqual(envs.log_events(env, "world.loaded")[0]["site_progress"], 2)
        code, rep = procs.run_bot(self.run_dir, env.port, "visitor", "observe")
        self.assertEqual((code, rep["initial_progress"]), (0, 2))
        engine_errors = [ln for ln in envs.container_logs(env).splitlines() if ln.startswith(("ERROR:", "SCRIPT ERROR:"))]
        self.assertEqual(engine_errors, [])

    def test_docker_stop_saves_and_logs_shutdown(self) -> None:
        env = self.make_env("test-dock-stop", "stopper", 5)
        self.assertEqual(procs.run_bot(self.run_dir, env.port, "builder", "gather:1")[0], 0)
        subprocess.run(["docker", "stop", "--time", "20", env.container], capture_output=True, timeout=60)
        logs = envs.container_logs(env)
        self.assertIn('"entrypoint.stop_signal"', logs)
        self.assertIn('"server.stopped"', logs)
        self.assertEqual(envs.container_state(env)["exit_code"], 0)
        self.assertFalse(env.status_file.exists(), "lease released on graceful stop")
        self.assertEqual(self.progress(env), 1)

    def test_scenario_b_isolated_environments_run_concurrently(self) -> None:
        env_a = self.make_env("test-iso-a", "iso-a", 101)
        env_b = self.make_env("test-iso-b", "iso-b", 202)
        self.assertNotEqual(env_a.port, env_b.port)
        self.assertNotEqual(env_a.data_dir.resolve(), env_b.data_dir.resolve())
        self.assertTrue(envs.container_state(env_a)["running"] and envs.container_state(env_b)["running"])
        self.assertEqual(procs.run_bot(self.run_dir, env_a.port, "builder", "gather:2")[0], 0)
        code_b, rep_b = procs.run_bot(self.run_dir, env_b.port, "observer", "observe")
        self.assertEqual(code_b, 0)
        self.assertEqual(rep_b["final_progress"], 0, "work in iso-a never reaches iso-b")
        self.assertEqual(rep_b["env"], "test-iso-b")
        self.assertEqual(self.progress(env_a), 2)
        self.assertEqual(self.progress(env_b), 0)
        doc_a = json.loads(env_a.world_file.read_text(encoding="utf-8"))
        doc_b = json.loads(env_b.world_file.read_text(encoding="utf-8"))
        self.assertEqual((doc_a["world_id"], doc_a["seed"]), ("iso-a", 101))
        self.assertEqual((doc_b["world_id"], doc_b["seed"]), ("iso-b", 202))


if __name__ == "__main__":
    unittest.main(verbosity=2)
