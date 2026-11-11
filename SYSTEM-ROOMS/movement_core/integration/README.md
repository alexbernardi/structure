# movement_core integration history

Consumers record their pin in `<project>/systems/movement_core/INTEGRATION.json` (written by
`structure.py room install`); `structure.py room status movement_core` lists them.

| Date | Version | Consumer | Commit | Note |
|---|---|---|---|---|
| 2026-11-11 | 1.0.0 | `SANDBOX/godot` | promotion merge into `main` | first install; `tests/unit/test_movement_core.gd` builds and drives a character with no laboratory code |
