"""Server environments: INFRASTRUCTURE/environments/<name>.env + an isolated data dir + one compose project.

Isolation rules: every environment has its own compose project, container name, host UDP port and data
directory (.runtime/envs/<name>/data). Ports must be unique across environment files.
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import time
from dataclasses import dataclass
from pathlib import Path

from . import paths

REQUIRED = ("STRUCTURE_ENV_ID", "STRUCTURE_PORT", "STRUCTURE_WORLD_ID", "STRUCTURE_WORLD_SEED")
ID_RE = re.compile(r"^[a-z0-9][a-z0-9_-]{0,31}$")
COMPOSE_FILE = paths.DOCKER / "compose.server.yml"
LEASE_MAX_AGE_S = 5.0


class EnvError(RuntimeError):
    pass


@dataclass
class Environment:
    name: str
    values: dict
    data_root: Path

    @property
    def port(self) -> int:
        return int(self.values["STRUCTURE_PORT"])

    @property
    def world_id(self) -> str:
        return self.values["STRUCTURE_WORLD_ID"]

    @property
    def seed(self) -> int:
        return int(self.values["STRUCTURE_WORLD_SEED"])

    @property
    def bind(self) -> str:
        return self.values.get("STRUCTURE_BIND", "127.0.0.1")

    @property
    def image_tag(self) -> str:
        return self.values.get("STRUCTURE_IMAGE_TAG", "")

    @property
    def data_dir(self) -> Path:
        return self.data_root / "data"

    @property
    def world_file(self) -> Path:
        return self.data_dir / "world" / "world.json"

    @property
    def status_file(self) -> Path:
        return self.data_dir / "runtime" / "status.json"

    @property
    def compose_project(self) -> str:
        return f"structure-{self.name}"

    @property
    def container(self) -> str:
        return f"structure-{self.name}-server"


def parse_env_file(path: Path) -> dict:
    values = {}
    for number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            raise EnvError(f"{path.name}:{number}: expected KEY=VALUE")
        key, value = line.split("=", 1)
        values[key.strip()] = value.strip().strip('"').strip("'")
    return values


def validate(env: Environment) -> list[str]:
    errors = [f"{env.name}: missing {key}" for key in REQUIRED if not env.values.get(key)]
    if errors:
        return errors
    if env.values["STRUCTURE_ENV_ID"] != env.name:
        errors.append(f"{env.name}: STRUCTURE_ENV_ID must equal the file name ({env.name})")
    for key in ("STRUCTURE_ENV_ID", "STRUCTURE_WORLD_ID"):
        if not ID_RE.match(env.values[key]):
            errors.append(f"{env.name}: {key} must match {ID_RE.pattern}")
    if not env.values["STRUCTURE_PORT"].isdigit() or not 1024 <= env.port <= 65535:
        errors.append(f"{env.name}: STRUCTURE_PORT must be 1024-65535")
    seed = env.values["STRUCTURE_WORLD_SEED"]
    if not seed.isdigit() or int(seed) > 2147483646:
        errors.append(f"{env.name}: STRUCTURE_WORLD_SEED must be 0-2147483646")
    if env.bind not in ("127.0.0.1", "localhost") and env.values.get("STRUCTURE_ALLOW_PUBLIC_BIND") != "yes":
        errors.append(f"{env.name}: STRUCTURE_BIND={env.bind} exposes the server beyond localhost; "
                      "also set STRUCTURE_ALLOW_PUBLIC_BIND=yes if that is really intended")
    return errors


def validate_set(envs: list[Environment]) -> list[str]:
    errors = []
    seen_ports: dict[int, str] = {}
    for env in envs:
        errors += validate(env)
        if env.values.get("STRUCTURE_PORT", "").isdigit():
            if env.port in seen_ports:
                errors.append(f"{env.name}: port {env.port} already used by {seen_ports[env.port]}")
            seen_ports[env.port] = env.name
    return errors


def load(name: str) -> Environment:
    if not ID_RE.match(name):
        raise EnvError(f"invalid environment name {name!r}")
    path = paths.ENVIRONMENTS / f"{name}.env"
    if not path.is_file():
        known = ", ".join(e.name for e in all_envs()) or "none"
        raise EnvError(f"unknown environment {name!r} (known: {known}); create {path.relative_to(paths.REPO)}")
    env = Environment(name, parse_env_file(path), paths.ENV_DATA / name)
    local = paths.ENVIRONMENTS / f"{name}.local.env"  # git-ignored personal overrides
    if local.is_file():
        env.values.update(parse_env_file(local))
    problems = validate(env)
    if problems:
        raise EnvError("; ".join(problems))
    return env


def all_envs() -> list[Environment]:
    return [Environment(p.stem, parse_env_file(p), paths.ENV_DATA / p.stem)
            for p in sorted(paths.ENVIRONMENTS.glob("*.env")) if p.stem != "example" and not p.stem.endswith(".local")]


def ephemeral(name: str, port: int, world_id: str, seed: int, data_root: Path) -> Environment:
    """Test environments: same shape as dev environments, but with their own data root."""
    values = {"STRUCTURE_ENV_ID": name, "STRUCTURE_PORT": str(port), "STRUCTURE_WORLD_ID": world_id,
              "STRUCTURE_WORLD_SEED": str(seed), "STRUCTURE_METRICS_INTERVAL": "2"}
    return Environment(name, values, data_root)


# ---------------------------------------------------------------------------------------------- docker

def _compose_env(env: Environment, image: str) -> dict:
    out = dict(os.environ)
    out.update(env.values)
    out["STRUCTURE_DATA_DIR"] = env.data_dir.resolve().as_posix()
    out["STRUCTURE_IMAGE"] = image
    return out


def compose(env: Environment, image: str, *args: str, capture: bool = False) -> subprocess.CompletedProcess:
    cmd = ["docker", "compose", "-p", env.compose_project, "-f", str(COMPOSE_FILE), *args]
    return subprocess.run(cmd, env=_compose_env(env, image), capture_output=capture, text=True, timeout=300)


def up(env: Environment, image: str) -> None:
    if lease_fresh(env) and not container_state(env):
        raise EnvError(f"{env.name}: a native server is using {env.data_dir}; stop it first")
    env.data_dir.mkdir(parents=True, exist_ok=True)
    proc = compose(env, image, "up", "-d", "--force-recreate", capture=True)
    if proc.returncode != 0:
        raise EnvError(f"docker compose up failed for {env.name}:\n{proc.stdout}{proc.stderr}")


def down(env: Environment) -> None:
    """Stops and removes the container and network. Never touches the world data."""
    proc = compose(env, "none", "down", "--timeout", "20", capture=True)
    if proc.returncode != 0:
        raise EnvError(f"docker compose down failed for {env.name}:\n{proc.stdout}{proc.stderr}")


def container_state(env: Environment) -> dict | None:
    proc = subprocess.run(["docker", "inspect", env.container], capture_output=True, text=True, timeout=30)
    if proc.returncode != 0:
        return None
    info = json.loads(proc.stdout)[0]
    state = info["State"]
    return {"status": state["Status"], "running": state["Running"], "health": (state.get("Health") or {}).get("Status"),
            "image": info["Config"]["Image"], "started_at": state.get("StartedAt"), "exit_code": state.get("ExitCode")}


def container_logs(env: Environment, tail: int | None = None) -> str:
    cmd = ["docker", "logs", env.container] + (["--tail", str(tail)] if tail else [])
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
    return proc.stdout + proc.stderr


def log_events(env: Environment, evt: str) -> list[dict]:
    out = []
    for line in container_logs(env).splitlines():
        if line.startswith("{"):
            try:
                record = json.loads(line)
            except json.JSONDecodeError:
                continue
            if record.get("evt") == evt:
                out.append(record)
    return out


def wait_for_log_event(env: Environment, evt: str, timeout: float = 60.0, after_count: int = 0) -> dict:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        events = log_events(env, evt)
        if len(events) > after_count:
            return events[-1]
        state = container_state(env)
        if state and not state["running"] and state["status"] == "exited":
            break
        time.sleep(0.5)
    raise EnvError(f"{env.name}: no '{evt}' log event within {timeout}s\n{container_logs(env, 30)}")


def status_doc(env: Environment) -> dict | None:
    try:
        return json.loads(env.status_file.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None


def lease_fresh(env: Environment, max_age: float = LEASE_MAX_AGE_S) -> bool:
    """True when some server (native or container) is heart-beating into this data dir."""
    try:
        return time.time() - env.status_file.stat().st_mtime < max_age
    except OSError:
        return False


def is_running(env: Environment) -> bool:
    state = container_state(env)
    return bool(state and state["running"]) or lease_fresh(env)
