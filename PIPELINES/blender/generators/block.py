"""Parameterised bevelled block with its origin at the base centre.

Spec params (metres, glTF/Godot axes: x = width, y = height, z = depth):
  size [x, y, z], bevel (offset in m), bevel_segments (int), color [r, g, b, a], roughness (0..1)
"""
import bmesh
import bpy


def build(asset_id: str, params: dict):
    sx, sy, sz = (float(v) for v in params["size"])
    mesh = bpy.data.meshes.new(asset_id)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    # Blender is Z-up: glTF height (y) is Blender z and glTF depth (z) is Blender y.
    bmesh.ops.scale(bm, vec=(sx, sz, sy), verts=bm.verts)
    bmesh.ops.translate(bm, vec=(0.0, 0.0, sy / 2.0), verts=bm.verts)
    bevel = float(params.get("bevel", 0.0))
    if bevel > 0.0:
        bmesh.ops.bevel(bm, geom=list(bm.edges) + list(bm.verts), offset=bevel, offset_type="OFFSET",
                        segments=int(params.get("bevel_segments", 1)), profile=0.5, affect="EDGES", clamp_overlap=True)
    bm.to_mesh(mesh)
    bm.free()

    obj = bpy.data.objects.new(asset_id, mesh)
    bpy.context.scene.collection.objects.link(obj)
    mesh.materials.append(_material(f"{asset_id}_mat", params))
    return obj


def _material(name: str, params: dict):
    mat = bpy.data.materials.new(name)
    if mat.node_tree is None:  # Blender 4.x creates node-less materials through the API
        mat.use_nodes = True
    bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = tuple(params.get("color", (0.8, 0.8, 0.8, 1.0)))
    bsdf.inputs["Roughness"].default_value = float(params.get("roughness", 0.8))
    return mat
