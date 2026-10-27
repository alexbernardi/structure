"""Standard glTF export for every STRUCTURE asset (change export settings here only)."""
import bpy

SETTINGS = {
    "export_format": "GLB",
    "use_selection": True,
    "export_apply": True,
    "export_yup": True,
    "export_texcoords": True,
    "export_normals": True,
    "export_materials": "EXPORT",
    "export_cameras": False,
    "export_lights": False,
    "export_animations": False,
    "export_extras": False,
}


def export_glb(obj, filepath: str) -> None:
    for other in bpy.context.scene.objects:
        other.select_set(False)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    result = bpy.ops.export_scene.gltf(filepath=filepath, **SETTINGS)
    if result != {"FINISHED"}:
        raise RuntimeError(f"glTF export failed: {result}")


def exporter_version() -> str:
    try:
        import io_scene_gltf2

        return ".".join(str(v) for v in io_scene_gltf2.bl_info["version"])
    except Exception:  # bl_info layout differs between Blender releases
        return "unknown"
