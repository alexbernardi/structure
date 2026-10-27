"""Shared helpers for tooling tests: import path and temporary directories under .runtime/."""
from __future__ import annotations

import shutil
import sys
import uuid
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO / "TOOLS" / "cli"))

from structure_cli import paths  # noqa: E402


def temp_dir(prefix: str) -> Path:
    path = paths.RUNTIME / "tool-tests" / f"{prefix}-{uuid.uuid4().hex[:8]}"
    path.mkdir(parents=True)
    return path


def cleanup(path: Path) -> None:
    shutil.rmtree(path, ignore_errors=True)
