"""Compatibility rules (AGENT-WORKSHOP/PROTOCOLS/VERSIONING.md).

* Client <-> server: protocol_version must be identical; build versions may differ.
* World <-> server build: min_world_schema_version <= world schema <= world_schema_version.
  Older (but >= min) worlds are migrated by the server, which keeps the original as world.v<N>.json.
* A git checkout alone is not a rollback: an older build may be unable to read newer worlds.
"""
from __future__ import annotations

import json
from pathlib import Path


def protocol_compatible(client: dict, server: dict) -> tuple[bool, str]:
    cp, sp = client["protocol_version"], server["protocol_version"]
    if cp != sp:
        return False, f"incompatible: client protocol v{cp}, server protocol v{sp} (the server rejects the client at login)"
    note = ""
    if client.get("build_version") != server.get("build_version"):
        note = f" (builds differ: client {client.get('build_version')}, server {server.get('build_version')}; allowed)"
    return True, f"compatible: protocol v{cp}{note}"


def world_loadable(world_schema: int, build: dict) -> tuple[bool, str]:
    current, minimum = build["world_schema_version"], build["min_world_schema_version"]
    if world_schema > current:
        return False, f"world schema v{world_schema} is newer than this build supports (v{current}); the server refuses it"
    if world_schema < minimum:
        return False, f"world schema v{world_schema} predates the oldest migratable schema (v{minimum})"
    if world_schema < current:
        return True, f"loadable with migration v{world_schema} -> v{current} (original kept as world.v{world_schema}.json)"
    return True, f"loadable as-is (schema v{current})"


def load_manifest(ref: str) -> dict:
    """'current' = this source tree; a path = manifest JSON; anything else = a server image tag."""
    from . import buildinfo, builds

    if ref in ("current", "source"):
        return buildinfo.manifest()
    path = Path(ref)
    if path.suffix == ".json" and path.is_file():
        return json.loads(path.read_text(encoding="utf-8"))
    image = builds.resolve_image(ref)
    manifest = builds.image_manifest(image)
    if manifest is None:
        raise ValueError(f"{image} carries no STRUCTURE build manifest label")
    return manifest
