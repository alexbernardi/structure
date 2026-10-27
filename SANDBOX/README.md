# SANDBOX - the playable game

| Folder | Contents |
|---|---|
| `godot/` | The Godot 4.7 project (one project, three roles: `server`, `client`, `bot`) - see layout below |
| `config/` | Where runtime configuration lives today (routing note) |
| `scenarios/` | `scenario-a.json` (one server, two clients), `scenario-b.json` (two isolated servers) used by `structure.py scenario` |

## `godot/` layout

| Path | Purpose |
|---|---|
| `main.tscn`, `main.gd` | boot: config -> `Session` + role app |
| `core/` | config (`app_config.gd`), structured log, build info, metrics, input map |
| `net/` | `session.gd` (all RPCs, auth), `protocol.gd` (validation) |
| `world/` | `world_state.gd` (rules), `world_gen.gd` (seeded layout), `world_store.gd` (persistence) |
| `server/` | `server_app.gd` - authoritative tick, saves, heartbeat lease, metrics |
| `client/` | windowed presentation: world view, FP controller, avatars, HUD, connect menu |
| `bots/` | headless scripted client for tests/benchmarks |
| `systems/` | **read-only** promoted copies of system rooms (`INTEGRATION.json` records the source hash) |
| `assets/common/` | **read-only** deployed copies of `COMMON-ASSETS` (+ `.asset.json` sidecars) |
| `tests/unit/` | GDScript unit tests (run with `structure.py test unit`) |
| `build_manifest.json` | generated build identity (git-ignored; baked into images) |

Run it: `python TOOLS/cli/structure.py play`. Architecture: `AGENT-WORKSHOP/DOCUMENTATION/ARCHITECTURE.md`.
