"""Docker image builds. Every server image carries its build manifest (label + res://build_manifest.json)
and a unique tag (<version>-<sha7>[-dirty.<UTC stamp>]); existing tags are never overwritten."""
from __future__ import annotations

import json
import subprocess

from . import buildinfo, paths, toolchain

DOCKERFILE = paths.DOCKER / "server.Dockerfile"
LABEL_MANIFEST = "org.structure.manifest"
TOOLS_IMAGE = "structure-tools:local"
TEST_TAG = "test"  # the only mutable tag: rebuilt by the docker test suite, never used by environments


class BuildError(RuntimeError):
    pass


def repository() -> str:
    return toolchain.load()["docker"]["server_image_repository"]


def image_exists(image: str) -> bool:
    return subprocess.run(["docker", "image", "inspect", image], capture_output=True, timeout=60).returncode == 0


def _build_args() -> list[str]:
    tc = toolchain.load()
    linux = tc["godot"]["platforms"]["linux-x86_64"]
    return ["--build-arg", f"BASE_IMAGE={tc['docker']['base_image']}",
            "--build-arg", f"GODOT_VERSION={tc['godot']['version']}",
            "--build-arg", f"GODOT_ARCHIVE={linux['archive']}",
            "--build-arg", f"GODOT_SHA256={linux['sha256']}"]


def build_server(tag: str | None = None, overwrite: bool = False) -> str:
    """overwrite=True is reserved for the test suite's throwaway `test` tag."""
    m = buildinfo.manifest()
    tag = tag or buildinfo.image_tag(m)
    image = f"{repository()}:{tag}"
    if image_exists(image) and not overwrite:
        print(f"{image} already exists; tags are immutable (commit or change files to get a new tag).")
        return image
    m["image"] = image
    buildinfo.write_sandbox_manifest(m)
    cmd = ["docker", "build", "-f", str(DOCKERFILE), "--target", "runtime", "-t", image, *_build_args(),
           "--label", f"{LABEL_MANIFEST}={json.dumps(m, separators=(',', ':'))}",
           "--label", f"org.structure.build_version={m['build_version']}",
           "--label", f"org.structure.protocol_version={m['protocol_version']}",
           "--label", f"org.structure.world_schema_version={m['world_schema_version']}",
           "--label", f"org.opencontainers.image.revision={m['git_commit']}",
           "--label", f"org.opencontainers.image.version={m['build_version']}",
           str(paths.REPO)]
    print(f"Building {image} ...", flush=True)
    if subprocess.run(cmd, timeout=1800).returncode != 0:
        raise BuildError(f"docker build failed for {image}")
    if tag != TEST_TAG:
        paths.BUILD_REGISTRY.mkdir(parents=True, exist_ok=True)
        (paths.BUILD_REGISTRY / f"{tag}.json").write_text(json.dumps(m, indent=2) + "\n", encoding="utf-8")
    return image


def build_tools() -> str:
    cmd = ["docker", "build", "-f", str(DOCKERFILE), "--target", "tools", "-t", TOOLS_IMAGE, *_build_args(), str(paths.REPO)]
    if subprocess.run(cmd, timeout=1800).returncode != 0:
        raise BuildError("docker build failed for the tools image")
    return TOOLS_IMAGE


def image_manifest(image: str) -> dict | None:
    proc = subprocess.run(["docker", "image", "inspect", image, "--format", f'{{{{index .Config.Labels "{LABEL_MANIFEST}"}}}}'],
                          capture_output=True, text=True, timeout=60)
    if proc.returncode != 0 or not proc.stdout.strip():
        return None
    return json.loads(proc.stdout.strip())


def list_builds() -> list[dict]:
    """Local server images, newest first, with their manifests."""
    proc = subprocess.run(["docker", "images", repository(), "--format", "{{.Repository}}:{{.Tag}}|{{.CreatedAt}}|{{.Size}}"],
                          capture_output=True, text=True, timeout=60)
    rows = []
    for line in proc.stdout.splitlines():
        image, created, size = line.split("|")
        if image.endswith(f":{TEST_TAG}") or image.endswith(":<none>"):
            continue
        rows.append({"image": image, "created": created, "size": size, "manifest": image_manifest(image) or {}})
    rows.sort(key=lambda r: r["created"], reverse=True)
    return rows


def resolve_image(tag: str | None) -> str:
    """Explicit tag -> that image (must exist); otherwise the newest local build."""
    if tag:
        image = tag if ":" in tag else f"{repository()}:{tag}"
        if not image_exists(image):
            raise BuildError(f"image {image} not found; run `structure.py builds` to list local builds")
        return image
    builds = list_builds()
    if not builds:
        raise BuildError("no server image built yet; run `python TOOLS/cli/structure.py build`")
    return builds[0]["image"]
