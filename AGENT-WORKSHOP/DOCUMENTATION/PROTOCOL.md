# Network protocol v1

Transport: ENet via `ENetMultiplayerPeer`; default UDP port 24565. Channel 0 reliable ordered, channel 1 unreliable
ordered. Defined in `SANDBOX/godot/net/session.gd` (RPCs) and `net/protocol.gd` (validation).
Any change to this page's tables requires bumping `structure/network/protocol_version`.

## Authentication (SceneMultiplayer auth phase, before any RPC)

| Direction | Payload (UTF-8 JSON, <= 1 KB) | Server behaviour |
|---|---|---|
| client -> server | `{"protocol": int, "build": str, "name": str}` | validates; `protocol_mismatch`, `server_full`, `not_ready` or `bad_hello_*` -> reply + disconnect after 0.5 s |
| server -> client | `{"ok": bool, "reason": str, "info": {...}}` | client completes auth on `ok`, otherwise reports `reason` |

Auth timeout 5 s. Display names are sanitised (printable, <= 24 chars) and made unique (`name#2`).

## Client -> server

| RPC | Mode | Arguments | Validation / limits |
|---|---|---|---|
| `_rpc_state` | unreliable_ordered, ch 1, ~20 Hz | `position: Vector3`, `yaw: float` | finite, abs <= 10 000; world bounds; speed budget (1.5x movement bound, 1 s burst) -> else `_rpc_correct` |
| `_rpc_action` | reliable, ch 0 | `action: "pickup"\|"drop"\|"deposit"`, `target: id` (`""` for drop) | ids `[a-z0-9_]{1,32}`; <= 8 per tick; game rules -> `rejected` event |

Malformed arguments count as violations (`net.violation`); 50 violations kick the peer.

## Server -> client (`authority` mode: clients cannot send these)

| RPC | Mode | Payload |
|---|---|---|
| `_rpc_welcome` | reliable | `{you, name, env, server: build summary, rules: {interact_range, deposit_range, movement, sync_rate}, snapshot}` |
| `_rpc_event` | reliable | one event (below) |
| `_rpc_players` | unreliable_ordered, ch 1, 15 Hz | `[[peer, position, yaw], ...]` |
| `_rpc_correct` | reliable | `position: Vector3` (authoritative position after a rejected move) |

## Events

| `type` | Fields | Persistent |
|---|---|---|
| `resource_spawned` | `id, seq, kind, pos` | yes |
| `resource_picked` | `id, by` | no (saved at last resting position) |
| `resource_dropped` | `id, pos` | yes |
| `resource_deposited` | `id, site, by, by_name, deposited` | yes |
| `player_joined` | `peer, name, pos, yaw` | no |
| `player_left` | `peer` | no |
| `rejected` (to one client) | `action, target, reason` | - |

Rejection reasons: `unknown_player`, `already_carrying`, `no_such_resource`, `resource_taken`, `out_of_range`,
`not_carrying`, `no_such_site`, `bad_action`. Move rejections: `out_of_bounds`, `too_fast` (answered with `_rpc_correct`).
