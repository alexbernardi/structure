# Performance baselines (initial, 2026-10-27)

Machine: Windows 11 (26200), Intel 64 Family 6 Model 183 (32 logical cores), NVIDIA GeForce RTX 3090 (Vulkan 1.4),
Docker Desktop 29.1.3 on WSL2. Godot 4.7.2-stable. These are **reference points for regression checks, not scalability promises**.
Raw results: `TESTING/performance/baselines/*.json` (re-record with `--record`).

## Server (fixed seed 4242, 30 s, bots run the gather loop; 5 s warm-up excluded)

`python TOOLS/cli/structure.py bench server [--docker] --bots N --duration 30`

| Mode | Bots | Tick avg | Tick p95 (worst interval) | Tick max | CPU avg / max (1 core = 100) | RSS | Net in / out | Deposits |
|---|---|---|---|---|---|---|---|---|
| Docker | 8 | 0.38 ms | 7.7 ms | 10.1 ms | 0.9 % / 1.9 % | 102 MB | 4.2 / 36 KB/s | 31 |
| Docker | 32 | 0.66 ms | 9.3 ms | 12.2 ms | 1.5 % / 2.9 % | 102 MB | 15 / 462 KB/s | 64 |
| Native (Windows) | 8 | 0.40 ms | 7.0 ms | 37.2 ms | n/a | n/a (static 25 MB) | 4.7 / 41 KB/s | 30 |

Observations:
- Tick budget at 30 Hz is 33 ms; average load is ~1-2 % of it. p95 spikes coincide with save-on-change writes
  (Docker Desktop bind mount / Windows file system) - see KI-001.
- Outbound traffic grows ~n² (every player state to every client at 15 Hz): 4x players -> ~13x traffic (KI-003).
- CPU and RSS are measured in-process from `/proc` (Linux only); native Windows runs report null (KI-002).

## Client (windowed, Forward+, vsync off, 2 active bots, 15 s)

`python TOOLS/cli/structure.py bench client --duration 15`

| FPS avg | Frame avg | p50 | p99 | Max | RTT (localhost) |
|---|---|---|---|---|---|
| 1975 | 0.51 ms | 0.48 ms | 0.72 ms | 150 ms (one-time world build on join, KI-005) | 14 ms |

Placeholder geometry only; useful to catch regressions, not to predict the cost of real content.

First human session (task 0002, vsync on, Docker server, 2 players): 143.9 FPS avg locked to the 144 Hz display
(p50 = p99 = 6.94 ms), RTT 29 ms, server tick avg 0.17 ms / max 6.8 ms, 0.6 % CPU.

## Systems

`python TOOLS/cli/structure.py room bench movement` (targets in `SYSTEM-ROOMS/movement/room.json`)

| Benchmark | Measured | Target |
|---|---|---|
| `movement.step` | 0.36 µs/op | <= 2.0 µs |
| `movement.tick_64_players` (64 steps) | 29.3 µs | <= 150 µs |

## Other measured facts

- Server image `structure-server`: 344 MB unpacked (~109 MB compressed); build ~70 s cold, seconds with cache.
- Container start to `server.ready`: ~1 s; `docker stop` to exit (graceful save): ~1.8 s.
- Godot headless import of the sandbox: ~2-3 s. Asset pipeline (Blender 5.0.1 background): a few seconds per asset.
