# Sandbox architecture (0.1.0)

## Roles and scene graph

`main.tscn` -> `main.gd` reads configuration (`core/app_config.gd`) and builds:

```
/root/Main/Session   net/session.gd      every RPC; ENet + SceneMultiplayer; same on every peer
/root/Main/App       one of:
   server/server_app.gd   authoritative: WorldState + WorldStore + metrics; headless
   client/client_app.gd   presentation: WorldView, PlayerController, HUD, ConnectMenu; windowed
   bots/bot_app.gd        scripted headless client for tests and benchmarks
```

| Module | Responsibility |
|---|---|
| `world/world_state.gd` | rules + data (resources, sites, players); `request_*` -> events -> `apply_event` |
| `world/world_gen.gd` | deterministic layout from the seed (obstacles, resource spawns, spawn points) |
| `world/world_store.gd` | JSON persistence, atomic save, schema checks, recovery, migrations |
| `net/protocol.gd` | message constants and validation of client input |
| `systems/movement/` | integrated movement system (promoted from `SYSTEM-ROOMS/movement`) |
| `core/` | config, structured log, build info, metrics, input map |
| `client/` | world presentation (placeholder geometry + pipeline asset), FP controller, avatars, HUD |

## Data flow (one interaction)

```
client E key -> Session._rpc_action("pickup", "r3") ----> server queue -> tick:
     WorldState.request_pickup(peer, "r3")   validates player, carrying, existence, ownership, distance
       ok  -> events [resource_picked] -> apply_event -> broadcast _rpc_event to all -> save if persistent
       bad -> _rpc_event {type: rejected, reason} to that client only
clients: apply_event on their replica -> WorldView updates visuals / HUD
```

Server tick (30 Hz, `Engine.max_fps` = tick rate when headless): position reports (latest per peer, speed-budget
validated, corrections sent) -> queued actions -> player-state broadcast (15 Hz) -> save if dirty -> heartbeat/control
file (1 Hz) -> metrics (every `metrics_interval` s).

## Authority summary

| State | Owner | Clients may |
|---|---|---|
| resources (position, carrier), construction progress, contributions | server | request pickup/drop/deposit |
| player position | client-predicted, server-validated | report position <= speed budget; get corrected otherwise |
| player identity/name | server (sanitised, made unique) | propose a display name at login |

## Persistence and runtime files (per environment data dir)

`world/world.json` (+ `.bak`, transient `.tmp`, `world.v<N>.json` after migrations), `runtime/status.json`
(heartbeat lease, 1 s), `runtime/shutdown.request` (graceful stop request; used by the container entrypoint and tools).

## Metrics

Server `server.metrics` log line: tick avg/p95/max, frame process time, CPU % and RSS (Linux /proc; null on Windows),
static memory, players, entities, nodes, network bytes/s in/out (ENet host statistics), action/move/violation/save counters.
Client: F3 overlay (FPS, frame/physics time, draw calls, RTT, nodes) and `client.metrics` summary on `--quit-after`.
