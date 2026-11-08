"""Copies selected animations from a large GLB into a small GLB without altering any keyframe bytes.

Keeps every node, skin, mesh and material; drops unselected animations and the binary data only they referenced.
Verifies that each kept animation's sampler data is byte-identical to the source before writing.

    python tools/extract_glb_clips.py <source.glb> <output.glb> SafetyVault [MoreClips ...]
"""
import hashlib
import json
import struct
import sys
from pathlib import Path

GLB_MAGIC = 0x46546C67
CHUNK_JSON = 0x4E4F534A
CHUNK_BIN = 0x004E4942


def read_glb(path: Path) -> tuple[dict, bytes]:
    data = path.read_bytes()
    magic, version, _ = struct.unpack_from("<III", data, 0)
    if magic != GLB_MAGIC or version != 2:
        raise ValueError(f"{path} is not a glTF 2.0 binary")
    json_length, json_type = struct.unpack_from("<II", data, 12)
    if json_type != CHUNK_JSON:
        raise ValueError("first GLB chunk must be JSON")
    doc = json.loads(data[20:20 + json_length])
    offset = 20 + json_length
    bin_length, bin_type = struct.unpack_from("<II", data, offset)
    if bin_type != CHUNK_BIN or len(doc.get("buffers", [])) != 1:
        raise ValueError("expected exactly one embedded binary buffer")
    return doc, data[offset + 8:offset + 8 + bin_length]


def accessor_bytes(doc: dict, blob: bytes, index: int) -> bytes:
    accessor = doc["accessors"][index]
    view = doc["bufferViews"][accessor["bufferView"]]
    start = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
    end = view.get("byteOffset", 0) + view["byteLength"]
    return blob[start:end]


def used_accessors(doc: dict) -> set[int]:
    used: set[int] = set()
    for mesh in doc.get("meshes", []):
        for primitive in mesh["primitives"]:
            used.update(primitive["attributes"].values())
            if "indices" in primitive:
                used.add(primitive["indices"])
            for target in primitive.get("targets", []):
                used.update(target.values())
    for skin in doc.get("skins", []):
        if "inverseBindMatrices" in skin:
            used.add(skin["inverseBindMatrices"])
    for animation in doc.get("animations", []):
        for sampler in animation["samplers"]:
            used.update((sampler["input"], sampler["output"]))
    return used


def extract(source: Path, output: Path, names: list[str]) -> str:
    doc, blob = read_glb(source)
    available = [animation["name"] for animation in doc.get("animations", [])]
    missing = [name for name in names if name not in available]
    if missing:
        raise ValueError(f"clips not present in {source.name}: {missing}")
    original = json.loads(json.dumps(doc))
    doc["animations"] = [animation for animation in doc["animations"] if animation["name"] in names]
    accessors = sorted(used_accessors(doc))
    if any("sparse" in doc["accessors"][i] for i in accessors):
        raise ValueError("sparse accessors are not supported")
    views = sorted({doc["accessors"][i]["bufferView"] for i in accessors}
                   | {image["bufferView"] for image in doc.get("images", []) if "bufferView" in image})
    view_map, new_views, chunks, length = {}, [], [], 0
    for old in views:
        view = dict(doc["bufferViews"][old])
        start = view.get("byteOffset", 0)
        padding = (-length) % 4
        chunks.append(b"\0" * padding + blob[start:start + view["byteLength"]])
        length += padding
        view["byteOffset"] = length
        length += view["byteLength"]
        view_map[old] = len(new_views)
        new_views.append(view)
    accessor_map, new_accessors = {}, []
    for old in accessors:
        accessor = dict(doc["accessors"][old])
        accessor["bufferView"] = view_map[accessor["bufferView"]]
        accessor_map[old] = len(new_accessors)
        new_accessors.append(accessor)
    for mesh in doc.get("meshes", []):
        for primitive in mesh["primitives"]:
            primitive["attributes"] = {key: accessor_map[value] for key, value in primitive["attributes"].items()}
            if "indices" in primitive:
                primitive["indices"] = accessor_map[primitive["indices"]]
            if "targets" in primitive:
                primitive["targets"] = [{key: accessor_map[value] for key, value in target.items()} for target in primitive["targets"]]
    for skin in doc.get("skins", []):
        if "inverseBindMatrices" in skin:
            skin["inverseBindMatrices"] = accessor_map[skin["inverseBindMatrices"]]
    for animation in doc["animations"]:
        for sampler in animation["samplers"]:
            sampler["input"] = accessor_map[sampler["input"]]
            sampler["output"] = accessor_map[sampler["output"]]
    for image in doc.get("images", []):
        if "bufferView" in image:
            image["bufferView"] = view_map[image["bufferView"]]
    doc["accessors"] = new_accessors
    doc["bufferViews"] = new_views
    new_blob = b"".join(chunks)
    new_blob += b"\0" * ((-len(new_blob)) % 4)
    doc["buffers"] = [{"byteLength": len(new_blob)}]

    by_name = {animation["name"]: animation for animation in original["animations"]}
    for animation in doc["animations"]:
        before = by_name[animation["name"]]
        if [c["target"] for c in before["channels"]] != [c["target"] for c in animation["channels"]]:
            raise AssertionError(f"{animation['name']}: channel targets changed")
        for old, new in zip(before["samplers"], animation["samplers"]):
            for key in ("input", "output"):
                if accessor_bytes(original, blob, old[key])[:_size(original, old[key])] != accessor_bytes(doc, new_blob, new[key])[:_size(doc, new[key])]:
                    raise AssertionError(f"{animation['name']}: sampler data changed")

    text = json.dumps(doc, separators=(",", ":")).encode()
    text += b" " * ((-len(text)) % 4)
    body = struct.pack("<II", len(text), CHUNK_JSON) + text + struct.pack("<II", len(new_blob), CHUNK_BIN) + new_blob
    result = struct.pack("<III", GLB_MAGIC, 2, 12 + len(body)) + body
    output.write_bytes(result)
    return hashlib.sha256(result).hexdigest()


def _size(doc: dict, index: int) -> int:
    accessor = doc["accessors"][index]
    components = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}[accessor["type"]]
    width = {5120: 1, 5121: 1, 5122: 2, 5123: 2, 5125: 4, 5126: 4}[accessor["componentType"]]
    return accessor["count"] * components * width


if __name__ == "__main__":
    if len(sys.argv) < 4:
        sys.exit(__doc__)
    source_path, output_path = Path(sys.argv[1]), Path(sys.argv[2])
    digest = extract(source_path, output_path, sys.argv[3:])
    print(f"{output_path.name}: {output_path.stat().st_size} bytes, sha256 {digest}")
    print(f"source {source_path.name}: sha256 {hashlib.sha256(source_path.read_bytes()).hexdigest()}")
