"""`structure.py check`: fast static validation of the repository (no Godot, no Docker needed)."""
from __future__ import annotations

import re

from . import assets, buildinfo, envs, packages, paths, rooms, toolchain

REQUIRED_PATHS = [
    "AGENTS.md", "README.md", ".gitignore", "AGENT-WORKSHOP/START-HERE.md", "AGENT-WORKSHOP/PROTOCOLS",
    "AGENT-WORKSHOP/DECISIONS", "SANDBOX/godot/project.godot", "SYSTEM-ROOMS/_TEMPLATE/room.json",
    "INFRASTRUCTURE/builds/toolchain.json", "INFRASTRUCTURE/docker/server.Dockerfile", "TESTING/harness/run_gd_tests.gd",
]
SECRET_PATTERNS = [
    re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----"),
    re.compile(r"AKIA[0-9A-Z]{16}"),
    re.compile(r"(?i)\b(password|passwd|secret|api[_-]?key|token)\s*[=:]\s*['\"]?[A-Za-z0-9/+_\-]{12,}"),
]
SCAN_SUFFIXES = {".py", ".gd", ".md", ".json", ".env", ".yml", ".yaml", ".cfg", ".godot", ".sh", ".ps1", ".txt", ".tscn"}
SKIP_DIRS = {".git", ".tools", ".runtime", ".godot", "__pycache__"}
LINK_RE = re.compile(r"\]\(([^)\s]+)\)")


def _iter_text_files():
    for path in paths.REPO.rglob("*"):
        if path.is_file() and path.suffix in SCAN_SUFFIXES and not (SKIP_DIRS & set(path.relative_to(paths.REPO).parts)):
            yield path


def run() -> list[tuple[str, str, str]]:
    """-> [(level, check, detail)] where level is 'error' or 'warn'."""
    out: list[tuple[str, str, str]] = []

    def err(check: str, detail: str) -> None:
        out.append(("error", check, detail))

    for rel in REQUIRED_PATHS:
        if not (paths.REPO / rel).exists():
            err("layout", f"missing {rel}")

    tc = toolchain.load()
    dockerfile = (paths.DOCKER / "server.Dockerfile").read_text(encoding="utf-8")
    linux = tc["godot"]["platforms"]["linux-x86_64"]
    for arg, value in (("BASE_IMAGE", tc["docker"]["base_image"]), ("GODOT_VERSION", tc["godot"]["version"]),
                       ("GODOT_ARCHIVE", linux["archive"]), ("GODOT_SHA256", linux["sha256"])):
        if f"ARG {arg}={value}" not in dockerfile:
            err("pins", f"server.Dockerfile ARG {arg} default differs from toolchain.json")
    features = re.search(r'config/features=PackedStringArray\("([0-9.]+)"', (paths.SANDBOX_PROJECT / "project.godot").read_text(encoding="utf-8"))
    if not features or not tc["godot"]["version"].startswith(features.group(1)):
        err("pins", "project.godot config/features does not match the pinned Godot minor version")

    v = buildinfo.project_versions()
    if v["protocol_version"] < 1 or not 1 <= v["min_world_schema_version"] <= v["world_schema_version"]:
        err("versions", f"invalid protocol/schema versions in project.godot: {v}")

    for problem in envs.validate_set(envs.all_envs()):
        err("environments", problem)

    for level, detail in packages.problems():
        out.append((level, "systems", detail))
    for name in rooms.list_rooms():
        if packages.is_package(name):
            continue
        try:
            st = rooms.integration_status(name)
        except (KeyError, FileNotFoundError) as exc:
            err("systems", f"{name}: {exc}")
            continue
        if st["drift"]:
            err("systems", f"{name}: SANDBOX copy was edited directly (hash drift); move edits into the room and promote")
        elif st["pending"]:
            out.append(("warn", "systems", f"{name}: room has changes not yet promoted"))
        elif not st["integrated"]:
            out.append(("warn", "systems", f"{name}: not integrated yet"))

    for problem in assets.check():
        err("assets", problem)

    for path in _iter_text_files():
        text = path.read_text(encoding="utf-8", errors="ignore")
        for pattern in SECRET_PATTERNS:
            if pattern.search(text):
                err("secrets", f"possible credential in {path.relative_to(paths.REPO)} ({pattern.pattern[:30]}...)")
        if path.suffix == ".md":
            for target in LINK_RE.findall(text):
                if target.startswith(("http://", "https://", "mailto:")):
                    continue
                if not (path.parent / target.split("#")[0]).exists():
                    err("docs", f"broken link in {path.relative_to(paths.REPO)}: {target}")
    return out
