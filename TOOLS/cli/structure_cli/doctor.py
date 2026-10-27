"""`structure.py versions`: build identity, pinned vs installed tools, environments, builds, systems."""
from __future__ import annotations

from . import buildinfo, envs, paths, rooms, toolchain


def report(strict: bool = False) -> int:
    problems = []
    v = buildinfo.project_versions()
    git = buildinfo.git_info()
    print("STRUCTURE build identity")
    print(f"  build version     {v['build_version']}   (SANDBOX/godot/project.godot)")
    print(f"  git               {git['commit'][:12]}{' (dirty)' if git['dirty'] else ''} on {git['branch']}")
    print(f"  network protocol  v{v['protocol_version']}")
    print(f"  world schema      v{v['world_schema_version']} (loads >= v{v['min_world_schema_version']})")
    manifest = paths.ASSET_MANIFEST
    print(f"  asset manifest    {(buildinfo.file_sha256(manifest) or 'missing')[:12]}  ({manifest.relative_to(paths.REPO)})")

    tc = toolchain.load()
    print("\nToolchain (pinned -> found)")
    godot_found = toolchain.godot_reported_version()
    godot_ok = bool(godot_found) and godot_found.startswith(tc["godot"]["version"].replace("-", "."))
    print(f"  godot    {tc['godot']['version']:<14} -> {godot_found or 'not installed (run setup)'} {'OK' if godot_ok else 'MISMATCH'}")
    if not godot_ok:
        problems.append("godot")
    blender = toolchain.find_blender()
    blender_found = toolchain.blender_reported_version(blender) if blender else None
    blender_ok = blender_found == tc["blender"]["version"]
    print(f"  blender  {tc['blender']['version']:<14} -> {blender_found or 'not found'} {'OK' if blender_ok else 'MISMATCH (only needed for the asset pipeline)'}")
    docker = toolchain.tool_version(["docker", "version", "--format", "{{.Server.Version}}"])
    print(f"  docker   {'any':<14} -> {('daemon ' + docker) if docker else 'daemon not reachable'}")
    print(f"  python   {'>=' + tc['python']['min_version']:<14} -> {toolchain.tool_version(['python', '--version'])}")
    print(f"  git-lfs  {'any':<14} -> {toolchain.tool_version(['git', 'lfs', 'version']) or 'not installed'}")
    print(f"  base img {tc['docker']['base_image']}")

    print("\nEnvironments (INFRASTRUCTURE/environments)")
    for env in envs.all_envs():
        print(f"  {env.name:<8} udp {env.bind}:{env.values.get('STRUCTURE_PORT')}  world={env.values.get('STRUCTURE_WORLD_ID')}"
              f" seed={env.values.get('STRUCTURE_WORLD_SEED')}  data={env.data_dir.relative_to(paths.REPO)}")

    if docker:
        from . import builds

        rows = builds.list_builds()
        print(f"\nServer images: {len(rows)} local build(s)" + (f", newest {rows[0]['image']}" if rows else ""))

    print("\nIntegrated systems")
    for name in rooms.list_rooms():
        st = rooms.integration_status(name)
        state = ("not integrated" if not st["integrated"] else "drift!" if st["drift"]
                 else "pending promotion" if st["pending"] else "in sync")
        print(f"  {name:<10} room {st['room_version']}  sandbox {st['integrated_version'] or 'not integrated'}  ({state})")
    if strict and problems:
        print(f"\nMismatched pins: {', '.join(problems)}")
        return 1
    return 0
