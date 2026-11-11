"""Package rooms (ADR-0010): a system whose source lives in a workbench laboratory and is installed, pinned and
hash-checked into every consumer project at res://<mount>/ (for movement_core: res://systems/movement_core/).

A room is a package room when its room.json has a "package" section:
  {"source": "<repo path of the package folder>", "mount": "systems/<name>", "workbench": "<repo path of its lab>",
   "tests": ["res://tests"], "benchmarks": ["res://benchmarks/<file>.gd"]}
Releases are git tags "<room>/v<version>"; `install --version X` reads the package from that tag, so a consumer can be
pinned to (or rolled back to) any released version without touching the source.
"""
from __future__ import annotations

import hashlib
import json
import shutil
import subprocess
from pathlib import Path

from . import buildinfo, godot, paths

RECORD = "INTEGRATION.json"
TEXT_SUFFIXES = {".gd", ".tscn", ".tres", ".json", ".md", ".txt", ".import", ".uid", ".cfg", ".gdshader"}


class PackageError(RuntimeError):
    pass


def _room(name: str) -> dict:
    path = paths.SYSTEM_ROOMS / name / "room.json"
    if not path.is_file():
        raise PackageError(f"no room '{name}'")
    return json.loads(path.read_text(encoding="utf-8"))


def is_package(name: str) -> bool:
    return "package" in _room(name)


def package_rooms() -> list[str]:
    return sorted(p.parent.name for p in paths.SYSTEM_ROOMS.glob("*/room.json")
                  if not p.parent.name.startswith("_") and "package" in json.loads(p.read_text(encoding="utf-8")))


def source_dir(name: str) -> Path:
    return paths.REPO / _room(name)["package"]["source"]


def mount(name: str) -> str:
    return _room(name)["package"]["mount"]


def workbench(name: str) -> Path:
    return paths.REPO / _room(name)["package"]["workbench"]


def tag(name: str, version: str) -> str:
    return f"{name}/v{version}"


# ---------------------------------------------------------------------------------------------- hashing

def _normalise(rel: str, data: bytes) -> bytes:
    return data.replace(b"\r\n", b"\n") if Path(rel).suffix in TEXT_SUFFIXES else data


def files_on_disk(folder: Path) -> dict[str, bytes]:
    """Every file of an installed or source package except the install record and Godot's cache."""
    out = {}
    if folder.is_dir():
        for f in sorted(folder.rglob("*")):
            rel = f.relative_to(folder).as_posix()
            if f.is_file() and rel != RECORD and ".godot" not in f.relative_to(folder).parts:
                out[rel] = f.read_bytes()
    return out


def files_hash(files: dict[str, bytes]) -> str:
    digest = hashlib.sha256()
    for rel in sorted(files):
        digest.update(rel.encode() + b"\n")
        digest.update(_normalise(rel, files[rel]))
    return digest.hexdigest()


def _git(*args: str, cwd: Path = paths.REPO) -> subprocess.CompletedProcess:
    return subprocess.run(["git", *args], cwd=cwd, capture_output=True)


def files_at(name: str, version: str | None) -> tuple[str, dict[str, bytes], str | None]:
    """-> (version, files, tag) of the package: the working tree (version None) or a released tag."""
    if version is None:
        return _room(name)["version"], files_on_disk(source_dir(name)), None
    ref = tag(name, version)
    if _git("rev-parse", "-q", "--verify", f"refs/tags/{ref}").returncode != 0:
        raise PackageError(f"no release tag {ref} (released: {', '.join(released(name)) or 'none'})")
    room = json.loads(_git("show", f"{ref}:SYSTEM-ROOMS/{name}/room.json").stdout)
    source = room["package"]["source"].rstrip("/")
    listing = _git("ls-tree", "-r", "--name-only", ref, "--", source).stdout.decode().splitlines()
    files = {}
    for path in listing:
        rel = path[len(source) + 1:]
        if rel and rel != RECORD:
            files[rel] = _git("show", f"{ref}:{path}").stdout
    return room["version"], files, ref


def released(name: str) -> list[str]:
    out = _git("tag", "--list", f"{name}/v*").stdout.decode().split()
    return sorted((t.split("/v", 1)[1] for t in out), key=_parse)


# ---------------------------------------------------------------------------------------------- versions

def _parse(version: str) -> tuple[int, int, int]:
    parts = [int(p) for p in version.split(".")]
    return (parts + [0, 0, 0])[:3]


def compatibility(installed: str, current: str) -> str:
    """current | behind_compatible (same major, older) | behind_breaking (older major) | ahead."""
    a, b = _parse(installed), _parse(current)
    if a == b:
        return "current"
    if a > b:
        return "ahead"
    return "behind_compatible" if a[0] == b[0] else "behind_breaking"


# ---------------------------------------------------------------------------------------------- consumers

def candidate_projects() -> list[Path]:
    return godot.all_projects()


def consumer_record(name: str, project: Path) -> dict | None:
    path = project / mount(name) / RECORD
    return json.loads(path.read_text(encoding="utf-8")) if path.is_file() else None


def status(name: str) -> dict:
    room = _room(name)
    source = files_on_disk(source_dir(name))
    source_hash = files_hash(source)
    consumers = []
    for project in candidate_projects():
        record = consumer_record(name, project)
        if record is None:
            continue
        copy_hash = files_hash(files_on_disk(project / mount(name)))
        consumers.append({
            "project": project.relative_to(paths.REPO).as_posix(), "version": record["version"],
            "tag": record.get("tag"), "drift": copy_hash != record["sha256"],
            "compatibility": compatibility(record["version"], room["version"]),
            "matches_source": copy_hash == source_hash,
        })
    declared = set(room.get("consumers", []))
    missing = sorted(declared - {c["project"] for c in consumers})
    return {"room": name, "version": room["version"], "released": released(name), "source": room["package"]["source"],
            "source_sha256": source_hash, "files": len(source), "consumers": consumers, "missing_consumers": missing}


def install(name: str, project: Path, version: str | None = None, force: bool = False) -> dict:
    """Installs (or re-pins) the package into `project` at its mount. Refuses to overwrite local edits unless forced."""
    project = project.resolve()
    if not (project / "project.godot").is_file():
        raise PackageError(f"{project} is not a Godot project")
    if project == workbench(name).resolve():
        raise PackageError(f"{project.relative_to(paths.REPO)} is the workbench of {name}: it holds the source itself")
    target = project / mount(name)
    previous = consumer_record(name, project)
    if previous is not None and not force:
        if files_hash(files_on_disk(target)) != previous["sha256"]:
            raise PackageError(f"{target.relative_to(paths.REPO)} was edited by hand (hash drift); move the edits into the "
                               f"workbench, or pass --force to discard them")
    resolved, files, ref = files_at(name, version)
    if target.exists():
        shutil.rmtree(target)
    for rel, data in files.items():
        dest = target / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(data)
    record = {
        "room": name, "version": resolved, "tag": ref, "source": _room(name)["package"]["source"],
        "sha256": files_hash(files), "files": len(files), "installed_at": buildinfo.utc_now(),
        "git_commit": buildinfo.git_info()["commit"], "previous_version": previous["version"] if previous else None,
        "note": "Generated by `structure.py room install`. Do not edit this folder: change the workbench, release, and "
                "re-install.",
    }
    (target / RECORD).write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")
    return record


def problems() -> list[tuple[str, str]]:
    """For `structure.py check`: [(level, detail)] over every package room's consumers."""
    out = []
    for name in package_rooms():
        st = status(name)
        if not source_dir(name).is_dir():
            out.append(("error", f"{name}: package source {st['source']} missing"))
        for c in st["consumers"]:
            if c["drift"]:
                out.append(("error", f"{name}: copy in {c['project']} was edited by hand (hash drift); re-install"))
            elif c["compatibility"] == "behind_breaking":
                out.append(("warn", f"{name}: {c['project']} pins {c['version']}, current {st['version']} is a breaking "
                                    f"(major) update - migrate deliberately"))
            elif c["compatibility"] == "behind_compatible":
                out.append(("warn", f"{name}: {c['project']} pins {c['version']}; {st['version']} is compatible "
                                    f"(`room install {name} {c['project']}`)"))
            elif c["compatibility"] == "current" and not c["matches_source"]:
                out.append(("warn", f"{name}: the workbench source changed since {c['project']} installed "
                                    f"{c['version']} (release a new version or re-install)"))
        for project in st["missing_consumers"]:
            out.append(("warn", f"{name}: declared consumer {project} has no installed copy"))
    return out


def run_workbench(name: str, mode: str, echo: bool = True) -> tuple[int, dict | None]:
    bench = workbench(name)
    godot.import_project(bench)
    spec = _room(name)["package"]
    dirs = spec.get("tests", ["res://tests"]) if mode == "test" else spec.get("benchmarks", ["res://benchmarks"])
    report = paths.RUNTIME / "test-results" / f"room-{name}-{mode}.json"
    if mode == "bench" and all(d.endswith(".gd") for d in dirs):
        # the runner takes directories; a single benchmark file is selected with a filter on its name
        folder = dirs[0].rsplit("/", 1)[0]
        return godot.run_gd_tests(bench, mode, [folder], report, test_filter=Path(dirs[0]).stem, echo=echo)
    return godot.run_gd_tests(bench, mode, dirs, report, echo=echo)
