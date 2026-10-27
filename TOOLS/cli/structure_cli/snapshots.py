"""World snapshots: INFRASTRUCTURE/snapshots/<env>/<id>/{world.json, snapshot.json} (local data, git-ignored).

Safety rules: snapshots are never deleted by tooling; a restore requires --yes, refuses while a server is
using the environment, verifies integrity and schema compatibility with the target build, refuses a
different world unless explicitly allowed, and always snapshots the current world first ("pre-restore").
"""
from __future__ import annotations

import hashlib
import json
import os
import re
import shutil
from pathlib import Path

from . import buildinfo, compat, envs, paths


class SnapshotError(RuntimeError):
    pass


def _label(text: str) -> str:
    cleaned = re.sub(r"[^a-z0-9-]+", "-", text.lower()).strip("-")
    return cleaned[:40] or "manual"


def create(env: envs.Environment, label: str = "manual") -> dict:
    if not env.world_file.is_file():
        raise SnapshotError(f"{env.name}: no world file at {env.world_file}")
    raw = env.world_file.read_bytes()  # saves are atomic renames, so this is always a complete document
    try:
        doc = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise SnapshotError(f"{env.name}: world file is not valid JSON ({exc}); not snapshotting it") from exc
    snapshot_id = f"{buildinfo.utc_stamp()}-{_label(label)}"
    dest = paths.SNAPSHOTS / env.name / snapshot_id
    suffix = 1
    while dest.exists():
        suffix += 1
        dest = paths.SNAPSHOTS / env.name / f"{snapshot_id}-{suffix}"
    dest.mkdir(parents=True)
    (dest / "world.json").write_bytes(raw)
    sites = doc.get("sites") or [{}]
    meta = {
        "id": dest.name, "env": env.name, "label": _label(label), "created_at": buildinfo.utc_now(),
        "world_id": doc.get("world_id"), "seed": doc.get("seed"), "schema_version": doc.get("schema_version"),
        "revision": doc.get("revision"), "site_progress": sites[0].get("deposited"), "saved_at": doc.get("saved_at"),
        "server_build": doc.get("server_build"), "sha256": hashlib.sha256(raw).hexdigest(), "bytes": len(raw),
        "server_was_running": envs.lease_fresh(env),
    }
    (dest / "snapshot.json").write_text(json.dumps(meta, indent=2) + "\n", encoding="utf-8")
    return meta


def list_snapshots(env_name: str | None = None) -> list[dict]:
    pattern = f"{env_name}/*/snapshot.json" if env_name else "*/*/snapshot.json"
    metas = [json.loads(p.read_text(encoding="utf-8")) for p in paths.SNAPSHOTS.glob(pattern)]
    return sorted(metas, key=lambda m: (m["env"], m["id"]))


def find(env_name: str, snapshot_id: str) -> tuple[Path, dict]:
    candidates = [d for d in (paths.SNAPSHOTS / env_name).glob(f"{snapshot_id}*") if (d / "snapshot.json").is_file()]
    exact = [d for d in candidates if d.name == snapshot_id]
    if exact:
        candidates = exact
    if len(candidates) != 1:
        raise SnapshotError(f"{env_name}: {len(candidates)} snapshots match '{snapshot_id}' (use `snapshot list`)")
    return candidates[0], json.loads((candidates[0] / "snapshot.json").read_text(encoding="utf-8"))


def plan_restore(env: envs.Environment, snapshot_id: str, build: dict, allow_other_world: bool = False) -> dict:
    folder, meta = find(env.name, snapshot_id)
    problems: list[str] = []
    raw = (folder / "world.json").read_bytes()
    if hashlib.sha256(raw).hexdigest() != meta["sha256"]:
        problems.append("snapshot integrity check failed (world.json does not match its recorded sha256)")
    ok, reason = compat.world_loadable(int(meta["schema_version"]), build)
    if not ok:
        problems.append(reason)
    if meta["world_id"] != env.world_id and not allow_other_world:
        problems.append(f"snapshot holds world '{meta['world_id']}' but {env.name} is configured for '{env.world_id}' "
                        "(--allow-other-world to override)")
    if envs.is_running(env):
        problems.append(f"a server is running on {env.name}; stop it first (`structure.py env down {env.name}`)")
    return {"snapshot": meta, "folder": folder, "compatibility": reason, "problems": problems,
            "target_build": {k: build.get(k) for k in ("build_version", "git_commit", "world_schema_version", "image")}}


def restore(env: envs.Environment, snapshot_id: str, build: dict, yes: bool = False, allow_other_world: bool = False) -> dict:
    plan = plan_restore(env, snapshot_id, build, allow_other_world)
    if plan["problems"]:
        raise SnapshotError("restore refused:\n  - " + "\n  - ".join(plan["problems"]))
    if not yes:
        raise SnapshotError(f"restore would replace the current world of {env.name} (a pre-restore snapshot is taken first). "
                            "Re-run with --yes to confirm.")
    backup = None
    if env.world_file.is_file():
        backup = create(env, "pre-restore")
        backup_dir = paths.SNAPSHOTS / env.name / backup["id"]
        for extra in ("world.json.bak", "world.json.tmp"):
            leftover = env.world_file.parent / extra
            if leftover.exists():
                shutil.move(str(leftover), backup_dir / extra)
    env.world_file.parent.mkdir(parents=True, exist_ok=True)
    staging = env.world_file.with_name("world.json.restore")
    shutil.copyfile(plan["folder"] / "world.json", staging)
    os.replace(staging, env.world_file)
    return {"restored": plan["snapshot"]["id"], "backup": backup["id"] if backup else None,
            "compatibility": plan["compatibility"]}
