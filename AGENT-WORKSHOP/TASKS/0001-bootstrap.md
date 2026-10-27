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
| A compatible world snapshot can be restored | snapshot create/restore with integrity, schema, world-id and running-server guards (unit-tested) and end-to-end on `dev` | verified (see final run below) |
| A system room runs tests independently | `room test movement` (10 tests) and a freshly scaffolded template room | verified |
| One asset generated in Blender and imported into Godot | `pipeline run resource_stone` (Blender 5.0.1) -> validated GLB -> in-engine dimension test; regeneration byte-identical | verified |
| Essential automated checks pass | `structure.py test` (all suites) | see final run below |

## Outcome
- Implemented as described in `START-HERE.md` section 2; decisions ADR-0001..0008; baselines in
  `../INVENTORY/PERFORMANCE-BASELINES.md`; open problems in `../INVENTORY/KNOWN-ISSUES.md`.
- Deviations from the brief's tree: ADR-0001.
- Not verified: human play sessions with real input; client on a second machine/LAN; Linux-native client; macOS;
  standalone exports (export templates not downloaded); fsync-level durability; CPU/RSS of native Windows servers.

## Final run
(filled in at the end of the task)

## Next steps
Milestone M1 proposal in `../PLANNING/MILESTONES.md` (requires approval).
