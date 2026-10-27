# SANDBOX/config

No sandbox-wide config files are needed yet. Configuration currently lives where it is consumed:

| What | Where |
|---|---|
| Server instance settings (port, world id, seed, limits, log level) | `INFRASTRUCTURE/environments/<env>.env` |
| Runtime options and their defaults (all roles) | `SANDBOX/godot/core/app_config.gd` (`-- --key=value` or `STRUCTURE_*` env vars) |
| Versions (build, protocol, world schema) | `SANDBOX/godot/project.godot` `[application]` / `[structure]` |
| Gameplay rules (ranges, movement tolerance) | constants in `world/world_state.gd`; movement parameters in `systems/movement` |

Add files here only when a tunable must change without a code change and is shared by several environments
(e.g. gameplay tuning presets); load them through `app_config.gd` and document them in this README.
