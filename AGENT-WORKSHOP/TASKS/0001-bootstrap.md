# 0001 - Repository bootstrap

Status: done     Owner: founding engineering agent     Date: 2026-10-27

## Goal
Establish the workshop, a minimal playable multiplayer sandbox with one gameplay loop, containerised dedicated
servers, versioning/snapshots, one system room, one asset pipeline example and automated validation
(brief: "PROJECT STRUCTURE - Repository Bootstrap"). Plan: `../PLANNING/BOOTSTRAP-PLAN.md`.

## Impact
Everything (new repository). Versions introduced: build 0.1.0, protocol v1, world schema v1 (min v1).

## Validation summary (executed on the dev machine, Windows 11 + Docker Desktop 29.1.3)

| Completion criterion | Evidence | Result |
|---|---|---|
| A new agent can enter the workshop and understand how to contribute | `AGENTS.md` -> `START-HERE.md` -> protocols/docs; `check` verifies all doc links | done (judgement + link check) |
| Godot project opens without errors | headless import + smoke load of every script/scene, zero engine errors | verified |
| A player can enter the sandbox | windowed client joined a native server and rendered the world (screenshot check, Forward+, ~135 FPS vsync on) | verified (automated screenshot, no human play session) |
| Headless dedicated server runs in Docker | container healthy, `server.ready`, zero engine errors | verified |
| Two clients connect and observe each other | bots report each other's names and >5 replicated moves (native and Docker); windowed client showed a bot avatar | verified |
| Players cooperatively contribute to one site | two bots each deposit; both observe progress 2; contributors recorded | verified |
| Server owns and persists progress | cheat suite (8+ refused manipulations); graceful restart, crash (kill) and container re-creation keep progress | verified |
| Second isolated server runs concurrently | Scenario B test: two containers, separate ports/worlds/seeds/storage, no cross-talk | verified |
| Build versions can be identified | build manifest in image label + `res://build_manifest.json`; `versions`, `builds`; servers log and send it | verified |
| A compatible world snapshot can be restored | snapshot create/restore with integrity, schema, world-id and running-server guards (unit-tested) and end-to-end on `dev` | verified |
| A system room runs tests independently | `room test movement` (10 tests) and a freshly scaffolded template room | verified |
| One asset generated in Blender and imported into Godot | `pipeline run resource_stone` (Blender 5.0.1) -> validated GLB -> in-engine dimension test; regeneration byte-identical | verified |
| Essential automated checks pass | `structure.py test --with-blender`: 8/8 suites | verified |

## Outcome
- Implemented as described in `START-HERE.md` section 2; decisions ADR-0001..0008; baselines in
  `../INVENTORY/PERFORMANCE-BASELINES.md`; open problems in `../INVENTORY/KNOWN-ISSUES.md`.
- Deviations from the brief's tree: ADR-0001.
- Not verified: human play sessions with real input; client on a second machine/LAN; Linux-native client; macOS;
  standalone exports (export templates not downloaded); fsync-level durability; CPU/RSS of native Windows servers.

## Final run (2026-10-27, after commit 1d818e9 + documentation updates)

`python TOOLS/cli/structure.py test --with-blender` - **all 8 suites passed**:

| Suite | Result |
|---|---|
| check | 0 errors, 0 warnings (pins, envs, system drift, asset hashes, secrets, documentation links) |
| tools | 29 Python tests passed |
| import | all projects imported; smoke load of 28 scripts/scenes, 0 failures |
| unit | 34 GDScript tests passed (incl. v1 world fixture and in-engine asset check) |
| rooms | movement 10/10; template-scaffolded room 1/1 + benchmark within target |
| pipeline | library consistent; Blender 5.0.1 regeneration byte-identical to the committed GLB |
| multiplayer | 8/8 (two-client cooperation, cheat suite, protocol mismatch, server full, graceful + crash persistence, lease, newer schema) |
| docker | 3/3 (container persistence across re-creation, graceful `docker stop`, Scenario B isolation) |

Also executed by hand through the CLI with the clean build `structure-server:0.1.0-1d818e9`:
`setup`; `versions`; `builds`; `scenario b` (+ `--down`); `scenario a --bots`; snapshot create -> restore refused while
running -> refused without `--yes` -> dry run -> restore with automatic `pre-restore` snapshot -> new client sees the
restored progress; `compat --client current --server 0.1.0-1d818e9 --snapshot dev/<id>`; `play` (window joined the
restored world on Vulkan/RTX 3090; closing it stopped the server gracefully, no orphan processes);
`room promote movement` (gateway incl. sandbox suites); `pipeline run resource_stone`; all benchmarks with `--record`.
Linux tools container: `test rooms unit` passed with Linux Godot; movement golden trajectory bit-exact (KI-010 resolved).

## Next steps
Milestone M1 proposal in `../PLANNING/MILESTONES.md` (requires approval).
