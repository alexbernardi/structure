"""Benchmarks with fixed seeds. Results go to .runtime/benchmarks/; --record copies them to
TESTING/performance/baselines/ (committed) - summarise them in AGENT-WORKSHOP/INVENTORY/PERFORMANCE-BASELINES.md."""
from __future__ import annotations

import json
import os
import platform
import shutil
import statistics
import time
from pathlib import Path

from . import buildinfo, builds, envs, godot, paths, procs, rooms

BASELINES = paths.TESTING / "performance" / "baselines"


def _machine() -> dict:
    return {"os": platform.platform(), "cpu": platform.processor(), "cores": os.cpu_count(),
            "python": platform.python_version()}


def _save(name: str, result: dict, record: bool) -> Path:
    result.update({"benchmark": name, "recorded_at": buildinfo.utc_now(), "git": buildinfo.git_info()["commit"][:12],
                   "machine": _machine()})
    out = paths.RUNTIME / "benchmarks" / f"{buildinfo.utc_stamp()}-{name}.json"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    if record:
        BASELINES.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(out, BASELINES / f"{name}.json")
    return out


def _summarise_metrics(samples: list[dict]) -> dict:
    def series(key):
        return [s[key] for s in samples if s.get(key) is not None]

    def stats(key, fn=statistics.mean):
        values = series(key)
        return round(fn(values), 3) if values else None

    return {
        "intervals": len(samples),
        "tick_avg_ms": stats("tick_avg_ms"), "tick_p95_ms_max": stats("tick_p95_ms", max), "tick_max_ms": stats("tick_max_ms", max),
        "cpu_pct_avg": stats("cpu_pct"), "cpu_pct_max": stats("cpu_pct", max),
        "rss_mb_max": stats("rss_mb", max), "mem_static_mb_max": stats("mem_static_mb", max),
        "players_max": stats("players", max), "entities_avg": stats("entities"),
        "net_in_bps_avg": stats("net_in_bps"), "net_out_bps_avg": stats("net_out_bps"),
        "saves": samples[-1].get("saves") if samples else None,
        "actions_ok": samples[-1].get("actions_ok") if samples else None,
        "moves_rejected": samples[-1].get("moves_rejected") if samples else None,
    }


def server(bots: int = 8, duration: float = 30.0, seed: int = 4242, docker: bool = False, warmup: float = 5.0,
           record: bool = False) -> dict:
    run_dir = paths.TEST_RUNS / f"bench-server-{buildinfo.utc_stamp()}"
    run_dir.mkdir(parents=True)
    godot.import_project(paths.SANDBOX_PROJECT)
    buildinfo.write_sandbox_manifest()
    port = procs.free_udp_port()
    env = server_proc = None
    if docker:
        image = builds.build_server(tag=builds.TEST_TAG, overwrite=True)
        env = envs.ephemeral("bench-server", port, "bench", seed, run_dir / "env")
        env.values["STRUCTURE_METRICS_INTERVAL"] = "1"
        env.values["STRUCTURE_MAX_PLAYERS"] = str(max(16, bots))
        envs.up(env, image)
        envs.wait_for_log_event(env, "server.ready", 90)
    else:
        server_proc = procs.ServerProcess(run_dir / "data", port, world_id="bench", seed=seed,
                                          extra=[f"--max-players={max(16, bots)}"], log_path=run_dir / "server.log")
        server_proc.start_and_wait_ready()
    started = time.time()
    fleet = [procs.start_bot(run_dir, port, f"bot{i:02d}", "wander", hold=duration, timeout=duration + 60) for i in range(bots)]
    reports = [procs.finish_bot(*b, timeout=duration + 90) for b in fleet]
    events = envs.log_events(env, "server.metrics") if docker else server_proc.events("server.metrics")
    if docker:
        envs.down(env)
    else:
        server_proc.stop()
    samples = [e for e in events if _ts(e) >= started + warmup]
    result = {"mode": "docker" if docker else "native", "bots": bots, "duration_s": duration, "seed": seed, "warmup_s": warmup,
              "server": _summarise_metrics(samples),
              "bots_ok": sum(1 for code, _ in reports if code == 0),
              "deposits_total": sum(r.get("deposits", 0) for _, r in reports)}
    result["output"] = str(_save(f"server-{result['mode']}-{bots}bots", result, record).relative_to(paths.REPO))
    return result


def _ts(event: dict) -> float:
    import datetime as dt

    return dt.datetime.strptime(event["ts"], "%Y-%m-%dT%H:%M:%S.%fZ").replace(tzinfo=dt.timezone.utc).timestamp()


def client(duration: float = 15.0, bots: int = 2, record: bool = False) -> dict:
    """Opens a real window: FPS / frame time of the client connected to a native server with active bots."""
    run_dir = paths.TEST_RUNS / f"bench-client-{buildinfo.utc_stamp()}"
    run_dir.mkdir(parents=True)
    godot.import_project(paths.SANDBOX_PROJECT)
    buildinfo.write_sandbox_manifest()
    port = procs.free_udp_port()
    srv = procs.ServerProcess(run_dir / "data", port, world_id="bench", seed=4242, log_path=run_dir / "server.log")
    srv.start_and_wait_ready()
    fleet = [procs.start_bot(run_dir, port, f"bot{i}", "wander", hold=duration + 10, timeout=duration + 60) for i in range(bots)]
    cli = procs.GodotProcess("client", [f"--connect=127.0.0.1:{port}", "--name=bench", f"--quit-after={duration}", "--vsync=false"],
                             run_dir / "client.log")
    cli.cmd.remove("--headless")
    cli.start()
    cli.wait(duration + 60)
    for b in fleet:
        b[0].kill()
    srv.stop()
    metrics = cli.events("client.metrics")
    result = {"duration_s": duration, "bots": bots, "client": metrics[-1] if metrics else None,
              "engine_errors": cli.engine_errors()}
    result["output"] = str(_save("client-native", result, record).relative_to(paths.REPO))
    return result


def movement(record: bool = False) -> dict:
    result = rooms.bench_room("movement")
    result["output"] = str(_save("room-movement", result, record).relative_to(paths.REPO))
    return result
