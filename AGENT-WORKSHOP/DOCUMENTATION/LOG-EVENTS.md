# Structured log events

Every line on stdout is one JSON object: `{"ts", "lvl", "role", "env", "evt", ...fields}` (`core/log.gd`).
Engine errors are plain lines starting with `ERROR:` / `SCRIPT ERROR:`. Summarise a log with
`python TOOLS/diagnostics/log_summary.py <file|->` (e.g. `structure.py env logs dev --tail 5000 | python TOOLS/diagnostics/log_summary.py -`).

## Server

| Event | Level | Key fields |
|---|---|---|
| `server.starting` | info | `build{build,commit,dirty,image,engine,protocol,world_schema}`, world, seed, port, bind, data_dir, tick_rate, pid |
| `server.stale_lease_ignored` | warn | file - a previous server crashed |
| `server.seed_ignored` | warn | configured, world_seed - existing worlds keep their seed |
| `world.loaded` | info | created, recovered, migrated_from, revision, resources, site_progress, file |
| `server.ready` | info | port, world, seed, protocol, world_schema, site_progress, max_players |
| `server.start_failed` | error | reason (`data_dir_in_use` exit 3, `world_load_failed` 4, `listen_failed` 5), detail |
| `player.joined` / `player.left` | info | peer, name, client_build, players |
| `action.accepted` / `action.rejected` | info | peer, action, target, reason |
| `site.progress` | info | site, deposited, by, revision |
| `move.rejected` | debug | peer, reason, reported, server_pos |
| `net.auth_rejected` | warn | peer, reason, client_protocol |
| `net.violation` / `net.kick` | warn | peer, kind/reason, count |
| `world.save_failed` | error | error, file |
| `server.metrics` | info | see ARCHITECTURE.md "Metrics" |
| `server.stopping` / `server.stopped` | info | reason, players / revision, saves, uptime_s |
| `entrypoint.stop_signal` / `entrypoint.exit` | info | container entrypoint (role `entrypoint`) |
| `config.invalid` | error | errors (any role; exit code 2) |

## Client and bot

| Event | Key fields |
|---|---|
| `client.started`, `client.connecting`, `client.joined` | build, renderer / address, name / peer, env, server, players, site_progress |
| `net.rejected_by_server` | reason, info |
| `client.action_rejected`, `client.position_corrected` (debug) | action, target, reason / position |
| `client.connection_lost` | reason |
| `client.screenshot`, `client.metrics` | path, error / frames, fps_avg, frame_avg/p50/p99/max_ms, rtt_ms, renderer, vsync |
| `client.session` | logged when the window closes (or on automated quit): reason, run_s, played_s, distance_m, jumps, actions_sent, pickups, deposits, rejections, corrections, disconnects, players_seen, final_site_progress |
| `bot.joined`, `bot.finished` | peer, name, players, site_progress / ok, reason, deposits, final_progress, errors |
