"""Pinned external tools: locate, download and verify (see INFRASTRUCTURE/builds/toolchain.json)."""
from __future__ import annotations

import hashlib
import json
import os
import platform
import re
import shutil
import subprocess
import sys
import urllib.request
import zipfile
from functools import lru_cache
from pathlib import Path

from . import paths


class ToolchainError(RuntimeError):
    pass


@lru_cache(maxsize=1)
def load() -> dict:
    return json.loads(paths.TOOLCHAIN_FILE.read_text(encoding="utf-8"))


def host_platform() -> str:
    machine = platform.machine().lower()
    arch = "x86_64" if machine in ("amd64", "x86_64") else machine
    if sys.platform.startswith("win"):
        return f"windows-{arch}"
    if sys.platform.startswith("linux"):
        return f"linux-{arch}"
    return f"{sys.platform}-{arch}"


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


# --------------------------------------------------------------------------- Godot

def godot_version() -> str:
    return load()["godot"]["version"]


def _godot_platform_entry() -> dict:
    platforms = load()["godot"]["platforms"]
    key = host_platform()
    if key not in platforms:
        raise ToolchainError(f"No pinned Godot build for host platform '{key}'. Pinned: {sorted(platforms)}")
    return platforms[key]


def godot_install_dir() -> Path:
    return paths.TOOLS_DIR / "godot" / godot_version()


def godot_executable() -> Path:
    """Console-attached Godot binary (logs go to the calling terminal)."""
    override = os.environ.get("STRUCTURE_GODOT")
    if override:
        return Path(override)
    return godot_install_dir() / _godot_platform_entry()["console"]


def godot_available() -> bool:
    return godot_executable().is_file()


def _download(url: str, dest: Path) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    tmp = dest.with_suffix(dest.suffix + ".part")
    request = urllib.request.Request(url, headers={"User-Agent": "structure-setup"})
    with urllib.request.urlopen(request, timeout=60) as response, open(tmp, "wb") as out:
        total = int(response.headers.get("Content-Length") or 0)
        done, next_report = 0, 0.1
        while chunk := response.read(1 << 20):
            out.write(chunk)
            done += len(chunk)
            if total and done / total >= next_report:
                print(f"  ... {int(100 * done / total)}%", flush=True)
                next_report += 0.1
    tmp.replace(dest)


def ensure_godot() -> Path:
    """Download + verify the pinned Godot build if it is not installed yet."""
    exe = godot_executable()
    if exe.is_file():
        return exe
    if os.environ.get("STRUCTURE_GODOT"):
        raise ToolchainError(f"STRUCTURE_GODOT points to a missing file: {exe}")
    entry = _godot_platform_entry()
    archive = paths.TOOLS_DIR / "downloads" / entry["archive"]
    if not archive.is_file() or sha256_file(archive) != entry["sha256"]:
        url = f"{load()['godot']['download_base']}/{entry['archive']}"
        print(f"Downloading {url}", flush=True)
        _download(url, archive)
    actual = sha256_file(archive)
    if actual != entry["sha256"]:
        archive.unlink(missing_ok=True)
        raise ToolchainError(f"SHA-256 mismatch for {archive.name}: expected {entry['sha256']}, got {actual}")
    print(f"Verified SHA-256 {actual[:16]}... for {archive.name}", flush=True)
    target = godot_install_dir()
    target.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(archive) as zf:
        zf.extractall(target)
    for item in target.iterdir():
        if item.is_file() and not sys.platform.startswith("win"):
            item.chmod(0o755)
    # Self-contained mode: keeps editor settings/caches inside .tools instead of the user profile.
    (target / "._sc_").touch()
    if not exe.is_file():
        raise ToolchainError(f"Archive did not contain expected executable {exe.name}")
    return exe


def godot_reported_version() -> str | None:
    if not godot_available():
        return None
    out = subprocess.run([str(godot_executable()), "--version"], capture_output=True, text=True, timeout=60)
    return out.stdout.strip() or None


# --------------------------------------------------------------------------- Blender

def find_blender() -> Path | None:
    cfg = load()["blender"]
    override = os.environ.get(cfg["env_override"])
    if override:
        return Path(override) if Path(override).is_file() else None
    on_path = shutil.which("blender")
    if on_path:
        return Path(on_path)
    for candidate in cfg["search_paths"]:
        if Path(candidate).is_file():
            return Path(candidate)
    return None


def blender_reported_version(exe: Path) -> str | None:
    out = subprocess.run([str(exe), "--version"], capture_output=True, text=True, timeout=120)
    match = re.search(r"Blender (\d+\.\d+\.\d+)", out.stdout)
    return match.group(1) if match else None


# --------------------------------------------------------------------------- Other tools

def tool_version(cmd: list[str]) -> str | None:
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
    except (OSError, subprocess.TimeoutExpired):
        return None
    text = (out.stdout or out.stderr).strip().splitlines()
    return text[0] if text and out.returncode == 0 else None
