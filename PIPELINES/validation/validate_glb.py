"""GLB validation against an asset spec (stdlib only). Module API: validate(path, spec) -> (errors, info).

CLI: python PIPELINES/validation/validate_glb.py <file.glb> <spec.json>
"""
from __future__ import annotations

import json
import math
import re
import struct
import sys
from pathlib import Path

NAME_RE = re.compile(r"^[a-z][a-z0-9_]*$")
IDENTITY = {"translation": [0, 0, 0], "rotation": [0, 0, 0, 1], "scale": [1, 1, 1]}


def read_glb(path: Path) -> tuple[dict, bytes]:
    data = Path(path).read_bytes()
    if len(data) < 20:
        raise ValueError("file too small to be a GLB")
    magic, version, length = struct.unpack_from("<4sII", data, 0)
    if magic != b"glTF":
        raise ValueError("not a GLB (bad magic)")
    if version != 2:
        raise ValueError(f"unsupported GLB container version {version}")
    if length != len(data):
        raise ValueError(f"header length {length} != file size {len(data)}")
    json_len, json_type = struct.unpack_from("<I4s", data, 12)
    if json_type != b"JSON":
        raise ValueError("first chunk is not JSON")
    doc = json.loads(data[20:20 + json_len])
    binary = b""
    offset = 20 + json_len
    if offset + 8 <= len(data):
        bin_len, bin_type = struct.unpack_from("<I4s", data, offset)
        if bin_type == b"BIN\x00":
            binary = data[offset + 8:offset + 8 + bin_len]
    return doc, binary


def inspect(doc: dict) -> dict:
    accessors = doc.get("accessors", [])
    lo, hi = [math.inf] * 3, [-math.inf] * 3
    triangles, non_triangle = 0, 0
    for mesh in doc.get("meshes", []):
        for prim in mesh.get("primitives", []):
            pos = accessors[prim["attributes"]["POSITION"]]
            for i in range(3):
                lo[i] = min(lo[i], pos["min"][i])
                hi[i] = max(hi[i], pos["max"][i])
            if prim.get("mode", 4) != 4:
                non_triangle += 1
            count = accessors[prim["indices"]]["count"] if "indices" in prim else pos["count"]
            triangles += count // 3
    size = [hi[i] - lo[i] for i in range(3)] if lo[0] != math.inf else [0.0, 0.0, 0.0]
    return {
        "generator": doc.get("asset", {}).get("generator"),
        "gltf_version": doc.get("asset", {}).get("version"),
        "meshes": [m.get("name") for m in doc.get("meshes", [])],
        "nodes": [n.get("name") for n in doc.get("nodes", [])],
        "materials": len(doc.get("materials", [])),
        "images": len(doc.get("images", [])),
        "triangles": triangles,
        "non_triangle_primitives": non_triangle,
        "bounds_min": lo,
        "bounds_max": hi,
        "size": size,
    }


def validate(path: Path, spec: dict) -> tuple[list[str], dict]:
    path = Path(path)
    try:
        doc, _ = read_glb(path)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        return [f"{path.name}: {exc}"], {}
    info = inspect(doc)
    info["bytes"] = path.stat().st_size
    errors: list[str] = []
    asset_id = spec["asset_id"]
    budget = spec.get("budget", {})
    tol = float(spec.get("tolerance_m", 0.001))
    if not NAME_RE.match(asset_id):
        errors.append(f"asset id '{asset_id}' must be lower_snake_case")
    if info["gltf_version"] != "2.0":
        errors.append(f"glTF version must be 2.0, got {info['gltf_version']}")
    if info["meshes"] != [asset_id]:
        errors.append(f"expected exactly one mesh named '{asset_id}', found {info['meshes']}")
    if asset_id not in info["nodes"]:
        errors.append(f"no node named '{asset_id}' (found {info['nodes']})")
    for node in doc.get("nodes", []):
        for key, identity in IDENTITY.items():
            if key in node and any(abs(a - b) > 1e-6 for a, b in zip(node[key], identity)):
                errors.append(f"node '{node.get('name')}' has a non-identity {key}; apply transforms before export")
    for axis, got, want in zip("xyz", info["size"], spec["params"]["size"]):
        if abs(got - want) > tol:
            errors.append(f"size.{axis} is {got:.4f} m, spec says {want} m (tolerance {tol} m)")
    if spec.get("origin") == "base_center":
        center_x = (info["bounds_min"][0] + info["bounds_max"][0]) / 2
        center_z = (info["bounds_min"][2] + info["bounds_max"][2]) / 2
        if abs(info["bounds_min"][1]) > tol or abs(center_x) > tol or abs(center_z) > tol:
            errors.append(f"origin must be the base centre (min.y={info['bounds_min'][1]:.4f}, centre x/z={center_x:.4f}/{center_z:.4f})")
    if info["non_triangle_primitives"]:
        errors.append("all primitives must be triangle lists")
    if info["triangles"] > budget.get("max_triangles", math.inf):
        errors.append(f"{info['triangles']} triangles exceed the budget of {budget['max_triangles']}")
    if info["materials"] > budget.get("max_materials", math.inf):
        errors.append(f"{info['materials']} materials exceed the budget of {budget['max_materials']}")
    if info["images"] > budget.get("max_images", 0):
        errors.append(f"{info['images']} embedded images exceed the budget of {budget.get('max_images', 0)}")
    if info["bytes"] > budget.get("max_bytes", math.inf):
        errors.append(f"{info['bytes']} bytes exceed the budget of {budget['max_bytes']}")
    return errors, info


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    problems, details = validate(Path(sys.argv[1]), json.loads(Path(sys.argv[2]).read_text(encoding="utf-8")))
    print(json.dumps(details, indent=2))
    for p in problems:
        print("ERROR:", p)
    sys.exit(1 if problems else 0)
