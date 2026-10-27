# ADR-0003: Dedicated authoritative server over ENet with explicit RPC events

Status: Accepted (2026-10-27)

## Context
Multiplayer is foundational. Clients must not be able to declare resource ownership or construction progress.
The brief suggests Godot's built-in ENet unless research shows otherwise; nothing did.

## Decision
- One Godot project runs as `server` (headless), `client` (windowed) or `bot` (headless scripted client).
- `ENetMultiplayerPeer` + `SceneMultiplayer`; `server_relay` disabled; spare transport slots so over-capacity clients
  receive an explicit `server_full`.
- **Authentication phase** (`SceneMultiplayer.auth_callback`): the client sends `{protocol, build, name}`; the server
  rejects protocol mismatches before the client can join or receive any RPC.
- **All RPCs live in `net/session.gd`** (identical configuration on every peer). Client->server: `_rpc_state`
  (unreliable_ordered, channel 1) and `_rpc_action` (reliable, channel 0) with `Variant` arguments validated by
  `net/protocol.gd`. Server->client RPCs are `authority`-only: welcome (full snapshot), events, player states (15 Hz),
  position corrections.
- **Event model**: `WorldState.request_*()` validates and returns events; the server applies, broadcasts and persists
  them; clients apply the same events to a read-only replica. Requests are queued and processed in the 30 Hz server tick.
- **Movement** is client-predicted with the shared movement system and validated on the server with a speed budget
  (bursts tolerated, sustained speed capped); violations are corrected. Interactions use the server's position.
- `MultiplayerSynchronizer`/`MultiplayerSpawner` are not used yet: explicit messages keep authority and bandwidth
  visible and testable from headless bots.

## Consequences
+ Cheating attempts are rejected (verified by the bot cheat suite); protocol drift is caught at login.
- Collisions are not server-validated (see `PROTOCOLS/SECURITY.md`); full server-side simulation is a future step.
- Every message change bumps `structure/network/protocol_version`.
