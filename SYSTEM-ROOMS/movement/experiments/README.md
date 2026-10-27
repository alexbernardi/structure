# Experiments: movement

Alternative implementations live here until measurements justify promotion, e.g.
`experiments/<variant>/movement_model.gd` with its own `test_*.gd`/`bench_*.gd` next to it.

Rules:
- Experiments never replace `src/` without the integration gateway (`structure.py room promote movement`).
- Optimisations need a benchmark showing the gain on this machine; record it in an experiment report
  (`AGENT-WORKSHOP/BLUEPRINTS/EXPERIMENT-REPORT.md`).
- To run an experiment's tests: `python TOOLS/cli/structure.py room test movement --experiments`
  (adds `res://experiments` to the discovered test folders).

No experiments yet.
