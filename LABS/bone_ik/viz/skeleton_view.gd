## Exposed mechanical skeleton for the Vitruvian rig: one faceted bone per segment (joint -> tip), a sphere per
## joint coloured by joint type, optional labels, local axes, rest / animation-stage ghosts and the selected joint's
## rotation limits. Reads the rig's stage snapshots (rig.stage_globals), so it shows exactly what the chain produced.
extends Node3D

const JointProfile = preload("res://systems/bone_ik/rig/joint_profile.gd")
const JointMath = preload("res://systems/bone_ik/rig/joint_math.gd")

const SIDE_COLOURS := {"L": Color(0.28, 0.56, 1.0), "R": Color(0.95, 0.36, 0.30), "C": Color(0.92, 0.88, 0.78)}
const JOINT_COLOURS := {"hinge": Color(1.0, 0.62, 0.15), "ball": Color(0.86, 0.32, 0.86), "spinal": Color(0.98, 0.86, 0.25),
	"girdle": Color(0.25, 0.85, 0.9), "ellipsoid": Color(0.3, 0.8, 0.55), "none": Color(0.9, 0.9, 0.9)}
const AXIS_COLOURS := [Color(1, 0.2, 0.2), Color(0.2, 0.95, 0.3), Color(0.25, 0.45, 1)]
const LIMIT_COLOURS := {"flex": Color(1.0, 0.6, 0.1), "abd": Color(0.2, 0.85, 1.0), "twist": Color(0.8, 0.45, 1.0)}

var rig
var show_labels := true
var show_axes := false
var show_limits := true
var show_rest_ghost := false
var show_animation_ghost := true
var selected := "LeftLowerArm"

var _bones := []          ## {index, mesh: MeshInstance3D, local: Transform3D (mesh in bone frame)}
var _joints := []         ## {index, mesh, material, label}
var _lines: MeshInstance3D
var _immediate: ImmediateMesh
var _bone_mesh: ArrayMesh


func setup(target_rig) -> void:
	rig = target_rig
	if _bone_mesh == null:
		_bone_mesh = _octahedron()
		_immediate = ImmediateMesh.new()
		_lines = MeshInstance3D.new()
		_lines.mesh = _immediate
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.vertex_color_use_as_albedo = true
		m.no_depth_test = true
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.render_priority = 2
		_lines.material_override = m
		_lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_lines)
	rebuild()


## Recreates bone and joint visuals for the rig's current definition (after a proportion change).
func rebuild() -> void:
	for b in _bones:
		b.mesh.queue_free()
	for j in _joints:
		j.mesh.queue_free()
		j.label.queue_free()
	_bones.clear()
	_joints.clear()
	var def: Dictionary = rig.definition
	var scale_k: float = def.dims.height / 1.8
	for bone in def.bones:
		if bone.name == "Root":
			continue
		var rest: Transform3D = bone.global
		var tip_local: Vector3 = rest.affine_inverse() * (bone.tip as Vector3)
		var length := tip_local.length()
		var width := clampf(length * 0.11, 0.010, 0.03) * (0.45 if bone.helper else 1.0) * scale_k
		var y := tip_local / maxf(length, 1e-6)
		var x := y.cross(Vector3(0, 0, 1) if absf(y.z) < 0.9 else Vector3(1, 0, 0)).normalized()
		var z := x.cross(y).normalized()
		var mi := MeshInstance3D.new()
		mi.mesh = _bone_mesh
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.35, 0.8, 0.45) if bone.helper else SIDE_COLOURS[bone.side]
		mat.roughness = 0.55
		mat.metallic = 0.25
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mi.material_override = mat
		add_child(mi)
		_bones.append({"index": def.index[bone.name], "mesh": mi,
			"local": Transform3D(Basis(x * width, y * length, z * width), Vector3.ZERO)})
		if bone.helper:
			continue
		var j: Dictionary = rig.profile.joint(bone.name)
		var sphere := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = (0.022 if j.is_empty() or j.type != "spinal" else 0.026) * scale_k
		sm.height = sm.radius * 2.0
		sm.radial_segments = 16
		sm.rings = 8
		sphere.mesh = sm
		var jm := StandardMaterial3D.new()
		jm.albedo_color = JOINT_COLOURS["none" if j.is_empty() else j.type]
		jm.emission_enabled = true
		jm.emission = jm.albedo_color * 0.25
		sphere.material_override = jm
		add_child(sphere)
		var label := Label3D.new()
		label.text = bone.name
		label.font_size = 22
		label.pixel_size = 0.0009 * scale_k
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.outline_size = 6
		label.modulate = Color(1, 1, 1, 0.92)
		label.render_priority = 3
		label.offset = Vector2(0, 26)
		add_child(label)
		_joints.append({"index": def.index[bone.name], "bone": bone.name, "mesh": sphere, "material": jm,
			"label": label, "base": jm.albedo_color})


func _process(_delta: float) -> void:
	if rig == null or rig.definition.is_empty():
		return
	var to_world: Transform3D = rig.global_transform
	var g: Array[Transform3D] = rig.stage_globals("final")
	for b in _bones:
		b.mesh.global_transform = to_world * g[b.index] * b.local
	var states: Dictionary = rig.limit_modifier.states
	for j in _joints:
		j.mesh.global_position = to_world * g[j.index].origin
		j.label.global_position = j.mesh.global_position
		j.label.visible = show_labels
		var s: Dictionary = states.get(j.bone, {})
		var colour: Color = j.base
		if s.get("hard", 0.0) > 1e-4:
			colour = Color(1, 0.1, 0.1)
		elif s.get("soft", 0.0) > 0.0:
			colour = j.base.lerp(Color(1, 0.95, 0.1), 0.6)
		if j.bone == selected:
			colour = colour.lightened(0.35)
			j.mesh.scale = Vector3.ONE * 1.6
		else:
			j.mesh.scale = Vector3.ONE
		j.material.albedo_color = colour
	_draw_lines(to_world, g)


## World positions of the joints (for picking).
func joint_positions() -> Dictionary:
	var out := {}
	for j in _joints:
		out[j.bone] = j.mesh.global_position
	return out


func _draw_lines(to_world: Transform3D, g: Array[Transform3D]) -> void:
	_immediate.clear_surfaces()
	_immediate.surface_begin(Mesh.PRIMITIVE_LINES)
	var def: Dictionary = rig.definition
	var k: float = def.dims.height / 1.8
	var count := 0
	if show_rest_ghost:
		count += _ghost(to_world, rig.stage_globals("rest"), Color(0.75, 0.75, 0.75, 0.55))
	if show_animation_ghost and rig.probe_animation.has_snapshot():
		count += _ghost(to_world, rig.stage_globals("animation"), Color(1.0, 0.55, 0.1, 0.8))
	if show_axes:
		for j in _joints:
			var t: Transform3D = to_world * g[j.index]
			for a in 3:
				_line(t.origin, t.origin + t.basis[a].normalized() * 0.07 * k, AXIS_COLOURS[a])
				count += 1
	if show_limits:
		count += _limit_gizmo(to_world, g, k)
	if count == 0:
		_line(Vector3.ZERO, Vector3.ZERO, Color(0, 0, 0, 0))   # an empty surface is an error
	_immediate.surface_end()


func _line(a: Vector3, b: Vector3, c: Color) -> void:
	_immediate.surface_set_color(c)
	_immediate.surface_add_vertex(a)
	_immediate.surface_set_color(c)
	_immediate.surface_add_vertex(b)


func _ghost(to_world: Transform3D, g: Array[Transform3D], c: Color) -> int:
	var def: Dictionary = rig.definition
	var n := 0
	for bone in def.bones:
		if bone.name == "Root" or bone.helper:
			continue
		var i: int = def.index[bone.name]
		var tip: Vector3 = g[i] * ((bone.global as Transform3D).affine_inverse() * (bone.tip as Vector3))
		_line(to_world * g[i].origin, to_world * tip, c)
		n += 1
	return n


## Arcs of the selected joint's flex, abd and twist ranges, drawn in the proximal segment's current frame:
## axis colour = soft range, red = resistance zone up to the hard limit, white = current angle.
func _limit_gizmo(to_world: Transform3D, g: Array[Transform3D], k: float) -> int:
	var j: Dictionary = rig.profile.joint(selected)
	if j.is_empty():
		return 0
	var def: Dictionary = rig.definition
	var parent_i: int = def.index[j.parent]
	var parent_motion: Quaternion = g[parent_i].basis.get_rotation_quaternion() * (j.parent_rest as Quaternion).inverse()
	var basis_w: Quaternion = to_world.basis.get_rotation_quaternion() * parent_motion
	var c: Vector3 = to_world * g[j.bone_index].origin
	var d0: Vector3 = (j.neutral as Quaternion) * (j.d_rest as Vector3)
	var current: Vector3 = rig.get_joint_angles(selected, "final") * (PI / 180.0)
	var bone_len: float = def.bones[j.bone_index].length
	var r := clampf(bone_len * 0.55, 0.06 * k, 0.22 * k)
	var n := 0
	for axis_name in ["flex", "abd"]:
		var axis: Vector3 = j.f if axis_name == "flex" else j.a
		var lim: Dictionary = j.limits[axis_name]
		var cur: float = current.x if axis_name == "flex" else current.y
		n += _arc(c, basis_w, axis, d0, r, lim, LIMIT_COLOURS[axis_name], cur)
	# Twist: a ring around the segment axis, a little way along the bone.
	var t_axis: Vector3 = j.t
	var ring_c: Vector3 = c + basis_w * (d0 * minf(bone_len * 0.35, 0.12 * k))
	var ref: Vector3 = j.f
	n += _arc(ring_c, basis_w, t_axis, ref, r * 0.45, j.limits.twist, LIMIT_COLOURS.twist, current.z)
	return n


func _arc(c: Vector3, basis_w: Quaternion, axis: Vector3, start: Vector3, r: float, lim: Dictionary, colour: Color, cur: float) -> int:
	var steps := 36
	var lo: float = lim.hard.x
	var hi: float = lim.hard.y
	var prev := Vector3.ZERO
	for s in steps + 1:
		var a := lerpf(lo, hi, float(s) / steps)
		var p := c + basis_w * (Quaternion(axis, a) * start) * r
		if s > 0:
			var mid := (a + lerpf(lo, hi, float(s - 1) / steps)) * 0.5
			var in_soft: bool = mid >= lim.soft.x and mid <= lim.soft.y
			_line(prev, p, colour if in_soft else Color(1, 0.15, 0.15))
		prev = p
	_line(c, c + basis_w * (Quaternion(axis, lo) * start) * r, Color(1, 0.15, 0.15, 0.6))
	_line(c, c + basis_w * (Quaternion(axis, hi) * start) * r, Color(1, 0.15, 0.15, 0.6))
	_line(c, c + basis_w * (Quaternion(axis, cur) * start) * r * 1.15, Color(1, 1, 1))
	return steps + 3


static func _octahedron() -> ArrayMesh:
	# Unit bone along +Y: joint at 0, tip at 1, a square waist at y = 0.18 of radius 1 (scaled per bone).
	var top := Vector3(0, 1, 0)
	var bottom := Vector3.ZERO
	var ring := [Vector3(1, 0.18, 0), Vector3(0, 0.18, 1), Vector3(-1, 0.18, 0), Vector3(0, 0.18, -1)]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	for i in 4:
		var a: Vector3 = ring[i]
		var b: Vector3 = ring[(i + 1) % 4]
		for tri in [[bottom, b, a], [a, b, top]]:
			for v in tri:
				st.add_vertex(v)
	st.generate_normals()
	return st.commit()
