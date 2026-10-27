# ADR-0005: Containers and environments

Status: Accepted (2026-10-27)

## Context
Headless dedicated servers must run in Docker (Docker Desktop on Windows), with isolated configurable instances,
reproducible builds and no public exposure. The client runs natively.

## Decision
- `INFRASTRUCTURE/docker/server.Dockerfile`: `debian:trixie-slim` pinned by digest; the official Linux Godot archive
  (SHA-256 verified) runs the **imported project** headless (`--import` at build time; the build fails on any engine
  error). Runtime stage: non-root user, healthcheck on the server heartbeat, `entrypoint.sh` turns `docker stop` into
  a graceful save via the control file. A `tools` stage provides Linux Godot + Python for test runs.
- Images are built by `structure.py build` with the build manifest baked in and a unique tag
  `<version>-<sha7>[-dirty.<UTC>]`; existing tags are never overwritten (the test suite's `structure-server:test`
  is the only mutable tag and is never used by environments).
- **Environment** = `INFRASTRUCTURE/environments/<name>.env` + compose project `structure-<name>` + container
  `structure-<name>-server` + data dir `.runtime/envs/<name>/data` (bind mount). Ports must be unique (checked).
  UDP is published on `127.0.0.1` only. The same environment can be served natively (`server --native`), never both at once (lease).

## Consequences
+ Scenario B (two isolated servers) is a configuration, not code; verified by the docker suite.
- The editor binary makes the image larger (measured: 344 MB unpacked, ~109 MB compressed) than an export template
  would; exporting a dedicated-server build is a later optimisation once export templates are worth the 1.28 GB download.
- No registry, orchestration or production deployment (out of scope for this phase).
