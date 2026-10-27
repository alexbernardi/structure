"""Command-line dispatcher. Commands are thin wrappers over the modules in this package.
Reference: AGENT-WORKSHOP/DOCUMENTATION/COMMANDS.md."""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time

from . import buildinfo, paths, toolchain


# ---------------------------------------------------------------------------------------------- helpers

def _env(name: str):
    from . import envs

    return envs.load(name)


def _image_for(env, tag: str | None) -> str:
    from . import builds

    return builds.resolve_image(tag or env.image_tag or None)


def _launch_client(connect: str, name: str, extra: list[str] | None = None, wait: bool = False):
    from . import godot as godot_mod

    godot_mod.import_project(paths.SANDBOX_PROJECT)
    buildinfo.write_sandbox_manifest()
    cmd = [str(toolchain.ensure_godot()), "--path", str(paths.SANDBOX_PROJECT), "--", f"--connect={connect}", f"--name={name}", *(extra or [])]
    proc = subprocess.Popen(cmd, cwd=paths.REPO)
    if wait:
        proc.wait()
    return proc


def _native_server(env, log_name: str = "native-server.log"):
    from . import godot as godot_mod, procs

    godot_mod.import_project(paths.SANDBOX_PROJECT)
    buildinfo.write_sandbox_manifest()
    server = procs.ServerProcess(env.data_dir, env.port, world_id=env.world_id, seed=env.seed, env_id=env.name,
                                 log_path=env.data_root / log_name,
                                 extra=["--metrics-interval=10", f"--max-players={env.values.get('STRUCTURE_MAX_PLAYERS', 16)}"])
    server.start_and_wait_ready(60)
    return server


# ---------------------------------------------------------------------------------------------- commands

def cmd_setup(args) -> int:
    print("== STRUCTURE setup ==")
    exe = toolchain.ensure_godot()
    print(f"Godot: {exe}\nGodot reports: {toolchain.godot_reported_version()}")
    from . import doctor, godot as godot_mod

    for project in godot_mod.all_projects():
        print(f"Importing {project.relative_to(paths.REPO)} ...")
        godot_mod.import_project(project)
    buildinfo.write_sandbox_manifest()
    if subprocess.run(["git", "lfs", "version"], capture_output=True).returncode == 0:
        subprocess.run(["git", "lfs", "install", "--local"], cwd=paths.REPO, capture_output=True)
    print()
    return doctor.report()


def cmd_versions(args) -> int:
    from . import doctor

    return doctor.report(strict=args.strict)


def cmd_check(args) -> int:
    from . import checks

    results = checks.run()
    for level, name, detail in results:
        print(f"{level.upper():5} {name}: {detail}")
    errors = sum(1 for level, _, _ in results if level == "error")
    print(f"check: {errors} error(s), {len(results) - errors} warning(s)")
    return 1 if errors else 0


def cmd_play(args) -> int:
    env = _env(args.env)
    server = _native_server(env)
    print(f"Native server for '{env.name}' on 127.0.0.1:{env.port} (log: {server.log_path}). Close the game window to stop.")
    try:
        _launch_client(f"127.0.0.1:{env.port}", args.name, wait=True)
    finally:
        print("Stopping server (graceful save) ...")
        server.stop()
    return 0


def cmd_client(args) -> int:
    connect = args.connect or f"127.0.0.1:{_env(args.env).port}"
    _launch_client(connect, args.name, wait=True)
    return 0


def cmd_server(args) -> int:
    env = _env(args.env)
    if not args.native:
        return cmd_env_up(argparse.Namespace(name=args.env, image_tag=args.image_tag))
    server = _native_server(env)
    print(f"Native server '{env.name}' ready on 127.0.0.1:{env.port}; log {server.log_path}. Ctrl+C to stop gracefully.")
    try:
        while server.returncode() is None:
            time.sleep(0.5)
    except KeyboardInterrupt:
        print("Stopping (graceful save) ...")
    finally:
        server.stop()
    return 0


def cmd_build(args) -> int:
    from . import builds

    image = builds.build_server()
    print(f"server image: {image}")
    if args.tools:
        print(f"tools image: {builds.build_tools()}")
    return 0


def cmd_builds(args) -> int:
    from . import builds

    rows = builds.list_builds()
    if not rows:
        print("No server images yet. Run: python TOOLS/cli/structure.py build")
    for r in rows:
        m = r["manifest"]
        print(f"{r['image']:<62} {r['created'][:19]}  build={m.get('build_version')} commit={str(m.get('git_commit'))[:7]}"
              f"{'+dirty' if m.get('git_dirty') else ''} protocol=v{m.get('protocol_version')} schema=v{m.get('world_schema_version')}"
              f" godot={m.get('godot_version')}")
    return 0


def cmd_env_list(args) -> int:
    from . import envs

    for env in envs.all_envs():
        state = envs.container_state(env)
        status = envs.status_doc(env) if envs.lease_fresh(env) else None
        running = (f"container {state['status']}/{state['health']}" if state else "no container") + \
                  (f", serving {status['players']} player(s), progress {status['site_progress']}" if status else "")
        print(f"{env.name:<8} udp 127.0.0.1:{env.port:<6} world={env.world_id:<8} {running}")
    return 0


def cmd_env_up(args) -> int:
    from . import envs

    env = _env(args.name)
    image = _image_for(env, args.image_tag)
    envs.up(env, image)
    ready = envs.wait_for_log_event(env, "server.ready", 90)
    print(f"{env.name}: {image} ready on udp 127.0.0.1:{env.port} world={ready['world']} progress={ready['site_progress']}")
    print(f"  data: {env.data_dir}\n  logs: python TOOLS/cli/structure.py env logs {env.name}")
    return 0


def cmd_env_down(args) -> int:
    from . import envs

    envs.down(_env(args.name))
    print(f"{args.name}: stopped (world data kept in .runtime/envs/{args.name}/data)")
    return 0


def cmd_env_status(args) -> int:
    from . import envs

    env = _env(args.name)
    print(json.dumps({"env": env.name, "port": env.port, "world": env.world_id, "data_dir": str(env.data_dir),
                      "container": envs.container_state(env), "lease_fresh": envs.lease_fresh(env),
                      "status": envs.status_doc(env)}, indent=2))
    stats = subprocess.run(["docker", "stats", "--no-stream", "--format", "{{.Name}} cpu={{.CPUPerc}} mem={{.MemUsage}} net={{.NetIO}}",
                            env.container], capture_output=True, text=True)
    if stats.returncode == 0:
        print(stats.stdout.strip())
    return 0


def cmd_env_logs(args) -> int:
    from . import envs

    print(envs.container_logs(_env(args.name), args.tail))
    return 0


def cmd_env_purge(args) -> int:
    """Destructive: deletes an environment's world data (after a final snapshot unless --no-snapshot)."""
    import shutil

    from . import envs, snapshots

    env = _env(args.name)
    if envs.is_running(env):
        print(f"{env.name} is running; run `env down {env.name}` first")
        return 1
    if not args.yes:
        print(f"This deletes {env.data_dir}. Re-run with --yes to confirm (a final snapshot is taken first).")
        return 1
    if env.world_file.is_file() and not args.no_snapshot:
        print(f"final snapshot: {snapshots.create(env, 'pre-purge')['id']}")
    shutil.rmtree(env.data_dir, ignore_errors=True)
    print(f"{env.name}: world data deleted")
    return 0


def _scenario(name: str) -> dict:
    path = paths.SANDBOX_SCENARIOS / f"scenario-{name}.json"
    if not path.is_file():
        raise SystemExit(f"unknown scenario '{name}' ({path} missing)")
    return json.loads(path.read_text(encoding="utf-8"))


def cmd_scenario(args) -> int:
    from . import envs, procs

    scenario = _scenario(args.name)
    print(f"Scenario {args.name.upper()}: {scenario['description']}")
    if args.down:
        for name in scenario["environments"]:
            envs.down(_env(name))
            print(f"  {name}: stopped")
        return 0
    started = []
    for name in scenario["environments"]:
        env = _env(name)
        if args.native:
            started.append(_native_server(env, f"scenario-{args.name}.log"))
            print(f"  {name}: native server on udp 127.0.0.1:{env.port}")
        else:
            cmd_env_up(argparse.Namespace(name=name, image_tag=args.image_tag))
    first = _env(scenario["environments"][0])
    try:
        if scenario.get("clients"):
            if args.bots:
                run_dir = paths.TEST_RUNS / f"scenario-{args.name}-{buildinfo.utc_stamp()}"
                bots = [procs.start_bot(run_dir, first.port, f"bot{i}", "gather:1", wait_players=scenario["clients"])
                        for i in range(scenario["clients"])]
                for proc, report in bots:
                    code, data = procs.finish_bot(proc, report)
                    print(f"  {data.get('name')}: exit {code}, saw {data.get('players_seen')}, site progress {data.get('final_progress')}")
            else:
                clients = [_launch_client(f"127.0.0.1:{first.port}", f"player{i + 1}") for i in range(scenario["clients"])]
                print(f"  {len(clients)} windowed clients connected to 127.0.0.1:{first.port}; close them to finish.")
                for c in clients:
                    c.wait()
        else:
            print("  Environments are running independently. Inspect: `structure.py env list`; stop: "
                  f"`structure.py scenario {args.name} --down`.")
    finally:
        for server in started:
            server.stop()
    return 0


def cmd_snapshot(args) -> int:
    from . import compat, snapshots

    if args.action == "list":
        rows = snapshots.list_snapshots(args.env)
        for m in rows:
            print(f"{m['env']:<8} {m['id']:<36} world={m['world_id']} schema=v{m['schema_version']} rev={m['revision']}"
                  f" progress={m['site_progress']} build={(m.get('server_build') or {}).get('build')}")
        if not rows:
            print("no snapshots")
        return 0
    env = _env(args.env)
    if args.action == "create":
        meta = snapshots.create(env, args.label)
        print(f"created {env.name}/{meta['id']} (schema v{meta['schema_version']}, progress {meta['site_progress']}, sha256 {meta['sha256'][:12]})")
        return 0
    build = compat.load_manifest(args.build) if args.build else _restore_target(env)
    if args.dry_run:
        plan = snapshots.plan_restore(env, args.snapshot, build, args.allow_other_world)
        print(json.dumps({k: v for k, v in plan.items() if k != "folder"}, indent=2, default=str))
        return 0 if not plan["problems"] else 1
    result = snapshots.restore(env, args.snapshot, build, yes=args.yes, allow_other_world=args.allow_other_world)
    print(f"restored {result['restored']} into {env.name} ({result['compatibility']}); previous world saved as {result['backup']}")
    return 0


def _restore_target(env) -> dict:
    """The build that will load the restored world: the env's pinned/newest image, else this source tree."""
    from . import builds

    try:
        image = builds.resolve_image(env.image_tag or None)
        return builds.image_manifest(image) or buildinfo.manifest()
    except Exception:
        return buildinfo.manifest()


def cmd_compat(args) -> int:
    from . import compat, snapshots

    server = compat.load_manifest(args.server)
    exit_code = 0
    if args.client:
        ok, reason = compat.protocol_compatible(compat.load_manifest(args.client), server)
        print(f"client {args.client} -> server {args.server}: {reason}")
        exit_code |= 0 if ok else 1
    if args.snapshot:
        env_name, snap_id = args.snapshot.split("/", 1)
        _, meta = snapshots.find(env_name, snap_id)
        ok, reason = compat.world_loadable(int(meta["schema_version"]), server)
        print(f"snapshot {args.snapshot} -> server {args.server}: {reason}")
        exit_code |= 0 if ok else 1
    return exit_code


def cmd_test(args) -> int:
    from . import testing

    return testing.run(args.suites, args.skip or [], args)


def cmd_bench(args) -> int:
    from . import bench

    if args.target == "movement":
        result = bench.movement(args.record)
    elif args.target == "server":
        result = bench.server(args.bots, args.duration, args.seed, args.docker, record=args.record)
    else:
        result = bench.client(args.duration, record=args.record)
    print(json.dumps(result, indent=2, default=str))
    return 0


def cmd_room(args) -> int:
    from . import rooms

    if args.action == "list":
        for name in rooms.list_rooms():
            room = rooms.load_room(name)
            print(f"{name:<12} {room['version']:<8} {room['status']:<12} {room['summary']}")
        return 0
    if args.action == "new":
        print(f"created {rooms.new_room(args.name)} - fill in README/SPEC/CONTRACT, then `room test {args.name}`")
        return 0
    if args.action == "test":
        return rooms.test_room(args.name, experiments=args.experiments)[0]
    if args.action == "bench":
        result = rooms.bench_room(args.name)
        for p in result["problems"]:
            print("  PROBLEM", p)
        return 0 if result["ok"] else 1
    if args.action == "status":
        print(json.dumps(rooms.integration_status(args.name), indent=2))
        return 0
    from . import testing

    def gates() -> bool:
        return testing.run(["import", "unit", "multiplayer"], [], args) == 0

    result = rooms.promote(args.name, gates, dry_run=args.dry_run)
    print("PROMOTED" if result["promoted"] else ("dry run: all pre-promotion checks passed" if result["ok"] is None else "NOT promoted"))
    return 0 if result["ok"] in (True, None) else 1


def cmd_pipeline(args) -> int:
    from . import assets

    if args.action == "check":
        problems = assets.check()
        for p in problems:
            print("ERROR", p)
        print(f"{len(assets.asset_ids())} asset(s) checked, {len(problems)} problem(s)")
        return 1 if problems else 0
    if args.action == "deploy":
        for target in assets.deploy(args.asset):
            print(f"deployed {target.relative_to(paths.REPO)}")
        return 0
    result = assets.run(args.asset, args.allow_version_mismatch)
    info = result["info"]
    print(f"{args.asset}: Blender {result['blender']['blender_version']} -> {info['bytes']} bytes, {info['triangles']} triangles, "
          f"size {[round(v, 4) for v in info['size']]} m, sha256 {result['meta']['runtime']['sha256'][:12]}; deployed to "
          f"{result['meta']['consumers']}")
    return 0


# ---------------------------------------------------------------------------------------------- parser

def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="structure", description="STRUCTURE developer CLI (see AGENT-WORKSHOP/DOCUMENTATION/COMMANDS.md)")
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("setup", help="download pinned Godot, import projects, report versions").set_defaults(func=cmd_setup)
    p = sub.add_parser("versions", help="build identity and pinned vs installed tool versions")
    p.add_argument("--strict", action="store_true")
    p.set_defaults(func=cmd_versions)
    sub.add_parser("check", help="static repository checks").set_defaults(func=cmd_check)

    p = sub.add_parser("play", help="native dedicated server + windowed client (quickest way in)")
    p.add_argument("--env", default="dev")
    p.add_argument("--name", default="player")
    p.set_defaults(func=cmd_play)
    p = sub.add_parser("client", help="launch the windowed client")
    p.add_argument("--connect", help="host:port (default: the env's local port)")
    p.add_argument("--env", default="dev")
    p.add_argument("--name", default="player")
    p.set_defaults(func=cmd_client)
    p = sub.add_parser("server", help="start a dedicated server (Docker by default)")
    p.add_argument("--env", default="dev")
    p.add_argument("--native", action="store_true", help="run headless Godot on this machine instead of Docker")
    p.add_argument("--image-tag")
    p.set_defaults(func=cmd_server)

    p = sub.add_parser("build", help="build the server image (unique immutable tag)")
    p.add_argument("--tools", action="store_true", help="also build the Linux tools image")
    p.set_defaults(func=cmd_build)
    sub.add_parser("builds", help="list local server builds").set_defaults(func=cmd_builds)

    env = sub.add_parser("env", help="server environments (Docker)").add_subparsers(dest="action", required=True)
    env.add_parser("list").set_defaults(func=cmd_env_list)
    for action, func in (("up", cmd_env_up), ("down", cmd_env_down), ("status", cmd_env_status), ("logs", cmd_env_logs), ("purge", cmd_env_purge)):
        q = env.add_parser(action)
        q.add_argument("name")
        if action == "up":
            q.add_argument("--image-tag", help="named server build (default: env file pin, else newest)")
        if action == "logs":
            q.add_argument("--tail", type=int, default=200)
        if action == "purge":
            q.add_argument("--yes", action="store_true")
            q.add_argument("--no-snapshot", action="store_true")
        q.set_defaults(func=func)

    p = sub.add_parser("scenario", help="A = one server + two clients, B = two isolated servers")
    p.add_argument("name", choices=["a", "b"])
    p.add_argument("--native", action="store_true")
    p.add_argument("--bots", action="store_true", help="headless bot clients instead of windows")
    p.add_argument("--down", action="store_true", help="stop the scenario's Docker environments")
    p.add_argument("--image-tag")
    p.set_defaults(func=cmd_scenario)

    p = sub.add_parser("snapshot", help="world snapshots")
    p.add_argument("action", choices=["create", "list", "restore"])
    p.add_argument("env", nargs="?")
    p.add_argument("snapshot", nargs="?")
    p.add_argument("--label", default="manual")
    p.add_argument("--build", help="restore target build: image tag, manifest path or 'current' (default: env image / newest build)")
    p.add_argument("--yes", action="store_true", help="confirm replacing the current world")
    p.add_argument("--dry-run", action="store_true")
    p.add_argument("--allow-other-world", action="store_true")
    p.set_defaults(func=cmd_snapshot)

    p = sub.add_parser("compat", help="client/server protocol and world/server schema compatibility")
    p.add_argument("--server", required=True, help="image tag, manifest path or 'current'")
    p.add_argument("--client", help="image tag, manifest path or 'current'")
    p.add_argument("--snapshot", help="<env>/<snapshot-id>")
    p.set_defaults(func=cmd_compat)

    p = sub.add_parser("test", help="automated suites")
    p.add_argument("suites", nargs="*", help="check tools import unit rooms pipeline multiplayer docker (default: all)")
    p.add_argument("--skip", nargs="*")
    p.add_argument("--with-blender", action="store_true", help="pipeline suite also regenerates assets with Blender")
    p.set_defaults(func=cmd_test)

    p = sub.add_parser("bench", help="benchmarks (fixed seeds)")
    p.add_argument("target", choices=["movement", "server", "client"])
    p.add_argument("--bots", type=int, default=8)
    p.add_argument("--duration", type=float, default=30.0)
    p.add_argument("--seed", type=int, default=4242)
    p.add_argument("--docker", action="store_true", help="server benchmark inside the container (CPU/RSS via /proc)")
    p.add_argument("--record", action="store_true", help="store as the committed baseline")
    p.set_defaults(func=cmd_bench)

    p = sub.add_parser("room", help="system rooms and the integration gateway")
    p.add_argument("action", choices=["list", "new", "test", "bench", "status", "promote"])
    p.add_argument("name", nargs="?")
    p.add_argument("--experiments", action="store_true")
    p.add_argument("--dry-run", action="store_true")
    p.set_defaults(func=cmd_room)

    p = sub.add_parser("pipeline", help="asset pipeline (Blender -> GLB -> Godot)")
    p.add_argument("action", choices=["run", "check", "deploy"])
    p.add_argument("asset", nargs="?", default="resource_stone")
    p.add_argument("--allow-version-mismatch", action="store_true")
    p.set_defaults(func=cmd_pipeline)
    return parser


def main(argv: list[str]) -> int:
    args = build_parser().parse_args(argv)
    if args.command == "room" and args.action != "list" and not args.name:
        print("room: a room name is required")
        return 2
    if args.command == "snapshot" and args.action in ("create", "restore") and not args.env:
        print("snapshot: an environment name is required")
        return 2
    if args.command == "snapshot" and args.action == "restore" and not args.snapshot:
        print("snapshot restore: a snapshot id is required (see `snapshot list`)")
        return 2
    try:
        return int(args.func(args) or 0)
    except KeyboardInterrupt:
        return 130
    except Exception as exc:  # known tool errors print cleanly; unexpected ones keep the traceback
        known = {"ToolchainError", "EnvError", "BuildError", "SnapshotError", "RoomError", "AssetError"}
        if type(exc).__name__ in known:
            print(f"ERROR: {exc}", file=sys.stderr)
            return 2
        raise
