#!/usr/bin/env python3
"""STRUCTURE developer CLI. Run `python TOOLS/cli/structure.py --help`.

Stdlib only (Python >= 3.11). Every command is documented in
AGENT-WORKSHOP/DOCUMENTATION/COMMANDS.md.
"""
from __future__ import annotations

import sys
from pathlib import Path

if sys.version_info < (3, 11):
    sys.exit("STRUCTURE tooling requires Python >= 3.11")

sys.path.insert(0, str(Path(__file__).resolve().parent))

from structure_cli.main import main  # noqa: E402

if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
