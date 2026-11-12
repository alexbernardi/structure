## Biomechanical stick skeleton (Movement Lab 5.5): the character's real runtime skeleton drawn as joints and rods from
## its final pose - after the authored clips, the IK and every correction - on each skeleton update, so what is seen is
## exactly what the mesh is skinned to. Left limbs orange, right limbs cyan, pelvis / spine / head white; hands and feet
## are larger, with a pointer along the fingers (hand bone +Y) and toes. Drawn through the body (no depth test), which
## the mannequin shows at 40 % opacity while this view is on (authored_mannequin.set_body_alpha).
extends Node3D

const JOINT := 0.022             ## m joint sphere radius
const END_JOINT := 0.034         ## m for hands and feet
const ROD := 0.011               ## m bone rod radius
const FINGERS := 0.17            ## m hand pointer along the fingers
const LEFT := Color(1.0, 0.55, 0.12)
const RIGHT := Color(0.2, 0.78, 1.0)
const CENTRE := Color(0.96, 0.96, 0.88)
const LEFT_END := Color(1.0, 0.85, 0.2)
const RIGHT_END := Color(0.55, 1.0, 0.95)

var skeleton: Skeleton3D
var bone_index := {}
var updates := 0                 ## skeleton updates drawn (tests)
var joint_world := {}            ## bone name -> world position drawn last update (tests)
var _joints := MultiMeshInstance3D.new()
var _rods := MultiMeshInstance3D.new()
var _bones: Array[int] = []      ## bones drawn as joints
var _links: Array = []           ## [from bone, to bone] rods
var _ends := ["LeftHand", "RightHand", "LeftFoot", "RightFoot"]


func setup(target: Skeleton3D, index: Dictionary) -> void:
	skeleton = target
	bone_index = index
	top_level = true
	for bone in skeleton.get_bone_count():
		var name := skeleton.get_bone_name(bone)
		if name == "Root":
			continue
		_bones.append(bone)
		var parent := skeleton.get_bone_parent(bone)
		if parent >= 0 and skeleton.get_bone_name(parent) != "Root":
			_links.append([parent, bone])
	_joints.multimesh = _multimesh(_sphere(), _bones.size())
	_rods.multimesh = _multimesh(_cylinder(), _links.size() + 3)   # + two finger pointers and the head top
	for node in [_joints, _rods]:
		node.material_override = _material()
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
	skeleton.skeleton_updated.connect(_draw)


func _draw() -> void:
	if not visible:
		return
	updates += 1
	var to_world := skeleton.global_transform
	var poses := {}
	for k in _bones.size():
		var bone: int = _bones[k]
		var pose: Transform3D = to_world * skeleton.get_bone_global_pose(bone)
		poses[bone] = pose
		var name := skeleton.get_bone_name(bone)
		joint_world[name] = pose.origin
		var end := name in _ends
		var radius := END_JOINT if end else JOINT
		_joints.multimesh.set_instance_transform(k, Transform3D(Basis.from_scale(Vector3.ONE * radius), pose.origin))
		_joints.multimesh.set_instance_color(k, _colour(name, end))
	var i := 0
	for link in _links:
		var a: Vector3 = poses[link[0]].origin
		var b: Vector3 = poses[link[1]].origin
		_rod(i, a, b, _colour(skeleton.get_bone_name(link[1]), false))
		i += 1
	for side in ["Left", "Right"]:
		var hand: Transform3D = poses[bone_index[side + "Hand"]]
		_rod(i, hand.origin, hand.origin + hand.basis.y.normalized() * FINGERS, _colour(side + "Hand", true))
		i += 1
	var head: Transform3D = poses[bone_index.Head]
	_rod(i, head.origin, head.origin + head.basis.y.normalized() * 0.2, CENTRE)


func _rod(i: int, a: Vector3, b: Vector3, colour: Color) -> void:
	var length := a.distance_to(b)
	var basis := Basis.from_scale(Vector3(ROD, maxf(length, 0.001), ROD))
	if length > 1e-5:
		basis = Basis(Quaternion(Vector3.UP, (b - a) / length)) * basis
	_rods.multimesh.set_instance_transform(i, Transform3D(basis, (a + b) * 0.5))
	_rods.multimesh.set_instance_color(i, colour)


func _colour(name: String, end: bool) -> Color:
	if name.begins_with("Left"):
		return LEFT_END if end else LEFT
	if name.begins_with("Right"):
		return RIGHT_END if end else RIGHT
	return CENTRE


func _multimesh(mesh: Mesh, count: int) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = count
	return mm


func _sphere() -> Mesh:
	var m := SphereMesh.new()
	m.radius = 1.0
	m.height = 2.0
	m.radial_segments = 12
	m.rings = 6
	return m


func _cylinder() -> Mesh:
	var m := CylinderMesh.new()
	m.top_radius = 1.0
	m.bottom_radius = 1.0
	m.height = 1.0
	m.radial_segments = 8
	return m


func _material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.no_depth_test = true                       # always visible through the (40 % opaque) body
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.render_priority = 20                        # after the transparent body
	return m
