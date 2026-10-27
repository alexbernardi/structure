# ADR-0004: World persistence - one JSON document per environment

Status: Accepted (2026-10-27)

## Context
The world must remember construction progress across restarts, never lose data silently, and reject data written by
incompatible builds. The world is tiny today (one site, about a dozen resources).

## Decision
- `<data_dir>/world/world.json` (sorted keys, rounded floats) with `schema_version`, `world_id`, `seed`,
  `spawn_counter`, `revision`, resources, sites, `saved_at`, `server_build`.
- **Save on change**: every persistent event marks the world dirty; it is written at the end of the same tick
  (write `.tmp` -> previous becomes `.bak` -> rename). Graceful shutdown also saves.
- **Refusals instead of guesses**: corrupt files, newer schemas, other world ids, or a `.bak` without `world.json` stop
  the server with a clear `server.start_failed` event and leave files untouched. An interrupted save is recovered from `.tmp`.
- **Migrations**: `WorldStore.migrate()` upgrades step by step and keeps the original as `world.v<N>.json`.
- Carried resources are saved at their last resting position; players are session-only.
- **Heartbeat lease** `<data_dir>/runtime/status.json` (1 s): a second server on the same data dir refuses to start;
  a stale lease (crashed server) is detected by observing it for 3 s.

## Consequences
+ Verified: graceful restart, hard kill, container re-creation and refusal cases (multiplayer and docker suites).
- Whole-file rewrites cost a few ms on Docker Desktop bind mounts (see `INVENTORY/PERFORMANCE-BASELINES.md`);
  revisit (incremental or background saves) when the world grows or tick spikes matter.
- No fsync: power loss may lose the last save (acceptable for development).
