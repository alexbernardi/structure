# INFRASTRUCTURE

| Folder | Contents |
|---|---|
| `builds/` | `toolchain.json` (all external pins) - see `builds/README.md` |
| `docker/` | `server.Dockerfile` (runtime + tools targets), `entrypoint.sh`, `healthcheck.sh`, compose files - see `docker/README.md` |
| `environments/` | one `<env>.env` per server instance (`dev`, `iso-a`, `iso-b`; template `example.env`) |
| `snapshots/` | local world snapshots (git-ignored) - see `snapshots/README.md` |

Mutable data is never stored here except snapshots: environment world data lives in `.runtime/envs/<env>/data/`.
Rules: `AGENT-WORKSHOP/PROTOCOLS/VERSIONING.md`, `SECURITY.md`; decisions: ADR-0004, ADR-0005.
