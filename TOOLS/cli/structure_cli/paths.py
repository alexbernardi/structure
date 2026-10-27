"""Well-known repository locations. All tooling resolves paths through this module."""
from __future__ import annotations

from pathlib import Path

REPO = Path(__file__).resolve().parents[3]

WORKSHOP = REPO / "AGENT-WORKSHOP"
SANDBOX_PROJECT = REPO / "SANDBOX" / "godot"
SANDBOX_CONFIG = REPO / "SANDBOX" / "config"
SANDBOX_SCENARIOS = REPO / "SANDBOX" / "scenarios"
SYSTEM_ROOMS = REPO / "SYSTEM-ROOMS"
COMMON_ASSETS = REPO / "COMMON-ASSETS"
ASSET_MANIFEST = COMMON_ASSETS / "manifests" / "assets.json"
PIPELINES = REPO / "PIPELINES"
INFRA = REPO / "INFRASTRUCTURE"
DOCKER = INFRA / "docker"
ENVIRONMENTS = INFRA / "environments"
BUILDS = INFRA / "builds"
TOOLCHAIN_FILE = BUILDS / "toolchain.json"
SNAPSHOTS = INFRA / "snapshots"
TESTING = REPO / "TESTING"
GD_TEST_RUNNER = TESTING / "harness" / "run_gd_tests.gd"

# Git-ignored local state.
TOOLS_DIR = REPO / ".tools"
RUNTIME = REPO / ".runtime"
ENV_DATA = RUNTIME / "envs"
TEST_RUNS = RUNTIME / "test-runs"
BUILD_REGISTRY = RUNTIME / "builds"
PIPELINE_OUT = RUNTIME / "pipeline"
