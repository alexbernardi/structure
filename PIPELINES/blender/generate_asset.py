"""Blender entry point: asset spec -> generator -> standard GLB export -> build report.

    blender --background --factory-startup --python-exit-code 1 \
            --python PIPELINES/blender/generate_asset.py -- \
            --spec COMMON-ASSETS/models/<id>/source/spec.json --out <file.glb> --report <report.json>

Normally invoked by `python TOOLS/cli/structure.py pipeline run <id>`. Supported: Blender 4.2+;
the pinned version is in INFRASTRUCTURE/builds/toolchain.json.
"""
import argparse
import json
import os
import sys
import traceback

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "export"))

from export_gltf import SETTINGS, export_glb, exporter_version  # noqa: E402
from generators import GENERATORS  # noqa: E402


def main() -> None:
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    parser = argparse.ArgumentParser(prog="generate_asset.py")
    parser.add_argument("--spec", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--report", required=True)
    args = parser.parse_args(argv)

    with open(args.spec, encoding="utf-8") as handle:
        spec = json.load(handle)
    generator = GENERATORS.get(spec["generator"])
    if generator is None:
        raise SystemExit(f"unknown generator {spec['generator']!r}; known: {sorted(GENERATORS)}")

    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0

    obj = generator.build(spec["asset_id"], spec["params"])
    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    export_glb(obj, args.out)

    mesh = obj.data
    mesh.calc_loop_triangles()
    report = {
        "asset_id": spec["asset_id"],
        "generator": spec["generator"],
        "params": spec["params"],
        "blender_version": bpy.app.version_string,
        "gltf_exporter": exporter_version(),
        "triangles": len(mesh.loop_triangles),
        "blender_dimensions_xyz": [round(v, 6) for v in obj.dimensions],
        "export_settings": SETTINGS,
    }
    with open(args.report, "w", encoding="utf-8") as handle:
        json.dump(report, handle, indent=2)
    print("STRUCTURE_PIPELINE_OK", args.out)


try:
    main()
except SystemExit:
    raise
except Exception:  # surface a clear failure to the calling tool
    traceback.print_exc()
    sys.exit(1)
