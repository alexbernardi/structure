## Pipeline validation inside Godot: every deployed common asset imports and matches its declared size/pivot.
extends RefCounted

const ROOT := "res://assets/common"


func _sidecars(dir_path: String, out: Array[String]) -> void:
	for sub in DirAccess.get_directories_at(dir_path):
		_sidecars(dir_path.path_join(sub), out)
	for f in DirAccess.get_files_at(dir_path):
		if f.ends_with(".asset.json"):
			out.append(dir_path.path_join(f))


func _accumulate_bounds(node: Node, xform: Transform3D, boxes: Array[AABB]) -> void:
	var local := xform
	if node is Node3D:
		local = xform * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		boxes.append(local * (node as MeshInstance3D).get_aabb())
	for child in node.get_children():
		_accumulate_bounds(child, local, boxes)


func test_common_assets_import_with_declared_dimensions(t) -> void:
	var sidecars: Array[String] = []
	_sidecars(ROOT, sidecars)
	t.ok(not sidecars.is_empty(), "at least one common asset is deployed")
	for path in sidecars:
		var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		var glb := path.get_base_dir().path_join("%s.glb" % meta.asset_id)
		var scene: PackedScene = load(glb)
		if not t.ok(scene != null, "%s imports" % glb):
			continue
		var root := scene.instantiate()
		var boxes: Array[AABB] = []
		_accumulate_bounds(root, Transform3D.IDENTITY, boxes)
		root.free()
		if not t.ok(not boxes.is_empty(), "%s contains a mesh" % meta.asset_id):
			continue
		var bounds := boxes[0]
		for b in boxes:
			bounds = bounds.merge(b)
		var dims := Vector3(meta.dimensions_m[0], meta.dimensions_m[1], meta.dimensions_m[2])
		t.near(bounds.size, dims, 0.005, "%s size in Godot" % meta.asset_id)
		if meta.pivot == "base_center":
			t.near(bounds.position.y, 0.0, 0.005, "%s pivot at the base" % meta.asset_id)
			t.near(bounds.get_center().x, 0.0, 0.005, "%s centred on x" % meta.asset_id)
