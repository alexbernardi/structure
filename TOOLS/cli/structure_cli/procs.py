"""Process orchestration for servers and bots (used by tests, scenarios and benchmarks).

Each process writes stdout+stderr to a log file. Structured events are JSON lines; engine errors are
plain lines starting with "ERROR:" or "SCRIPT ERROR:".
"""
from __future__ import annotations

import json
import os
import socket
import subprocess
import time
from pathlib import Path

from . import paths, toolchain


def free_udp_port(start: int = 25000, end: int = 26000) -> int:
    """A UDP port that is currently bindable on 127.0.0.1 (best effort; ports are probed in order)."""
    seed = (os.getpid() * 7919 + int(time.time() * 1000)) % (end - start)
    for offset in range(end - start):
        port = start + (seed + offset) % (end - start)
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
            try:
                sock.bind(("127.0.0.1", port))
            except OSError:
                continue
            return port
    raise RuntimeError("no free UDP port found")


class GodotProcess:
    def __init__(self, name: str, user_args: list[str], log_path: Path, project: Path = paths.SANDBOX_PROJECT):
        self.name = name
        self.log_path = log_path
        self.cmd = [str(toolchain.ensure_godot()), "--headless", "--path", str(project), "--", *user_args]
        self.proc: subprocess.Popen | None = None
        self._log_handle = None

    def start(self) -> "GodotProcess":
        self.log_path.parent.mkdir(parents=True, exist_ok=True)
        self._log_handle = open(self.log_path, "w", encoding="utf-8")
        self.proc = subprocess.Popen(self.cmd, stdout=self._log_handle, stderr=subprocess.STDOUT, cwd=paths.REPO)
        return self

    def lines(self) -> list[str]:
        try:
            return self.log_path.read_text(encoding="utf-8", errors="replace").splitlines()
        except FileNotFoundError:
            return []

    def events(self, evt: str | None = None) -> list[dict]:
        out = []
        for line in self.lines():
            if line.startswith("{"):
                try:
                    record = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if evt is None or record.get("evt") == evt:
                    out.append(record)
        return out

    def engine_errors(self) -> list[str]:
        return [ln for ln in self.lines() if ln.startswith(("ERROR:", "SCRIPT ERROR:"))]

    def wait_for_event(self, evt: str, timeout: float = 30.0, predicate=None) -> dict:
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            for record in self.events(evt):
                if predicate is None or predicate(record):
                    return record
            if self.proc and self.proc.poll() is not None:
                break
            time.sleep(0.1)
        tail = "\n".join(self.lines()[-25:])
        raise TimeoutError(f"{self.name}: no '{evt}' event within {timeout}s (exit={self.returncode()})\n{tail}")

    def returncode(self) -> int | None:
        return self.proc.poll() if self.proc else None

    def wait(self, timeout: float) -> int:
        assert self.proc
        try:
            return self.proc.wait(timeout=timeout)
        finally:
            self._close_log()

    def kill(self) -> None:
        if self.proc and self.proc.poll() is None:
            self.proc.kill()
            self.proc.wait(timeout=10)
        self._close_log()

    def _close_log(self) -> None:
        if self._log_handle and self.proc and self.proc.poll() is not None:
            self._log_handle.close()
            self._log_handle = None


class ServerProcess(GodotProcess):
    def __init__(self, data_dir: Path, port: int, world_id: str = "test", seed: int = 1337, env_id: str = "test",
                 log_path: Path | None = None, extra: list[str] | None = None):
        self.data_dir = data_dir
        self.port = port
        args = ["--server", f"--port={port}", f"--data-dir={data_dir}", f"--world-id={world_id}", f"--seed={seed}",
                f"--env-id={env_id}", "--metrics-interval=1", *(extra or [])]
        super().__init__(f"server:{env_id}", args, log_path or data_dir.parent / f"server-{port}.log")

    def start_and_wait_ready(self, timeout: float = 30.0) -> dict:
        self.start()
        return self.wait_for_event("server.ready", timeout)

    def request_shutdown(self) -> None:
        control = self.data_dir / "runtime" / "shutdown.request"
        control.parent.mkdir(parents=True, exist_ok=True)
        control.touch()

    def stop(self, timeout: float = 15.0) -> int:
        """Graceful stop via the control file; kills only if the server does not exit in time."""
        if self.proc is None or self.proc.poll() is not None:
            return self.returncode() or 0
        self.request_shutdown()
        try:
            return self.wait(timeout)
        except subprocess.TimeoutExpired:
            self.kill()
            return -9


def bot_args(port: int, name: str, plan: str, report: Path, *, wait_players: int = 1, until_progress: int = -1,
             timeout: float = 60.0, hold: float = 0.0, extra: list[str] | None = None) -> list[str]:
    return ["--bot", f"--connect=127.0.0.1:{port}", f"--name={name}", f"--bot-plan={plan}", f"--bot-report={report}",
            f"--bot-wait-players={wait_players}", f"--bot-until-progress={until_progress}", f"--bot-timeout={timeout}",
            f"--bot-hold={hold}", *(extra or [])]


def start_bot(run_dir: Path, port: int, name: str, plan: str, **kwargs) -> tuple[GodotProcess, Path]:
    report = run_dir / f"bot-{name}.json"
    report.unlink(missing_ok=True)
    proc = GodotProcess(f"bot:{name}", bot_args(port, name, plan, report, **kwargs), run_dir / f"bot-{name}.log").start()
    return proc, report


def finish_bot(proc: GodotProcess, report: Path, timeout: float = 120.0) -> tuple[int, dict]:
    try:
        code = proc.wait(timeout)
    except subprocess.TimeoutExpired:
        proc.kill()
        code = -9
    data = json.loads(report.read_text(encoding="utf-8")) if report.is_file() else {}
    return code, data


def run_bot(run_dir: Path, port: int, name: str, plan: str, **kwargs) -> tuple[int, dict]:
    proc, report = start_bot(run_dir, port, name, plan, **kwargs)
    return finish_bot(proc, report)
