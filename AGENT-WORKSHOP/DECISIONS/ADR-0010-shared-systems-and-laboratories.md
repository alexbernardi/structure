# ADR-0010: Package systems, pinned installs and laboratories

Status: Accepted (2026-11-11, requested by the user in the "Movement System Promotion & Integration Pipeline" brief).
Amends [ADR-0006](ADR-0006-system-rooms-and-integration.md) (rooms) and [ADR-0009](ADR-0009-utility-tree.md)
(utilities are never promoted) for package systems; neither is otherwise changed.

## Context

The movement laboratory (`utility/movement/flat-plane`, ADR-0009) produced the approved movement character. Other
laboratories (combat and weapons next, then flight, AI, ...) must use it without copying scripts by hand, while
movement keeps evolving in its own laboratory. Constraints found by inspection:

- one git repository, one remote; laboratories so far were branches checked out in sibling worktrees;
- Godot cannot load files outside a project's `res://`, so every project needs its own copy of shared code;
- the movement scripts preload absolute `res://` paths, and its modifier factory loads itself by path at runtime;
- ADR-0006 rooms keep their source in `SYSTEM-ROOMS/<room>/src/` and promote hash-tracked copies into the sandbox -
  but a system as large as movement is developed, played and tuned in its laboratory, not in a bare room project.

## Decision

1. **Package rooms.** A room may declare `"package"` in `room.json`: its source lives in a *workbench* laboratory
   (`package.source`, e.g. `utility/movement/flat-plane/systems/movement_core`), and the room folder holds the
   version, `CONTRACT.md`, `SPEC.md`, changelog and integration history. The room's tests and benchmarks run in the
   workbench. The first package room is `movement_core` 1.0.0.
2. **Fixed mount.** Every project mounts a package at `res://systems/<room>/` (the same folder the sandbox already
   uses for promoted rooms), so the package's absolute paths work everywhere, including its workbench.
3. **Pinned, hash-checked installs.** `structure.py room install <room> <project> [--version X.Y.Z]` copies the
   package (the current source, or a released tag) and writes `INTEGRATION.json` (version, tag, sha256, commit).
   Copies are read-only: `check` fails on hash drift and warns when a consumer is behind (compatible or breaking).
   Git stores identical files once, so copies cost no repository space.
4. **Releases are tags** `<room>/v<version>` (`room release`), semantic versions per the room's CONTRACT: patch =
   fixes, minor = additions, major = contract breaks with migration notes. Consumers stay on their pin until they
   choose to update; a breaking update is never installed silently (`lab sync --update-systems` takes only same-major).
5. **Laboratories** are branches `lab/<name>` in their own worktrees, created from `main` by `lab create`, with a
   Godot project at `LABS/<name>/` (new top-level folder) scaffolded from `LABS/_TEMPLATE` and its systems pinned in
   `lab.json`. `lab sync` merges `main` in (never rebases or overwrites); `lab validate` runs the checks;
   `lab promote` merges the lab into a fresh integration branch from `main` in a temporary worktree, runs the gates
   there, and with `--merge` fast-forwards `main` to exactly the validated merge commit. Nothing pushes.
6. The movement laboratory stays where it is (`utility/movement/flat-plane`) as the workbench of `movement_core`;
   its lab-only code (course, MIDI tuning, legacy procedural animation, capture tools) never ships in the package.

## Consequences

+ A new laboratory gets the approved movement character with one command and no copied scripts.
+ Movement can change in its workbench without touching other laboratories; they move to a new version deliberately.
+ Every consumer's version is visible (`room status`), drift is caught, and any released version can be reinstalled.
+ Promotions are validated on the merged result, not on the laboratory alone, and `main` only ever moves to a
  validated commit.
- Each consumer carries a copy of the package (about 10 MB of animation GLBs for movement_core) in its working tree.
- Package rooms rely on the mount convention instead of relative preloads (SYSTEM-ROOMS README rule), because the
  package's runtime `load()` of its own path cannot be relative.
- Laboratory worktrees are sibling folders; `git worktree list` shows them, and removing one is a manual step.

## Alternatives considered

- **Git submodules / subtrees per system** - a second repository per system and fragile tooling on Windows, for no
  gain over pinned copies inside one repository.
- **Symlinks or junctions into each project** - not versioned, break on clone, and Godot's import cache treats them
  as separate files.
- **Godot addons in `addons/`** - the same copy problem with an editor plugin wrapper the system does not need.
- **Moving the movement laboratory into `SYSTEM-ROOMS/`** - churn across about 550 tests and tools, and it would mix
  the MIDI tuning utility into a room.
