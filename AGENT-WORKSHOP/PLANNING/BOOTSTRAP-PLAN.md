# Bootstrap Plan — Architecture & Implementation

Status: **executed** (see `../TASKS/0001-bootstrap.md` for the outcome log).
Owner: founding engineering agent. Date: 2026-10-27.

## 1. Environment inspection (2026-10-27)

| Tool | Found | Decision |
|---|---|---|
| Godot | not installed | Pin **4.7.2-stable** (latest stable, Aug 2026). `structure.py setup` downloads the official build to `.tools/` and verifies SHA-256. |
| Blender | 4.2.0 and 5.0.1 installed (not on PATH) | Pin **5.0.1** (installed; used to generate committed assets). |
| Docker | Desktop 29.1.3 (WSL2), Compose v2.40 | Base image `debian:trixie-slim` pinned by digest. |
| Python | 3.13.0 | Tooling is **stdlib-only**, requires >= 3.11. |
| Git / LFS | 2.45 / 3.5 | Repo initialised on `main`; LFS rules for large source assets. |

Pins live in exactly one place: `INFRASTRUCTURE/builds/toolchain.json`.

## 2. Architecture overview

```
           Windows (native)                          Docker Desktop (Linux)
 ┌──────────────────────────────┐        ┌─────────────────────────────────────┐
 │ Godot client (windowed)      │  UDP   │ structure-server:<version>-<sha>    │
 │  ClientApp ── Session(RPC) ──┼──ENet──┼─ Session(RPC) ── ServerApp          │
 │  WorldReplica (read-only)    │ 127.0.0.1 │  WorldState (authoritative rules) │
 └──────────────────────────────┘        │  WorldStore ── /data (bind mount)   │
 ┌──────────────────────────────┐        └─────────────────────────────────────┘
 │ Bot client (headless, tests) │── same protocol ──┘   one container + one data
 └──────────────────────────────┘                       dir per environment
```

* **One Godot project** (`SANDBOX/godot`) runs in three roles chosen at boot:
  `server` (headless, authoritative), `client` (windowed player), `bot` (headless scripted client for tests/benchmarks).
* **Server authority**: clients send *requests* (`pickup`, `drop`, `deposit`, position reports). The server validates
  them against `WorldState` rules, produces *events*, applies them, persists, and broadcasts. Clients only apply
  server events to a read-only replica. Movement is client-predicted but speed/bounds-validated by the server.
* **Persistence**: one JSON world file per environment, saved atomically on every persistent change;
  `schema_version` with explicit migration/refusal rules.
* **System rooms** are standalone mini Godot projects. A tested room is *promoted* into
  `SANDBOX/godot/systems/<name>/` by the integration gateway (hash-tracked copy; no direct edits in the sandbox).
* **Assets**: spec → Blender script (background) → GLB → validation → deployed into consuming Godot projects.
* **Tooling**: one stdlib Python CLI, `python TOOLS/cli/structure.py`, wraps every workflow.

## 3. Phase plan, acceptance criteria and validation

| Phase | Deliverables | Acceptance / validation |
|---|---|---|
| A Workshop | Tree, `AGENTS.md`, `START-HERE.md`, protocols, templates, ADRs, this plan | A new agent can find process, decisions, commands from `AGENTS.md` in <= 2 hops |
| B Sandbox | Godot project, FP controller, placeholder world, interaction ray, HUD | Headless import has no errors; smoke-load of all scripts/scenes; windowed screenshot |
| C Multiplayer | ENet server, auth handshake (protocol check), headless role, Dockerfile, compose | Native + Docker server start; two bot clients connect and observe each other |
| D Gameplay loop | Resource pickup → carry → deposit → site progress → broadcast → persist | Bot integration tests incl. cheat attempts; restart (graceful and kill) keeps progress |
| E Rooms + pipeline | `_TEMPLATE`, `movement` room (tests + benchmarks), promotion; Blender → GLB → Godot | Room tests pass in isolation; GLB validated and imported; used by the sandbox |
| F Versions + validation | Build manifest, unique image tags, snapshots (create/list/restore + compat rules), compat check, scenario A/B tooling, baselines | Snapshot restore refuses incompatible worlds; scenario B isolation test; `structure.py test all` |

## 4. Explicit non-goals for this bootstrap

AI/A-Life, combat, inventory beyond "carry one item", progression, world generation beyond a seeded scatter,
art direction, lore, production deployment, external telemetry.

## 5. Risks

| Risk | Mitigation |
|---|---|
| Client-predicted movement can be abused (speed hacks within tolerance) | Server speed/bounds validation now; full server simulation is a future movement-room milestone (ADR-0003) |
| Docker Desktop UDP forwarding quirks | Integration test connects bots through the published UDP port |
| Godot global class cache missing on fresh clones | No `class_name` in gameplay code: explicit `preload` dependencies; CLI always imports before running |
| Save-on-change cost grows with world size | Measured in server benchmark; revisit when the world file exceeds ~1 MB |
