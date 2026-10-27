# Docker

| File | Purpose |
|---|---|
| `server.Dockerfile` | stages: `godot` (verified download), `project` (headless import; fails on engine errors), `runtime` (server, non-root, healthcheck), `tools` (Linux Godot + Python) |
| `entrypoint.sh` | PID 1: starts the server, turns SIGTERM/SIGINT into a graceful save via `/data/runtime/shutdown.request` |
| `healthcheck.sh` | healthy while `/data/runtime/status.json` is fresher than 10 s |
| `compose.server.yml` | one server per compose project; all values come from environment variables |
| `compose.tools.yml` | tools container with the repository bind-mounted at `/repo` |

Preferred: `python TOOLS/cli/structure.py env up <env>`. Manual equivalent (PowerShell, from the repo root):

```powershell
$env:STRUCTURE_IMAGE = "structure-server:<tag>"            # see: python TOOLS/cli/structure.py builds
$env:STRUCTURE_DATA_DIR = "$PWD/.runtime/envs/dev/data"
docker compose -p structure-dev --env-file INFRASTRUCTURE/environments/dev.env -f INFRASTRUCTURE/docker/compose.server.yml up -d
docker compose -p structure-dev -f INFRASTRUCTURE/docker/compose.server.yml logs -f
docker compose -p structure-dev --env-file INFRASTRUCTURE/environments/dev.env -f INFRASTRUCTURE/docker/compose.server.yml down
```

Tools container: `structure.py build --tools`, then
`docker compose -f INFRASTRUCTURE/docker/compose.tools.yml run --rm tools python3 TOOLS/cli/structure.py test rooms unit`.

Ports are published on `127.0.0.1` only (`STRUCTURE_BIND`); inside the container the server always listens on 24565/udp.
