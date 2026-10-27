# TOOLS

| Folder | Contents |
|---|---|
| `cli/structure.py` | the developer CLI (stdlib only); modules in `cli/structure_cli/` - commands in `AGENT-WORKSHOP/DOCUMENTATION/COMMANDS.md` |
| `diagnostics/log_summary.py` | summarise a JSON-lines server/client log (events, errors, metrics) |
| `visualization/world_map.py` | render a `world.json` or snapshot as a top-down SVG |

`structure_cli` modules: `paths` (locations), `toolchain` (pins, downloads), `godot` (import/test runner), `procs`
(server/bot processes), `envs` (environments + compose), `builds` (images), `buildinfo` (manifest, tags), `snapshots`,
`compat`, `rooms` (incl. integration gateway), `assets` (pipeline), `checks`, `testing`, `bench`, `doctor`, `main`.
