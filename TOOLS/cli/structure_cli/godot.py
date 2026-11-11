"""Running Godot headless: project import, GDScript test runner, role processes."""
from __future__ import annotations

import json
import subprocess
from pathlib import Path

from . import paths, toolchain

BANNER_PREFIXES = ("Godot Engine v",)


def utility_projects() -> list[Path]:
    """Standalone utilities: utility/<area>/<tool>/project.godot (ADR-0009)."""
    return sorted(p.parent for p in paths.UTILITY.glob("*/*/project.godot"))


def lab_projects() -> list[Path]:
    """Laboratories: LABS/<name>/project.godot (ADR-0010); LABS/_TEMPLATE is the scaffold, not a lab."""
    return sorted(p.parent for p in paths.LABS.glob("*/project.godot") if not p.parent.name.startswith("_"))


def all_projects() -> list[Path]:
    rooms = sorted(p.parent for p in paths.SYSTEM_ROOMS.glob("*/project.godot") if not p.parent.name.startswith("_"))
    return [paths.SANDBOX_PROJECT, *rooms, *utility_projects(), *lab_projects()]


def base_cmd(project: Path) -> list[str]:
    return [str(toolchain.ensure_godot()), "--headless", "--path", str(project)]


def import_project(project: Path) -> None:
    """Builds .godot/ caches (global class list, imported assets). Raises on engine errors."""
    proc = subprocess.run([*base_cmd(project), "--import"], capture_output=True, text=True, timeout=600)
    errors = [ln for ln in (proc.stdout + proc.stderr).splitlines() if ln.startswith(("ERROR:", "SCRIPT ERROR:"))]
    if proc.returncode != 0 or errors:
        print(proc.stdout[-4000:], proc.stderr[-4000:], sep="\n")
        raise RuntimeError(f"Godot import failed for {project} (exit {proc.returncode}, {len(errors)} error lines)")


def run_gd_tests(project: Path, mode: str = "test", dirs: list[str] | None = None,
                 report: Path | None = None, test_filter: str | None = None, echo: bool = True) -> tuple[int, dict | None]:
    cmd = [*base_cmd(project), "--script", str(paths.GD_TEST_RUNNER), "--", f"--mode={mode}"]
    cmd += [f"--dir={d}" for d in (dirs or ["res://tests"])]
    if report:
        report.parent.mkdir(parents=True, exist_ok=True)
        report.unlink(missing_ok=True)
        cmd.append(f"--report={report}")
    if test_filter:
        cmd.append(f"--filter={test_filter}")
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=1800)
    if echo:
        for line in (proc.stdout + proc.stderr).splitlines():
            if line.strip() and not line.startswith(BANNER_PREFIXES):
                print("  " + line)
    data = json.loads(report.read_text(encoding="utf-8")) if report and report.is_file() else None
    return proc.returncode, data
