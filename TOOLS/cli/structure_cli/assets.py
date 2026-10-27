"""Asset pipeline: Specification -> Blender script -> GLB -> validation -> COMMON-ASSETS runtime -> consumers -> Godot.

Library layout: COMMON-ASSETS/models/<id>/{asset.json, source/spec.json, runtime/<id>.glb}.
Consumers (Godot projects) receive a copy plus a <id>.asset.json sidecar used by in-engine tests.
"""
from __future__ import annotations

import hashlib
import importlib.util
import json
import shutil
import subprocess
from pathlib import Path

from . import buildinfo, godot, paths, toolchain


class AssetError(RuntimeError):
    pass


def _validator():
    spec = importlib.util.spec_from_file_location("validate_glb", paths.PIPELINES / "validation" / "validate_glb.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def asset_ids() -> list[str]:
    return sorted(p.parent.name for p in paths.COMMON_ASSETS.glob("*/*/asset.json"))


def asset_dir(asset_id: str) -> Path:
    matches = [p.parent for p in paths.COMMON_ASSETS.glob(f"*/{asset_id}/asset.json")]
    if len(matches) != 1:
        raise AssetError(f"asset '{asset_id}' not found under COMMON-ASSETS (known: {asset_ids()})")
    return matches[0]


def load(asset_id: str) -> tuple[Path, dict, dict]:
    folder = asset_dir(asset_id)
    meta = json.loads((folder / "asset.json").read_text(encoding="utf-8"))
    spec = json.loads((folder / "source" / "spec.json").read_text(encoding="utf-8"))
    return folder, meta, spec


def _sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def generate(asset_id: str, allow_version_mismatch: bool = False) -> dict:
    """Runs Blender headless and validates the output. Returns the build info (nothing promoted yet)."""
    folder, meta, spec = load(asset_id)
    exe = toolchain.find_blender()
    if exe is None:
        raise AssetError("Blender not found: install the pinned version or set STRUCTURE_BLENDER to blender.exe")
    version = toolchain.blender_reported_version(exe)
    pinned = toolchain.load()["blender"]["version"]
    if version != pinned and not allow_version_mismatch:
        raise AssetError(f"Blender {version} at {exe} does not match the pinned {pinned} "
                         "(--allow-version-mismatch to proceed; the version is recorded in asset.json)")
    out_dir = paths.PIPELINE_OUT / asset_id
    shutil.rmtree(out_dir, ignore_errors=True)
    out_dir.mkdir(parents=True)
    glb, report = out_dir / f"{asset_id}.glb", out_dir / "blender-report.json"
    cmd = [str(exe), "--background", "--factory-startup", "--python-exit-code", "1",
           "--python", str(paths.PIPELINES / "blender" / "generate_asset.py"), "--",
           "--spec", str(folder / "source" / "spec.json"), "--out", str(glb), "--report", str(report)]
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=600)
    (out_dir / "blender.log").write_text(proc.stdout + proc.stderr, encoding="utf-8")
    if proc.returncode != 0 or not glb.is_file():
        tail = "\n".join((proc.stdout + proc.stderr).splitlines()[-25:])
        raise AssetError(f"Blender generation failed (exit {proc.returncode}); log: {out_dir / 'blender.log'}\n{tail}")
    errors, info = _validator().validate(glb, spec)
    if errors:
        raise AssetError("validation failed:\n  - " + "\n  - ".join(errors))
    return {"glb": glb, "info": info, "blender": json.loads(report.read_text(encoding="utf-8")), "blender_exe": str(exe)}


def promote_and_deploy(asset_id: str, build: dict) -> dict:
    folder, meta, spec = load(asset_id)
    runtime = folder / meta["runtime"]["path"]
    runtime.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(build["glb"], runtime)
    info = build["info"]
    meta["runtime"].update({"sha256": _sha(runtime), "bytes": runtime.stat().st_size})
    meta["generated_with"] = {"blender": build["blender"]["blender_version"], "gltf_exporter": build["blender"]["gltf_exporter"],
                              "generator": spec["generator"], "script": "PIPELINES/blender/generate_asset.py",
                              "spec_sha256": _sha(folder / "source" / "spec.json"), "generated_at": buildinfo.utc_now()}
    meta["dimensions_m"] = [round(v, 4) for v in info["size"]]
    meta["triangles"] = info["triangles"]
    (folder / "asset.json").write_text(json.dumps(meta, indent=2) + "\n", encoding="utf-8")
    deploy(asset_id)
    update_manifest()
    return meta


def deploy(asset_id: str) -> list[Path]:
    folder, meta, _ = load(asset_id)
    runtime = folder / meta["runtime"]["path"]
    sidecar = {k: meta[k] for k in ("asset_id", "version", "dimensions_m", "pivot")}
    sidecar["sha256"] = meta["runtime"]["sha256"]
    sidecar["source"] = folder.relative_to(paths.REPO).as_posix()
    targets = []
    for consumer in meta["consumers"]:
        dest = paths.REPO / consumer
        dest.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(runtime, dest / runtime.name)
        (dest / f"{asset_id}.asset.json").write_text(json.dumps(sidecar, indent=2) + "\n", encoding="utf-8")
        targets.append(dest / runtime.name)
    return targets


def update_manifest() -> Path:
    entries = {}
    for asset_id in asset_ids():
        folder, meta, _ = load(asset_id)
        entries[asset_id] = {"version": meta["version"], "type": meta["type"], "path": folder.relative_to(paths.REPO).as_posix(),
                             "runtime_sha256": meta["runtime"]["sha256"], "license": meta["license"]}
    paths.ASSET_MANIFEST.parent.mkdir(parents=True, exist_ok=True)
    paths.ASSET_MANIFEST.write_text(json.dumps({"manifest_schema": 1, "assets": entries}, indent=2) + "\n", encoding="utf-8")
    return paths.ASSET_MANIFEST


def run(asset_id: str, allow_version_mismatch: bool = False) -> dict:
    build = generate(asset_id, allow_version_mismatch)
    meta = promote_and_deploy(asset_id, build)
    for project in godot.all_projects():
        if any((paths.REPO / c).resolve().is_relative_to(project.resolve()) for c in meta["consumers"]):
            godot.import_project(project)
    return {"meta": meta, "info": build["info"], "blender": build["blender"]}


def check() -> list[str]:
    """Static consistency checks (no Blender): library, manifest, consumer copies and sidecars."""
    problems = []
    validator = _validator()
    manifest = json.loads(paths.ASSET_MANIFEST.read_text(encoding="utf-8")) if paths.ASSET_MANIFEST.is_file() else {"assets": {}}
    for asset_id in asset_ids():
        folder, meta, spec = load(asset_id)
        for key in ("license", "origin", "editable_source", "units", "pivot", "dimensions_m", "owner"):
            if not meta.get(key):
                problems.append(f"{asset_id}: asset.json missing '{key}'")
        runtime = folder / meta["runtime"]["path"]
        if not runtime.is_file():
            problems.append(f"{asset_id}: runtime file {runtime.name} missing (run `structure.py pipeline run {asset_id}`)")
            continue
        if _sha(runtime) != meta["runtime"]["sha256"]:
            problems.append(f"{asset_id}: runtime sha256 differs from asset.json (edited by hand?)")
        errors, _ = validator.validate(runtime, spec)
        problems += [f"{asset_id}: {e}" for e in errors]
        if manifest["assets"].get(asset_id, {}).get("runtime_sha256") != meta["runtime"]["sha256"]:
            problems.append(f"{asset_id}: COMMON-ASSETS/manifests/assets.json is stale")
        for consumer in meta["consumers"]:
            copy = paths.REPO / consumer / runtime.name
            if not copy.is_file():
                problems.append(f"{asset_id}: not deployed to {consumer}")
            elif _sha(copy) != meta["runtime"]["sha256"]:
                problems.append(f"{asset_id}: copy in {consumer} differs from the library (re-deploy, never edit copies)")
    return problems
