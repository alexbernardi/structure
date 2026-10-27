# Conventions

## Code (GDScript, Godot 4.7)

- **No `class_name` in runtime or system code**; depend explicitly with `const X = preload("res://...")` (or relative
  paths inside a system). Fresh clones then work without the editor's global class cache.
- **Separate rules from presentation**: pure `RefCounted` logic (`world/world_state.gd`, `systems/*`) is unit-tested
  headless; nodes only present or transport.
- **Server authority**: every state change is `request_*()` -> validation -> events -> `apply_event()` on the server,
  broadcast to clients, which only `apply_event()`. Never mutate replicated state from client input.
- **All RPCs live in `net/session.gd`** so RPC configuration is identical on every peer. Client-to-server RPCs take
  `Variant` arguments and validate them (`net/protocol.gd`).
- Static typing where it helps; tabs; `snake_case` files and functions; `PascalCase` preload constants.
- Logging: `Log.event("area.what", {...}, level)` - JSON lines; add new events to `DOCUMENTATION/LOG-EVENTS.md`.
- Configuration: `core/app_config.gd` (defaults < `STRUCTURE_*` env vars < `-- --key=value` args); validate everything.

## Python tooling

Stdlib only, Python >= 3.11, one command surface (`TOOLS/cli/structure.py`), modules under `TOOLS/cli/structure_cli/`.
Tests use `unittest`. Errors that users can fix raise a module-specific `*Error` with an actionable message.

## Tests

GDScript: `test_*.gd` files with `func test_*(t)` methods (runner API in `DOCUMENTATION/TESTING.md`).
Python: `TESTING/**/test_*.py`. Tests fail on unexpected engine errors. Use fixed seeds; never depend on wall-clock order.

## Units, axes and assets

Metres, kilograms, seconds, radians in code (degrees only in UI/specs where stated). Godot/glTF axes: +Y up, -Z forward.
Asset ids are `lower_snake_case`; pivots at the base centre unless the spec says otherwise. Details: `COMMON-ASSETS/README.md`.

## Git

Branches `task/NNNN-slug`; commit messages `area: what changed` (e.g. `sandbox: validate deposit range`);
large binary sources go through Git LFS (`.gitattributes`); generated caches (`.godot/`, `.runtime/`, `.tools/`) are ignored.
