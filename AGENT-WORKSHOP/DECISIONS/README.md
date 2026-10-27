# Architecture decisions

ADRs record decisions that constrain future work. New ADRs use `../BLUEPRINTS/ADR.md`; changing an accepted ADR
needs the user's approval (see `../PROTOCOLS/WORKSHOP-PROTOCOL.md`). Superseded ADRs stay, marked "Superseded by".

| ADR | Decision | Status |
|---|---|---|
| [0001](ADR-0001-monorepo-and-workshop.md) | Modular monorepo with a mandatory agent workshop; documented layout deviations | Accepted |
| [0002](ADR-0002-engine-and-toolchain.md) | Godot 4.7.2-stable + GDScript; pinned, verified, auto-downloaded toolchain; no `class_name` | Accepted |
| [0003](ADR-0003-authoritative-networking.md) | Dedicated authoritative server over ENet; explicit RPC events; auth handshake with protocol version | Accepted |
| [0004](ADR-0004-world-persistence.md) | One JSON world per environment; save-on-change with atomic replace; schema versions; heartbeat lease | Accepted |
| [0005](ADR-0005-containers-and-environments.md) | Headless server image runs the imported project; loopback-only ports; per-environment storage; immutable tags | Accepted |
| [0006](ADR-0006-system-rooms-and-integration.md) | System rooms are standalone Godot projects promoted into the sandbox as hash-tracked copies | Accepted |
| [0007](ADR-0007-asset-pipeline.md) | Blender (pinned 5.0.1) background scripts -> validated GLB; small runtime files committed, large sources in LFS | Accepted |
| [0008](ADR-0008-testing-strategy.md) | Zero-dependency GDScript runner, stdlib Python orchestration, headless bot clients; engine errors fail tests | Accepted |
