# 0002 - First human play session

Status: done     Owner: agent + Alex (player)     Date: 2026-10-27

## Goal
First session with a human at the keyboard and mouse: does the first loop work and feel right for a person,
not only for bots? Find bugs, friction and tuning problems that automated tests cannot see.

## Setup
- Server: Docker environment `dev` (`structure-server:0.1.0-1d818e9`, udp 127.0.0.1:24565), world `dev` restored to
  progress 2; safety snapshot `dev/20261027T233500Z-pre-playtest-1`.
- Client: native Windows window (`structure.py client --name alex`), Forward+, Vulkan, RTX 3090, vsync on.
- Telemetry: new `client.session` + `client.metrics` summary when the window closes (distance, jumps, actions,
  pickups, deposits, rejections, corrections, disconnects, FPS distribution); server logs/metrics via `env logs dev`.

## Pre-flight findings (fixed before the session)
1. **Resource colour-space bug** - spec colours (sRGB) were written into Blender's linear Base Color, so stones
   rendered tan, nearly the same as the structure's blocks. Generator now converts sRGB -> linear; the GLB validator
   checks `baseColorFactor` against the spec (it flagged the old file); `resource_stone` regenerated as version 2.
2. **No telemetry on a normal window close** - only automated quits logged metrics; added the session summary.

## Acceptance criteria (what we want to learn)
| # | Question | Evidence |
|---|---|---|
| 1 | Can a human join, look around, move and jump comfortably? | feedback (mouse sensitivity, speed, jump), distance/jumps |
| 2 | Can they find a stone, pick it up, carry it and deposit it without help? | pickups/deposits, rejections, feedback on prompts |
| 3 | Does the structure visibly grow, and does progress persist after leaving and rejoining? | progress before/after, rejoin |
| 4 | Does the server ever fight the player (rubber-banding)? | corrections (client), moves_rejected (server) |
| 5 | Performance during real play | FPS/frame-time distribution, RTT, server tick metrics |
| 6 | Bugs, confusion, fun | free-form feedback |

## Session log (2026-10-27 23:37-23:41 UTC)

Alex played 3 min 48 s; a companion bot (`mason-bot`, plan `wander`) joined after ~2 min at Alex's request.

| Measure | Result |
|---|---|
| First deposit | 19 s after joining, without guidance beyond the controls card |
| Movement | 931 m walked, 34 jumps, **0 server corrections** (no rubber-banding), 0 rejected moves server-side |
| Interactions (Alex) | 30 pickups, 19 drops, **11 deposits**; **0 rejected actions** |
| Structure | 2 -> 27 when Alex left; 33 after mason-bot (20 deposits) was stopped |
| Client performance | 143.9 FPS avg, vsync-locked (p50 = p99 = 6.94 ms); one 127 ms frame on join (KI-005); RTT 29 ms via Docker |
| Server | 0 engine errors, 0 violations, 50 saves, tick avg 0.17 ms (max 6.8 ms), CPU 0.6 %, RSS 102 MB |
| Exit | server logged `player.left` 3 ms after the window closed (clean disconnect) |
| Persistence | container restarted: world loaded with 33, a new client saw 33; snapshot `dev/20261027T234833Z-post-playtest-1` |

**Player feedback:** "exited, test successful"; "Felt good - nothing to change yet" (no tuning requested for mouse,
movement, jump or prompts).

### Acceptance criteria
| # | Result |
|---|---|
| 1 Join, look, move, jump comfortably | yes - 931 m / 34 jumps, feedback "felt good" |
| 2 Find, pick up, carry, deposit unaided | yes - first deposit after 19 s, 11 deposits, no rejections |
| 3 Structure grows visibly; progress persists | yes - live growth to 27/33; persisted across a server restart (verified by restart + observer, not by Alex rejoining) |
| 4 No fighting the server | yes - 0 corrections, 0 rejected moves |
| 5 Performance | yes - vsync-locked 144 FPS, 29 ms RTT, server idle |
| 6 Bugs | 2 found and fixed (below) |

### Bugs found by the human session (fixed)
1. **Resource colour space** (pre-flight screenshot) - see "Pre-flight findings"; `resource_stone` v2.
2. **RPC after closing the session** - closing the window logged `RPC '_rpc_state' on yourself is not allowed`: the
   close handler closed the network session but the client ran one more frame and sent its position. Fix: sends are
   ignored unless connected (`net/session.gd`); the client stops processing on close (`client_app.gd`); automated quits
   now replay a real window close (the request arrives before `_process`, as for a player).
   Regression test `test_client_presentation_follows_server_and_exits_cleanly` runs the real client headless
   (`--allow-headless`) next to a gathering bot - **verified to fail with the original bug and pass with the fix**.
   It is also the first automated coverage of client presentation code (world view, avatars, HUD, events).

### Validation after the fixes
`structure.py test`: 8/8 suites (multiplayer now 9 tests); pipeline check passes with the new colour validation.

## Outcome and next steps
- The first loop is playable and readable for a human with the default tuning; no tuning changes requested.
- Bots are faster builders than humans (20 vs 11 deposits per ~2-4 min) because they walk through obstacles (KI-008):
  fine for tests, but keep it in mind before using bot numbers as gameplay balance.
- Still unverified: two humans at once, clients on another machine/LAN, longer sessions.
- Next: milestone M1 (`../PLANNING/MILESTONES.md`) after approval; a second session with two humans would close the
  remaining multiplayer gap.

