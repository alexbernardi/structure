# Integration gateway

How a system moves from `SYSTEM-ROOMS/<system>/` into the sandbox. Automated by
`python TOOLS/cli/structure.py room promote <system>` (`--dry-run` runs only the pre-copy checks).

## Checklist (all must pass; the tool prints this list)

| # | Requirement | How it is verified |
|---|---|---|
| 1 | The system has a defined interface | `room.json` `public_interface` files exist; `SPEC.md`/`CONTRACT.md` sections present and not placeholders |
| 2 | Automated tests pass | room tests in isolation (`room test`) |
| 3 | Existing gameplay remains functional | after copying: Godot import + smoke load + sandbox unit tests |
| 4 | Multiplayer authority is respected | `CONTRACT.md` "Multiplayer authority" section + multiplayer suite (incl. cheat suite) |
| 5 | Persistence/serialisation stay compatible | world-store unit tests + persistence tests in the multiplayer suite; protocol/schema bumps follow `VERSIONING.md` |
| 6 | Benchmarks show acceptable performance | `room bench` measurements vs `room.json` `benchmarks` targets (measured on this machine, never theoretical) |
| 7 | Dependencies are documented | `room.json` `dependencies` + `CONTRACT.md` "Dependencies" |
| 8 | A rollback path exists | previous copy saved in `.runtime/promotions/<system>-<stamp>/`; git history; `INTEGRATION.json` records the previous hash |

If any post-copy gate (3-5) fails, the tool restores the previous copy automatically.

## Procedure

1. Finish the room work; `room test` and `room bench` pass; update the room README changelog and `room.json` version.
2. `structure.py room promote <system> --dry-run` - fix every unchecked item.
3. `structure.py room promote <system>` - copies `src/` to `room.json` `integration.target` and writes `INTEGRATION.json`
   (room version, source sha256, benchmarks, git commit, previous hash).
4. Wire or update consumers in the sandbox only through the system's public interface. Consumer changes are part of
   the same task and are covered by the sandbox suites.
5. Commit room + sandbox copy + consumer changes together (`promote <system> <version>`), and log it in the task note
   and the room's `integration/README.md` history.

## Rules

- Sandbox copies are read-only: `structure.py check` fails on hash drift. Fix the room and promote again.
- Interface changes: update `CONTRACT.md`, bump the room version (minor for additions, major for breaking changes),
  update consumers and tests in the same change, and note it in the task log.
- Experimental variants stay in `experiments/` until measured and promoted; stable and experimental code can coexist.
- A promotion that changes network messages or saved data must also bump the protocol or world schema version.

## Package rooms

A room with a `"package"` section in `room.json` ([ADR-0010](../DECISIONS/ADR-0010-shared-systems-and-laboratories.md),
first: `movement_core`) keeps its source in a workbench laboratory. The same checklist applies, with these
differences: tests and benchmarks run in the workbench (`room test` / `room bench`); `room promote` installs the
workbench version into every project in `room.json` `consumers` (backups in `.runtime/promotions/`, restored if a
gate fails); any project can pin a version with `room install <room> <project> [--version X.Y.Z]`; releases are tags
`<room>/v<version>` (`room release`). Laboratories reach `main` through
[LABORATORY-PIPELINE.md](LABORATORY-PIPELINE.md).

## Rollback

`git revert <promotion commit>` (preferred), or copy `.runtime/promotions/<system>-<stamp>/` back and re-run
`structure.py test import unit multiplayer`. Rolling back code never rolls back world data; see `VERSIONING.md`.
