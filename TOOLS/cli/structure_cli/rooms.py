"""System rooms (SYSTEM-ROOMS/<name>) and the integration gateway.

A room is a tiny standalone Godot project (project.godot + src/ tests/ benchmarks/ ...) described by
room.json. `promote` copies a validated room's src/ into SANDBOX/godot/systems/<name>/ and records the
source hash in INTEGRATION.json; sandbox copies must never be edited directly (drift is detected).

Package rooms (room.json "package", ADR-0010) keep their source in a workbench laboratory instead of src/; their
tests and benchmarks run there and promotion installs a pinned copy into every declared consumer (packages.py).
"""
from __future__ import annotations

import hashlib
import json
import re
import shutil
from pathlib import Path

from . import buildinfo, godot, packages, paths

TEMPLATE = paths.SYSTEM_ROOMS / "_TEMPLATE"
NAME_RE = re.compile(r"^[a-z][a-z0-9_]{1,31}$")
SOURCE_SUFFIXES = {".gd", ".tscn", ".tres", ".json", ".gdshader", ".cfg"}
REQUIRED_SECTIONS = {
    "SPEC.md": ["Responsibilities and scope", "Behaviour"],
    "CONTRACT.md": ["Inputs and outputs", "Data ownership", "Public interface", "Dependencies",
                    "Events emitted and consumed", "Multiplayer authority", "Performance targets",
                    "Automated tests", "Integration requirements"],
}


class RoomError(RuntimeError):
    pass


def room_dir(name: str, root: Path = paths.SYSTEM_ROOMS) -> Path:
    return root / name


def load_room(name: str, root: Path = paths.SYSTEM_ROOMS) -> dict:
    path = room_dir(name, root) / "room.json"
    if not path.is_file():
        raise RoomError(f"no room '{name}' ({path} missing)")
    return json.loads(path.read_text(encoding="utf-8"))


def list_rooms() -> list[str]:
    return sorted(p.parent.name for p in paths.SYSTEM_ROOMS.glob("*/room.json") if not p.parent.name.startswith("_"))


def source_files(src: Path) -> list[Path]:
    return sorted(p for p in src.rglob("*") if p.is_file() and p.suffix in SOURCE_SUFFIXES and p.name != "INTEGRATION.json")


def tree_hash(src: Path) -> str:
    """Content hash of promotable files (line endings normalised; Godot .uid/.import files excluded)."""
    digest = hashlib.sha256()
    for f in source_files(src):
        digest.update(f.relative_to(src).as_posix().encode() + b"\n")
        digest.update(f.read_bytes().replace(b"\r\n", b"\n"))
    return digest.hexdigest()


def target_dir(name: str) -> Path:
    return paths.REPO / load_room(name)["integration"]["target"]


# ---------------------------------------------------------------------------------------------- scaffolding

def new_room(name: str, root: Path = paths.SYSTEM_ROOMS) -> Path:
    if not NAME_RE.match(name):
        raise RoomError(f"room name must match {NAME_RE.pattern}")
    dest = room_dir(name, root)
    if dest.exists():
        raise RoomError(f"{dest} already exists")
    shutil.copytree(TEMPLATE, dest, ignore=shutil.ignore_patterns(".godot", "*.uid"))
    for f in dest.rglob("*"):
        if f.is_file() and f.suffix in {".md", ".json", ".godot", ".gd"}:
            text = f.read_text(encoding="utf-8")
            if "{{ROOM_NAME}}" in text:
                f.write_text(text.replace("{{ROOM_NAME}}", name), encoding="utf-8")
    return dest


# ---------------------------------------------------------------------------------------------- tests

def test_room(name: str, root: Path = paths.SYSTEM_ROOMS, echo: bool = True, experiments: bool = False) -> tuple[int, dict | None]:
    if root == paths.SYSTEM_ROOMS and packages.is_package(name):
        return packages.run_workbench(name, "test", echo=echo)
    project = room_dir(name, root)
    godot.import_project(project)
    report = paths.RUNTIME / "test-results" / f"room-{name}-tests.json"
    dirs = ["res://tests"] + (["res://experiments"] if experiments else [])
    return godot.run_gd_tests(project, "test", dirs, report, echo=echo)


def bench_room(name: str, root: Path = paths.SYSTEM_ROOMS, echo: bool = True) -> dict:
    """Runs benchmarks and compares them with room.json targets (measured, never theoretical)."""
    if root == paths.SYSTEM_ROOMS and packages.is_package(name):
        code, data = packages.run_workbench(name, "bench", echo=echo)
    else:
        project = room_dir(name, root)
        godot.import_project(project)
        report = paths.RUNTIME / "test-results" / f"room-{name}-bench.json"
        code, data = godot.run_gd_tests(project, "bench", ["res://benchmarks"], report, echo=echo)
    targets = load_room(name, root).get("benchmarks", {})
    results = {b["name"]: b for b in (data or {}).get("benchmarks", [])}
    problems = [] if code == 0 else ["benchmark run failed"]
    for bench_name, target in targets.items():
        measured = results.get(bench_name)
        if measured is None:
            problems.append(f"{bench_name}: declared target but no measurement")
        elif measured["us_per_op"] > target["max_us_per_op"]:
            problems.append(f"{bench_name}: {measured['us_per_op']:.3f} us/op exceeds target {target['max_us_per_op']} us/op")
    return {"ok": not problems, "problems": problems, "results": list(results.values()), "targets": targets}


# ---------------------------------------------------------------------------------------------- integration

def contract_problems(name: str, root: Path = paths.SYSTEM_ROOMS) -> list[str]:
    problems = []
    folder = room_dir(name, root)
    room = load_room(name, root)
    for key in ("name", "version", "status", "public_interface", "dependencies", "integration", "benchmarks"):
        if key not in room:
            problems.append(f"room.json: missing '{key}'")
    base = packages.source_dir(name) if root == paths.SYSTEM_ROOMS and "package" in room else folder
    for rel in room.get("public_interface", []):
        if not (base / rel).is_file():
            problems.append(f"room.json: public interface file {rel} does not exist")
    for doc, sections in REQUIRED_SECTIONS.items():
        path = folder / doc
        if not path.is_file():
            problems.append(f"{doc} missing")
            continue
        text = path.read_text(encoding="utf-8")
        for section in sections:
            match = re.search(rf"^##\s+{re.escape(section)}\s*$(.*?)(?=^##\s|\Z)", text, re.M | re.S)
            if not match:
                problems.append(f"{doc}: section '{section}' missing")
            elif not match.group(1).strip() or "{{" in match.group(1) or "TODO" in match.group(1):
                problems.append(f"{doc}: section '{section}' is empty or still a placeholder")
    return problems


def integration_status(name: str) -> dict:
    if packages.is_package(name):
        st = packages.status(name)
        sandbox = next((c for c in st["consumers"] if c["project"] == "SANDBOX/godot"), None)
        return {
            "room": name, "integrated": sandbox is not None, "room_version": st["version"],
            "integrated_version": sandbox["version"] if sandbox else None,
            "drift": bool(sandbox and sandbox["drift"]),
            "pending": bool(sandbox and not sandbox["matches_source"]),
            "room_sha256": st["source_sha256"], "sandbox_sha256": None, "consumers": st["consumers"],
        }
    target = target_dir(name)
    record_path = target / "INTEGRATION.json"
    record = json.loads(record_path.read_text(encoding="utf-8")) if record_path.is_file() else None
    room_hash = tree_hash(room_dir(name) / "src")
    sandbox_hash = tree_hash(target) if target.is_dir() else None
    return {
        "room": name,
        "integrated": record is not None,
        "room_version": load_room(name)["version"],
        "integrated_version": record.get("room_version") if record else None,
        "drift": bool(record) and sandbox_hash != record["source_sha256"],  # sandbox copy edited directly
        "pending": bool(record) and room_hash != record["source_sha256"],   # room changed since promotion
        "room_sha256": room_hash,
        "sandbox_sha256": sandbox_hash,
    }


def promote(name: str, run_sandbox_suites, dry_run: bool = False) -> dict:
    """Integration gateway. `run_sandbox_suites()` -> bool runs the sandbox gates after copying."""
    checks: list[dict] = []

    def check(label: str, ok: bool, detail: str = "") -> bool:
        checks.append({"check": label, "ok": ok, "detail": detail})
        print(f"  [{'x' if ok else ' '}] {label}{(' - ' + detail) if detail else ''}", flush=True)
        return ok

    room = load_room(name)
    print(f"Integration gateway: {name} {room['version']} ({room['status']})")
    problems = contract_problems(name)
    check("1. interface and contract documented", not problems, "; ".join(problems))
    code, report = test_room(name, echo=False)
    check("2. room tests pass in isolation", code == 0, f"{(report or {}).get('passed', 0)} passed, {(report or {}).get('failed', '?')} failed")
    bench = bench_room(name, echo=False)
    check("6. benchmarks meet measured targets", bench["ok"], "; ".join(bench["problems"]) or
          ", ".join(f"{r['name']}={r['us_per_op']:.3f}us" for r in bench["results"]))
    deps = room.get("dependencies")
    check("7. dependencies declared", isinstance(deps, dict), json.dumps(deps))
    if "package" in room:
        return _promote_package(name, room, run_sandbox_suites, dry_run, checks, check, bench)
    status = integration_status(name)
    check("sandbox copy has not been edited directly", not status["drift"],
          "drift detected: re-promote deliberately or move the edits into the room" if status["drift"] else "")
    if not all(c["ok"] for c in checks) or dry_run:
        return {"ok": False if not all(c["ok"] for c in checks) else None, "checks": checks, "promoted": False}

    target = target_dir(name)
    backup = paths.RUNTIME / "promotions" / f"{name}-{buildinfo.utc_stamp()}"
    if target.exists():
        shutil.copytree(target, backup)
    check("8. rollback path recorded", True, f"previous copy in {backup.relative_to(paths.REPO)} (and git history)")
    src = room_dir(name) / "src"
    target.mkdir(parents=True, exist_ok=True)
    for f in source_files(target):
        f.unlink()
    for f in source_files(src):
        dest = target / f.relative_to(src)
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(f, dest)
    record = {
        "room": name, "room_version": room["version"], "status": room["status"],
        "source": f"SYSTEM-ROOMS/{name}/src", "source_sha256": tree_hash(src), "promoted_at": buildinfo.utc_now(),
        "git_commit": buildinfo.git_info()["commit"], "previous_sha256": status["sandbox_sha256"],
        "benchmarks": {r["name"]: round(r["us_per_op"], 4) for r in bench["results"]},
        "note": "Generated by `structure.py room promote`. Do not edit files in this folder; change the room and re-promote.",
    }
    (target / "INTEGRATION.json").write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")
    gates_ok = run_sandbox_suites()
    check("3-5. sandbox gameplay, multiplayer authority and persistence suites pass", gates_ok)
    if not gates_ok:
        shutil.rmtree(target)
        if backup.exists():
            shutil.copytree(backup, target)
        check("rolled back to the previous integrated copy", True)
        return {"ok": False, "checks": checks, "promoted": False}
    return {"ok": True, "checks": checks, "promoted": True, "record": record}


def _promote_package(name: str, room: dict, run_sandbox_suites, dry_run: bool, checks: list, check, bench: dict) -> dict:
    """Package room: install the workbench version into every declared consumer, then run the sandbox gates."""
    st = packages.status(name)
    drifted = [c["project"] for c in st["consumers"] if c["drift"]]
    check("consumer copies have not been edited directly", not drifted, ", ".join(drifted))
    if not all(c["ok"] for c in checks) or dry_run:
        return {"ok": False if not all(c["ok"] for c in checks) else None, "checks": checks, "promoted": False}
    stamp = buildinfo.utc_stamp()
    backups = {}
    for consumer in room.get("consumers", []):
        target = paths.REPO / consumer / packages.mount(name)
        if target.exists():
            backups[consumer] = paths.RUNTIME / "promotions" / f"{name}-{stamp}" / consumer.replace("/", "_")
            shutil.copytree(target, backups[consumer])
        record = packages.install(name, paths.REPO / consumer)
        check(f"installed {name} {record['version']} into {consumer}", True, record["sha256"][:12])
    check("8. rollback path recorded", True, f"previous copies in .runtime/promotions/{name}-{stamp}/, release tags, git history")
    gates_ok = run_sandbox_suites()
    check("3-5. sandbox gameplay, multiplayer authority and persistence suites pass", gates_ok)
    if not gates_ok:
        for consumer in room.get("consumers", []):
            target = paths.REPO / consumer / packages.mount(name)
            shutil.rmtree(target, ignore_errors=True)
            if consumer in backups:
                shutil.copytree(backups[consumer], target)
        check("rolled back every consumer to its previous copy", True)
        return {"ok": False, "checks": checks, "promoted": False}
    return {"ok": True, "checks": checks, "promoted": True}
