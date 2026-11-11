# Commands

Everything runs through one stdlib-only CLI: `python TOOLS/cli/structure.py <command>` (from the repository root;
`--help` on any command). Requirements: Python >= 3.11; Docker Desktop for container commands; Blender 5.0.1 for the
asset pipeline. Godot is downloaded by `setup`.

## Setup and inspection

| Command | What it does |
|---|---|
| `setup` | Downloads pinned Godot 4.7.2 into `.tools/` (SHA-256 verified), imports all Godot projects, enables Git LFS locally, prints `versions` |
| `versions [--strict]` | Build version, git commit, protocol/schema versions, pinned vs installed tools, environments, local builds, integrated systems |
| `check` | Static checks: layout, pins (toolchain.json vs Dockerfile vs project.godot), env files and ports, system drift, asset hashes, secret patterns |

## Playing

| Command | What it does |
|---|---|
| `play [--env dev] [--name you]` | Native headless server for the environment + windowed client; closing the window stops the server gracefully |
| `client [--connect host:port] [--name you]` | Windowed client only (default target: the dev environment's port) |
| `server --native [--env dev]` | Native headless server in the foreground (Ctrl+C = graceful stop) |
| `server [--env dev] [--image-tag T]` | Same as `env up` (Docker) |

Controls: WASD move, mouse look, Space jump, E pick up / deposit, Q drop, Esc release mouse, F3 debug overlay.

## Builds and environments (Docker)

| Command | What it does |
|---|---|
| `build [--tools]` | Builds `structure-server:<version>-<sha7>[-dirty.<UTC>]` with the build manifest baked in (and `structure-tools:local`) |
| `builds` | Lists local server images with their manifests (version, commit, protocol, schema, Godot) |
| `env list` | All environments with container state, players and progress |
| `env up <env> [--image-tag T]` | Starts the environment's container (pinned tag from the env file, else the newest build) and waits for `server.ready` |
| `env down <env>` | Graceful stop + remove container/network; world data is kept |
| `env status <env>` / `env logs <env> [--tail N]` | Container + heartbeat status and `docker stats` / structured logs |
| `env purge <env> --yes [--no-snapshot]` | **Destructive**: deletes the environment's world data (takes a final snapshot first) |
| `scenario a [--native] [--bots]` | Scenario A: one server (env `dev`) + two windowed clients (or two headless bots) |
| `scenario b` / `scenario b --down` | Scenario B: `iso-a` and `iso-b` side by side with separate ports, worlds and storage |

Manual compose equivalent: see `INFRASTRUCTURE/docker/README.md`.

## World data

| Command | What it does |
|---|---|
| `snapshot create <env> [--label L]` | Copies the current world into `INFRASTRUCTURE/snapshots/<env>/<UTC>-<label>/` with metadata and sha256 |
| `snapshot list [env]` | Lists snapshots (world, schema, revision, progress, source build) |
| `snapshot restore <env> <id> --yes [--build T] [--dry-run] [--allow-other-world]` | Guarded restore (see `PROTOCOLS/VERSIONING.md`) |
| `compat --server T [--client C] [--snapshot env/id]` | Offline compatibility check; `T`/`C` = image tag, manifest path or `current` |

## Tests, benchmarks, rooms, assets

| Command | What it does |
|---|---|
| `test [suites...] [--skip ...] [--with-blender]` | Suites: `check tools import unit rooms utility labs pipeline multiplayer docker` (default: all). See `TESTING.md` |
| `bench movement\|server\|client [--bots N] [--duration S] [--seed X] [--docker] [--record]` | Fixed-seed benchmarks; `--record` updates `TESTING/performance/baselines/` |
| `room list` / `room new <name>` | List rooms / scaffold a room from `_TEMPLATE` |
| `room test <name> [--experiments]` / `room bench <name>` | Isolated tests / benchmarks vs `room.json` targets |
| `room status <name>` / `room promote <name> [--dry-run]` | Integration state (drift, pending; a package room lists every consumer's pin) / integration gateway |
| `room install <room> <project> [--version X.Y.Z] [--force]` | Install a package room (e.g. `movement_core`) into a Godot project at `res://systems/<room>/`, pinned and hash-recorded; `--version` installs a released tag |
| `room release <room>` | Tag the current commit `<room>/v<version>` (from `room.json`; clean tree required; not pushed) |

## Laboratories ([LABORATORY-PIPELINE.md](../PROTOCOLS/LABORATORY-PIPELINE.md))

| Command | What it does |
|---|---|
| `lab create <name> [--systems room[@version]]... [--base main] [--path dir]` | Branch `lab/<name>` + worktree from main, `LABS/<name>/` from `LABS/_TEMPLATE`, systems pinned, one commit |
| `lab list` | Laboratory branches, their worktrees and how far ahead of / behind main they are |
| `lab sync [--update-systems]` | In a lab worktree: merge main in (no rebase; stops on conflicts), report pins; re-pin compatible updates |
| `lab validate [name]` | Static checks, the lab's tests, its pins (a workbench: its suite) |
| `lab promote <name> \| --branch <b> [--merge] [--gates ...]` | Merge into a fresh integration branch from main, run the gates there; `--merge` fast-forwards main to the validated merge (never pushes) |
| `pipeline run [asset]` | Blender -> GLB -> validation -> library -> consumers -> Godot import (default asset `resource_stone`) |
| `pipeline check` / `pipeline deploy [asset]` | Consistency check without Blender / re-deploy library copies |

## Running Godot directly (debugging)

```powershell
$g = ".tools/godot/4.7.2-stable/Godot_v4.7.2-stable_win64_console.exe"
& $g --path SANDBOX/godot -e                                   # open the sandbox in the editor
& $g --headless --path SANDBOX/godot -- --server --port=24565 --data-dir=$PWD/.runtime/envs/dev/data --world-id=dev
& $g --path SANDBOX/godot -- --connect=127.0.0.1:24565 --name=me
& $g --headless --path SANDBOX/godot --script $PWD/TESTING/harness/run_gd_tests.gd -- --dir=res://tests/unit
```

All game options (`-- --key=value`, or `STRUCTURE_*` environment variables) are listed in `SANDBOX/godot/core/app_config.gd`.
