"""`structure.py test`: runs the automated suites and records a summary in .runtime/test-results/."""
from __future__ import annotations

import json
import shutil
import subprocess
import sys
import time

from . import assets, buildinfo, checks, godot, paths, rooms

ORDER = ["check", "tools", "import", "unit", "rooms", "pipeline", "multiplayer", "docker"]
DESCRIPTIONS = {
    "check": "static repository checks (pins, envs, system drift, asset hashes, secrets)",
    "tools": "Python tooling unit tests (snapshots, compat rules, envs, GLB validator)",
    "import": "Godot import of every project + smoke-load of all sandbox scripts/scenes",
    "unit": "sandbox GDScript unit tests (rules, persistence, protocol, config, assets)",
    "rooms": "every system room in isolation + a room freshly scaffolded from _TEMPLATE",
    "pipeline": "asset library/consumer consistency (+ Blender regeneration with --with-blender)",
    "multiplayer": "native server + bot clients: sync, authority, cheats, persistence, safety",
    "docker": "server image, container persistence, graceful stop, Scenario B isolation",
}


def _unittest(folder: str, pattern: str = "test_*.py") -> bool:
    cmd = [sys.executable, "-m", "unittest", "discover", "-s", str(paths.REPO / folder), "-p", pattern, "-v"]
    return subprocess.run(cmd, cwd=paths.REPO, timeout=3600).returncode == 0


def suite_check(_opts) -> bool:
    results = checks.run()
    for level, name, detail in results:
        print(f"  {level.upper():5} {name}: {detail}")
    return not any(level == "error" for level, _, _ in results)


def suite_tools(_opts) -> bool:
    return _unittest("TESTING/unit/tools")


def suite_import(_opts) -> bool:
    for project in godot.all_projects():
        print(f"  import {project.relative_to(paths.REPO)}")
        godot.import_project(project)
    buildinfo.write_sandbox_manifest()
    code, _ = godot.run_gd_tests(paths.SANDBOX_PROJECT, "smoke", ["res://"], paths.RUNTIME / "test-results" / "smoke.json")
    return code == 0


def suite_unit(_opts) -> bool:
    godot.import_project(paths.SANDBOX_PROJECT)
    code, _ = godot.run_gd_tests(paths.SANDBOX_PROJECT, "test", ["res://tests/unit"], paths.RUNTIME / "test-results" / "unit.json")
    return code == 0


def suite_rooms(_opts) -> bool:
    ok = True
    for name in rooms.list_rooms():
        print(f"  room {name}")
        ok = rooms.test_room(name)[0] == 0 and ok
    scratch = paths.RUNTIME / "scratch-rooms"
    shutil.rmtree(scratch, ignore_errors=True)
    scratch.mkdir(parents=True)
    rooms.new_room("template_check", scratch)
    print("  room template_check (scaffolded from _TEMPLATE)")
    ok = rooms.test_room("template_check", scratch)[0] == 0 and ok
    bench = rooms.bench_room("template_check", scratch, echo=False)
    if not bench["ok"]:
        print("  template benchmark problems:", bench["problems"])
    return ok and bench["ok"]


def suite_pipeline(opts) -> bool:
    problems = assets.check()
    for p in problems:
        print("  ERROR", p)
    if not problems and getattr(opts, "with_blender", False):
        for asset_id in assets.asset_ids():
            build = assets.generate(asset_id)
            _, meta, _ = assets.load(asset_id)
            same = assets._sha(build["glb"]) == meta["runtime"]["sha256"]
            print(f"  {asset_id}: regenerated with Blender, {'identical to' if same else 'DIFFERS from'} the committed runtime file")
            problems += [] if same else [asset_id]
    return not problems


def suite_multiplayer(_opts) -> bool:
    return _unittest("TESTING/multiplayer")


def suite_docker(_opts) -> bool:
    if subprocess.run(["docker", "info"], capture_output=True).returncode != 0:
        print("  Docker daemon not reachable - suite NOT run")
        return False
    return _unittest("TESTING/integration", "test_docker*.py")


SUITES = {name: globals()[f"suite_{name}"] for name in ORDER}


def run(names: list[str], skip: list[str], opts) -> int:
    selected = [n for n in (names or ORDER) if n not in skip]
    unknown = [n for n in selected if n not in SUITES]
    if unknown:
        print(f"unknown suite(s): {unknown}; available: {ORDER}")
        return 2
    results = []
    for name in selected:
        print(f"\n=== {name}: {DESCRIPTIONS[name]}", flush=True)
        started = time.monotonic()
        try:
            ok = SUITES[name](opts)
        except Exception as exc:  # report and continue with the remaining suites
            print(f"  suite crashed: {exc!r}")
            ok = False
        results.append({"suite": name, "ok": ok, "seconds": round(time.monotonic() - started, 1)})
    print("\n=== summary")
    for r in results:
        print(f"  {'PASS' if r['ok'] else 'FAIL'}  {r['suite']:<12} {r['seconds']:>7.1f}s")
    for name in skip:
        print(f"  SKIP  {name}")
    out = paths.RUNTIME / "test-results" / f"summary-{buildinfo.utc_stamp()}.json"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps({"git": buildinfo.git_info(), "results": results, "skipped": skip}, indent=2), encoding="utf-8")
    print(f"  (recorded in {out.relative_to(paths.REPO)})")
    return 0 if all(r["ok"] for r in results) else 1
