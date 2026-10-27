# Security and development safety

This is a local development environment, not a public server. Defaults:

| Area | Default | Where enforced |
|---|---|---|
| Credentials | none needed; never committed; `.env` and `*.local.env` are git-ignored | `.gitignore`, `structure.py check` secret scan |
| Example configuration | `INFRASTRUCTURE/environments/example.env` documents every variable | - |
| Pinned dependencies | Godot by version + SHA-256; Docker base image by digest; Python tooling is stdlib-only | `toolchain.json`, `check` (Dockerfile/toolchain consistency) |
| Network exposure | servers publish UDP on `127.0.0.1` only; a native server binds `127.0.0.1` | compose port binding, env validation (public bind needs `STRUCTURE_ALLOW_PUBLIC_BIND=yes`) |
| Client trust | clients never declare state: requests are validated (types, ranges, ownership, distance, speed); `server_relay` disabled; server-to-client RPCs are authority-only | `net/session.gd`, `world/world_state.gd`, cheat suite |
| Abuse limits | auth payload <= 1 KB, auth timeout 5 s, 8 actions/peer/tick, kick after 50 protocol violations, names sanitised | `net/protocol.gd`, `server/server_app.gd` |
| Containers | non-root user (uid 10001), no extra packages in the runtime stage | `server.Dockerfile` |
| Data safety | atomic saves + backup, refuse unknown/newer worlds, heartbeat lease against two servers on one data dir, `--yes` + automatic snapshot before destructive operations, snapshots never deleted by tooling | `world_store.gd`, `server_app.gd`, `snapshots.py` |

## Unresolved risks (accepted for phase 0.1)

1. **No authentication of identity**: anyone who can reach the port can join with any display name. Acceptable on
   loopback; required before any non-local hosting.
2. **ENet traffic is unencrypted** (Godot supports DTLS; not configured).
3. **Client-predicted movement**: speed/bounds are validated with tolerance, collisions are not; a modified client
   can walk through obstacles at legal speed (ADR-0003).
4. **No rate limiting on position reports** beyond "latest report per tick wins".
5. **Docker Desktop bind mounts** expose world files to anything running as the Windows user.
6. **The server image contains the Godot editor binary** (larger attack surface than an export template; ADR-0005).

Revisit this list before exposing any server beyond the local machine.
