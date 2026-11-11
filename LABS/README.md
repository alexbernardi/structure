# LABS - laboratory projects

One Godot project per laboratory, `LABS/<name>/`, on the laboratory's own branch `lab/<name>` in its own worktree.
`main` holds only this README and the scaffold [`_TEMPLATE`](_TEMPLATE/README.md); a laboratory's folder reaches
`main` when the laboratory is promoted. Process: [LABORATORY-PIPELINE.md](../AGENT-WORKSHOP/PROTOCOLS/LABORATORY-PIPELINE.md),
decision: [ADR-0010](../AGENT-WORKSHOP/DECISIONS/ADR-0010-shared-systems-and-laboratories.md).

```powershell
python TOOLS/cli/structure.py lab create combat --systems movement_core   # worktree ../structure-lab-combat
python TOOLS/cli/structure.py lab list
```

Each laboratory has `lab.json` (base commit, pinned systems, systems it develops), `project.godot` (120 Hz physics),
`scenes/lab.tscn` (a test ground with the approved movement character), `tests/` (run by `structure.py test labs`)
and `systems/<room>/` (installed, read-only copies of approved systems).

The movement laboratory predates this folder: it is `utility/movement/flat-plane`, the workbench of `movement_core`.
