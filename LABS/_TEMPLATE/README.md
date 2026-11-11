# {{LAB_NAME}} laboratory

Created by `python TOOLS/cli/structure.py lab create {{LAB_NAME}} --systems movement_core` from an approved `main`.
Branch `lab/{{LAB_NAME}}`, in its own worktree. Pinned systems and the base commit: `lab.json`.

- Open `LABS/{{LAB_NAME}}` in Godot (`scenes/lab.tscn`): a test ground with the approved movement character.
- Build the laboratory's system here (its own folders, tests in `tests/`). Approved systems under `systems/` are
  read-only copies: change them only in their own workbench and laboratory.
- Process: [LABORATORY-PIPELINE.md](../../AGENT-WORKSHOP/PROTOCOLS/LABORATORY-PIPELINE.md) - `lab validate`,
  `lab sync` (bring in newer `main`), `lab promote {{LAB_NAME}}`.

## Goal

What this laboratory develops, and what "done" looks like (fill in).
