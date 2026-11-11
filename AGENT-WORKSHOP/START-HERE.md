# START HERE - the STRUCTURE workshop

Read this page first (about five minutes), then [PROTOCOLS/WORKSHOP-PROTOCOL.md](PROTOCOLS/WORKSHOP-PROTOCOL.md),
then the documents for the area you will touch. Rules for agents: [../AGENTS.md](../AGENTS.md).

## 1. What STRUCTURE is

An experimental, persistent, systemic multiplayer sandbox about **purpose, survival, emergence and structure** -
how civilisations build, maintain, transform and lose the institutions and infrastructure that hold them together.
A Tower / Stairway to Heaven is the central organising objective, not necessarily an ending. The project is
gameplay- and simulation-first: no art direction or lore yet ([CONCEPTS/PILLARS.md](CONCEPTS/PILLARS.md)).

## 2. Current state (updated 2026-10-27 by tasks [0001](TASKS/0001-bootstrap.md) and [0002](TASKS/0002-first-play-session.md))

**Phase: M0 bootstrap foundation - complete; first human play session done** (loop playable unaided, "felt good",
no rubber-banding; two bugs found and fixed). Next milestone (needs approval): [PLANNING/MILESTONES.md](PLANNING/MILESTONES.md).
Build 0.1.0 - network protocol v1 - world schema v1 - Godot 4.7.2-stable.
Canonical repository: <https://github.com/alexbernardi/structure> (public, [Unlicense](../LICENSE), branch `main`).
Agents on other machines: clone, run `setup`, then pull before starting a task and push task notes with the work.

| Area | What exists |
|---|---|
| Sandbox | Godot project with server / client / bot roles; first-person movement and jumping; placeholder world from a seed; pick up, carry, drop and deposit one resource type; shared construction site that grows; HUD + F3 metrics |
| Multiplayer | dedicated authoritative ENet server; login handshake with protocol check; validated requests; cheat-resistant (tested); players see each other; 30 Hz tick |
| Persistence | world saved on every change (atomic, backed up), schema-checked on load, heartbeat lease, snapshots with guarded restore |
| Containers | server image (unique tags + build manifest), compose environments `dev`, `iso-a`, `iso-b` on localhost, graceful stop, healthcheck, tools image |
| Systems | room template + `movement` room (tests, benchmarks, golden fixture) integrated through the gateway |
| Assets | Blender 5.0.1 pipeline example `resource_stone` (spec -> GLB -> validation -> Godot), reproducible bytes |
| Quality | 8 automated suites, performance baselines, structured logs, static `check` |
| Traversal (5.0, branch `benchmark/opus-traversal`) | [Movement Lab 5.0](DOCUMENTATION/MOVEMENT-LAB-5.md), task [0007](TASKS/0007-unified-traversal.md): vaults only on Space inside a visible interaction region (early press arms the 4.0 approach, late press fits a shorter stride); one traversal controller picks vault > mantle > jump on the ground and ledge grab > air jump > buffer in the air, with chained presses; authored `ClimbUp_1m` mantle / ledge grab (motion-warped) and `DoubleJump`; capability layer (unit-bearing attributes, add/mul/set/cap/floor modifiers, grants/revokes, stamina/energy/heat/mana) with human, cybernetic legs, timed spell and injury (keys 1-4, `--profile=`); course lanes D-G (`lane_d` ...). **5.1** (task [0008](TASKS/0008-traversal-refinement.md)): one authorization gate (no vault from contact, held Space or stale presses; a missed window is a jump), airborne catch -> mantle / climb-over (reach, grip strength, irregular tops), mirrored authored vault chosen by face angle and stride with angle turn and speed lean, lane F test bar solvable, lane H. **5.2** (task [0009](TASKS/0009-hang-angles-slide.md)): jump into a high wall to catch and hang (no press), one Space pulls up (authored two-handed `ClimbUp_2m`); fences and sharp angles climbed square to the face keeping momentum; Ctrl at speed slides (momentum, slopes, steering, 0.8 m collider, authored slide clips); lanes I-L. **5.3** (task [0010](TASKS/0010-crouch-flip.md)): Space while crouched or sliding is a front flip (authored `JogToFlip`, physics jump keeping momentum, turn spread over the real airtime, refused without headroom); lane M. Awaiting user playtest (KI-024) |
| Movement utility | [Movement Lab 4.0](DOCUMENTATION/MOVEMENT-LAB-4.md): one authored running vault (CC0 Quaternius UAL2 `SafetyVault`) on top of the user-approved [3.0](DOCUMENTATION/MOVEMENT-LAB-3.md) authored Quaternius running. Run -> Anticipate -> Vault -> Land -> Run, with collision-safe travel, support-hand contact and repaired first-sprint entry phase. Vault lanes A/B/C (T / Shift+T), F10 overlay, V side view, `--trial=vault` A/B and four Traversal MIDI controls. 6 m/s run, 12 m/s Shift approach (vault travel capped at 8 m/s); no gameplay walking; physics unchanged without a vault. Retained checks: full regression 499/499, vault/MIDI 17/17, Playground 6/6; run CPU checks without competing lab instances (KI-023). Native side/orbit captures verified; human visual/MIDI approval remains open (KI-020). Legacy gait, F9 3.0 A/B, [2.0 treadmill](DOCUMENTATION/MOVEMENT-LAB-2.md), editors, presets and circling benchmark preserved |

Verified and unverified items, test results and open problems: [TASKS/0001-bootstrap.md](TASKS/0001-bootstrap.md).

## 3. Repository map

| Path | Purpose |
|---|---|
| `AGENT-WORKSHOP/` | this headquarters: [PROTOCOLS](PROTOCOLS/), [BLUEPRINTS](BLUEPRINTS/README.md) (templates), [CONCEPTS](CONCEPTS/PILLARS.md), [GAMEPLAY-MAPS](GAMEPLAY-MAPS/FIRST-LOOP.md), [PLANNING](PLANNING/), [TASKS](TASKS/README.md), [DECISIONS](DECISIONS/README.md), [DOCUMENTATION](DOCUMENTATION/), [INVENTORY](INVENTORY/), [RESEARCH](RESEARCH/) (sourced technique and asset reviews); `DOWNLOADS/` holds user-supplied originals and is git-ignored |
| `SANDBOX/` | the playable Godot project, configuration notes, scenarios ([README](../SANDBOX/README.md)) |
| `SYSTEM-ROOMS/` | isolated system laboratories ([README](../SYSTEM-ROOMS/README.md)) |
| `COMMON-ASSETS/` | asset library with metadata and manifest ([README](../COMMON-ASSETS/README.md)) |
| `PIPELINES/` | Blender -> GLB -> validation -> Godot ([README](../PIPELINES/README.md)) |
| `INFRASTRUCTURE/` | toolchain pins, Docker, environments, snapshots ([README](../INFRASTRUCTURE/README.md)) |
| `TESTING/` | shared GDScript runner, Python suites, baselines, fixtures ([README](../TESTING/README.md)) |
| `TOOLS/` | `cli/structure.py`, diagnostics, visualisation ([README](../TOOLS/README.md)) |
| `.tools/`, `.runtime/` | git-ignored: downloaded Godot; local world data, logs, test runs, benchmark output |

## 4. Architecture in brief

- One Godot project, three roles chosen at boot; all RPCs in `net/session.gd`; the server owns every world change
  (`request -> validate -> event -> apply -> broadcast -> save`); clients only apply events to a replica.
- Movement is client-predicted using the integrated movement system and validated by the server (speed budget).
- One JSON world per environment; versions in `project.godot` `[structure]`; build identity in a manifest baked into images.
- Systems are developed in rooms and promoted as hash-tracked copies; assets are generated and deployed the same way.

Details: [DOCUMENTATION/ARCHITECTURE.md](DOCUMENTATION/ARCHITECTURE.md), [DOCUMENTATION/PROTOCOL.md](DOCUMENTATION/PROTOCOL.md),
[DOCUMENTATION/LOG-EVENTS.md](DOCUMENTATION/LOG-EVENTS.md), [DECISIONS/](DECISIONS/README.md) (ADR-0001..0008).

## 5. Tools and dependencies

Python >= 3.11 (stdlib only), Git + LFS, Docker Desktop (containers), Blender 5.0.1 (asset pipeline only).
Godot 4.7.2-stable is downloaded and SHA-256-verified by `setup`. Pins: `INFRASTRUCTURE/builds/toolchain.json`;
details: [INVENTORY/DEPENDENCIES.md](INVENTORY/DEPENDENCIES.md).

## 6. Run the sandbox

```powershell
python TOOLS/cli/structure.py setup             # once per machine / after pin changes
python TOOLS/cli/structure.py play              # native server (env dev) + game window; close the window to stop
python TOOLS/cli/structure.py build             # server image -> then:
python TOOLS/cli/structure.py env up dev        # dockerised dedicated server on udp 127.0.0.1:24565
python TOOLS/cli/structure.py client            # join it (run twice for two players)
python TOOLS/cli/structure.py scenario a        # one server + two client windows   (add --bots for headless)
python TOOLS/cli/structure.py scenario b        # two isolated servers (iso-a, iso-b); stop with --down
python TOOLS/cli/structure.py versions          # what is running / installed
```

Controls: WASD, mouse, Space, E (pick up / deposit), Q (drop), Esc (free mouse), F3 (metrics). All commands:
[DOCUMENTATION/COMMANDS.md](DOCUMENTATION/COMMANDS.md).

## 7. Create a new system room

1. Write a short proposal ([BLUEPRINTS/FEATURE-PROPOSAL.md](BLUEPRINTS/FEATURE-PROPOSAL.md)); get approval if it is architectural.
2. `python TOOLS/cli/structure.py room new <name>` - scaffolds `SYSTEM-ROOMS/<name>/` from `_TEMPLATE` (tests pass immediately).
3. Fill `SPEC.md`, `CONTRACT.md`, `room.json` (benchmark targets!), implement in `src/`, test in `tests/`.
4. `room test <name>`, `room bench <name>`; open `SYSTEM-ROOMS/<name>/project.godot` in the editor for experiments.

## 8. Run tests and benchmarks

```powershell
python TOOLS/cli/structure.py check                       # seconds; run before every commit
python TOOLS/cli/structure.py test                        # all suites (docker needs Docker Desktop)
python TOOLS/cli/structure.py test unit multiplayer       # a subset
python TOOLS/cli/structure.py bench server --docker --bots 8 --duration 30
```

Suites and how to write tests: [DOCUMENTATION/TESTING.md](DOCUMENTATION/TESTING.md). Current numbers:
[INVENTORY/PERFORMANCE-BASELINES.md](INVENTORY/PERFORMANCE-BASELINES.md).

## 9. Propose and integrate a change

1. Follow the [workshop protocol](PROTOCOLS/WORKSHOP-PROTOCOL.md): task note in `TASKS/`, plan with acceptance criteria.
2. Architectural changes: ADR ([BLUEPRINTS/ADR.md](BLUEPRINTS/ADR.md)) + user approval **before** implementing.
3. Systems: `room promote <name>` - the [integration gateway](PROTOCOLS/INTEGRATION-GATEWAY.md) checks contract, tests,
   benchmarks, dependencies, runs the sandbox suites and rolls back on failure.
4. Wire/save format changes: bump versions per [PROTOCOLS/VERSIONING.md](PROTOCOLS/VERSIONING.md); snapshot worlds first.
5. Record results, decisions and open issues; update section 2 of this page.

## 10. Where to find things

| Need | Go to |
|---|---|
| Decisions and their reasons | [DECISIONS/README.md](DECISIONS/README.md) |
| Known issues and limitations | [INVENTORY/KNOWN-ISSUES.md](INVENTORY/KNOWN-ISSUES.md) |
| Security defaults and open risks | [PROTOCOLS/SECURITY.md](PROTOCOLS/SECURITY.md) |
| Conventions (code, units, assets, git) | [PROTOCOLS/CONVENTIONS.md](PROTOCOLS/CONVENTIONS.md) |
| The gameplay loop mapped to code and tests | [GAMEPLAY-MAPS/FIRST-LOOP.md](GAMEPLAY-MAPS/FIRST-LOOP.md) |
| Plans | [PLANNING/BOOTSTRAP-PLAN.md](PLANNING/BOOTSTRAP-PLAN.md), [PLANNING/MILESTONES.md](PLANNING/MILESTONES.md) |
| Movement Lab (MIDI-tuned movement, authored animation, traversal, treadmill lab): status, launch, architecture | [5.0 unified traversal](DOCUMENTATION/MOVEMENT-LAB-5.md), [4.0 vault](DOCUMENTATION/MOVEMENT-LAB-4.md), [3.0 authored running](DOCUMENTATION/MOVEMENT-LAB-3.md), [2.0 treadmill](DOCUMENTATION/MOVEMENT-LAB-2.md), [parameters and MIDI banks](DOCUMENTATION/MOVEMENT-LAB-PARAMETERS.md), tasks [0004](TASKS/0004-movement-lab-2.md), [0005](TASKS/0005-movement-lab-3.md), [0006](TASKS/0006-fluid-traversal-vault.md), [traversal research](RESEARCH/fluid-traversal.md) |
| Asset inventory | [INVENTORY/ASSETS.md](INVENTORY/ASSETS.md) |
