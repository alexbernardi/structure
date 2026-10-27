import json
import struct
import unittest

import toolhelpers
from structure_cli import assets, paths


def make_glb(doc: dict) -> bytes:
    payload = json.dumps(doc).encode()
    payload += b" " * ((4 - len(payload) % 4) % 4)
    body = struct.pack("<I4s", len(payload), b"JSON") + payload
    return struct.pack("<4sII", b"glTF", 2, 12 + len(body)) + body


def box_doc(name="thing", size=(1.0, 2.0, 1.0), triangles=12):
    return {
        "asset": {"version": "2.0"},
        "meshes": [{"name": name, "primitives": [{"attributes": {"POSITION": 0}, "indices": 1}]}],
        "nodes": [{"name": name, "mesh": 0}],
        "materials": [{}],
        "accessors": [{"count": 8, "min": [-size[0] / 2, 0, -size[2] / 2], "max": [size[0] / 2, size[1], size[2] / 2]},
                      {"count": triangles * 3}],
    }


SPEC = {"asset_id": "thing", "params": {"size": [1.0, 2.0, 1.0]}, "origin": "base_center", "tolerance_m": 0.001,
        "budget": {"max_triangles": 100, "max_materials": 1, "max_images": 0, "max_bytes": 10000}}


class GlbValidatorTest(unittest.TestCase):
    def setUp(self):
        self.tmp = toolhelpers.temp_dir("glb")
        self.validator = assets._validator()

    def tearDown(self):
        toolhelpers.cleanup(self.tmp)

    def check(self, data: bytes, spec=SPEC):
        path = self.tmp / "x.glb"
        path.write_bytes(data)
        return self.validator.validate(path, spec)

    def test_valid_file_passes(self):
        errors, info = self.check(make_glb(box_doc()))
        self.assertEqual(errors, [])
        self.assertEqual(info["triangles"], 12)

    def test_wrong_magic_is_reported(self):
        errors, _ = self.check(b"NOPE" + make_glb(box_doc())[4:])
        self.assertIn("bad magic", errors[0])

    def test_dimensions_pivot_names_and_budget(self):
        doc = box_doc(name="Thing", size=(1.0, 3.0, 1.0), triangles=500)
        doc["nodes"][0]["scale"] = [2, 2, 2]
        doc["accessors"][0]["min"][1] = 0.5
        errors, _ = self.check(make_glb(doc))
        text = " | ".join(errors)
        for expected in ("mesh named 'thing'", "non-identity scale", "size.y", "base centre", "exceed the budget"):
            self.assertIn(expected, text)

    def test_committed_library_asset_is_valid(self):
        for asset_id in assets.asset_ids():
            folder, meta, spec = assets.load(asset_id)
            errors, _ = self.validator.validate(folder / meta["runtime"]["path"], spec)
            self.assertEqual(errors, [], asset_id)
        self.assertTrue(paths.ASSET_MANIFEST.is_file())


if __name__ == "__main__":
    unittest.main()
