"""Build identity: git state, project versions (from project.godot) and the build manifest."""
from __future__ import annotations

import datetime as dt
import hashlib
import json
import re
import subprocess
from pathlib import Path

from . import paths, toolchain

MANIFEST_SCHEMA = 1


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def utc_stamp() -> str:
    return dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")


def _git(*args: str) -> str | None:
    try:
        out = subprocess.run(["git", *args], cwd=paths.REPO, capture_output=True, text=True, timeout=30)
    except OSError:
        return None
    return out.stdout.strip() if out.returncode == 0 else None


def git_info() -> dict:
    commit = _git("rev-parse", "HEAD")
    status = _git("status", "--porcelain")
    return {
        "commit": commit or "nocommit",
        "short": (commit or "nocommit")[:7] if commit else "nocommit",
        "branch": _git("rev-parse", "--abbrev-ref", "HEAD") if commit else None,
        "dirty": bool(status) if status is not None else True,
    }


def project_versions(project: Path = paths.SANDBOX_PROJECT) -> dict:
    """Reads [application] config/version and the [structure] section of project.godot."""
    text = (project / "project.godot").read_text(encoding="utf-8")
    section, values = "", {}
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith(";"):
            continue
        if line.startswith("[") and line.endswith("]"):
            section = line[1:-1]
            continue
        if "=" in line:
            key, value = line.split("=", 1)
            values[f"{section}/{key.strip()}"] = value.strip().strip('"')

    def as_int(key: str) -> int:
        return int(values.get(key, "0"))

    return {
        "build_version": values.get("application/config/version", "0.0.0"),
        "protocol_version": as_int("structure/network/protocol_version"),
        "world_schema_version": as_int("structure/persistence/world_schema_version"),
        "min_world_schema_version": as_int("structure/persistence/min_world_schema_version"),
        "default_port": as_int("structure/network/default_port"),
    }


def file_sha256(path: Path) -> str | None:
    return hashlib.sha256(path.read_bytes()).hexdigest() if path.is_file() else None


def integrated_systems() -> dict:
    out = {}
    for record in sorted((paths.SANDBOX_PROJECT / "systems").glob("*/INTEGRATION.json")):
        data = json.loads(record.read_text(encoding="utf-8"))
        out[record.parent.name] = {"version": data.get("room_version"), "source_sha256": data.get("source_sha256")}
    return out


def manifest(image: str | None = None) -> dict:
    git = git_info()
    versions = project_versions()
    return {
        "manifest_schema": MANIFEST_SCHEMA,
        "build_version": versions["build_version"],
        "git_commit": git["commit"],
        "git_dirty": git["dirty"],
        "git_branch": git["branch"],
        "godot_version": toolchain.godot_version(),
        "protocol_version": versions["protocol_version"],
        "world_schema_version": versions["world_schema_version"],
        "min_world_schema_version": versions["min_world_schema_version"],
        "image": image,
        "asset_manifest_sha256": file_sha256(paths.ASSET_MANIFEST),
        "integrated_systems": integrated_systems(),
        "created_at": utc_now(),
    }


def image_tag(m: dict) -> str:
    """Unique, immutable tag: <version>-<sha7>, plus -dirty.<UTC stamp> for uncommitted trees."""
    short = m["git_commit"][:7] if m["git_commit"] != "nocommit" else "nocommit"
    tag = f"{m['build_version']}-{short}"
    if m["git_dirty"] or short == "nocommit":
        tag += f"-dirty.{utc_stamp()}"
    if not re.fullmatch(r"[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}", tag):
        raise ValueError(f"invalid image tag {tag!r}")
    return tag


def write_sandbox_manifest(m: dict | None = None) -> Path:
    """res://build_manifest.json, read by the game at runtime (git-ignored; baked into images)."""
    target = paths.SANDBOX_PROJECT / "build_manifest.json"
    target.write_text(json.dumps(m or manifest(), indent=2) + "\n", encoding="utf-8")
    return target
