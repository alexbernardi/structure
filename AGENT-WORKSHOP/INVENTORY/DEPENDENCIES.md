# Dependencies and versions

Pins live in `INFRASTRUCTURE/builds/toolchain.json` (single source of truth; `structure.py check` verifies the
Dockerfile and `project.godot` agree). Changing a pin needs an ADR and the user's approval.

| Dependency | Version | Integrity / pin | Used for |
|---|---|---|---|
| Godot, Windows x86_64 | 4.7.2-stable (official build ed1daf0bf) | `Godot_v4.7.2-stable_win64.exe.zip` sha256 `731980f9...aca1e953` | editor, client, native server, tests |
| Godot, Linux x86_64 | 4.7.2-stable | `Godot_v4.7.2-stable_linux.x86_64.zip` sha256 `cadd3204...35329e4` | server and tools containers |
| Godot export templates | 4.7.2-stable (1.28 GB) | `.tpz` sha256 `f298490b...ea248011` | **not needed yet**; required only for standalone exports: `windows_release_x86_64.exe`, `windows_debug_x86_64.exe`, `linux_release.x86_64`, `linux_debug.x86_64` |
| Blender | 5.0.1 (glTF exporter 5.0.21) | exact version check in the pipeline | asset generation (Blender 4.2.0 also installed, not used) |
| Docker base image | `debian:trixie-slim` | digest `sha256:62bd423a...9a034ad` | container images |
| Container build packages | Debian trixie apt: ca-certificates, curl, unzip, libfontconfig1 (+ python3 in `tools`) | base digest pinned; apt versions not pinned (build stage only) | download/verify/import Godot |
| Python | >= 3.11 (tested 3.13.0) | `python.min_version` | tooling and tests (stdlib only - no pip packages) |
| Docker Desktop | tested: Engine 29.1.3, Compose 2.40.3 (WSL2) | not pinned | containers |
| Git / Git LFS | tested 2.45.2 / 3.5.1 | not pinned | versioning, large source assets |

Godot add-ons: none. Python third-party packages: none. Network services: none.

Downloads made by `setup` and image builds: the two Godot archives above, from
`https://github.com/godotengine/godot-builds/releases/download/4.7.2-stable/`.
