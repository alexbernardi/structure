## Primitive humanoid: a Skeleton3D built in code, Godot primitive meshes attached to its bones, and a procedural
## animator (walk/run cycle, crouch, jump/fall pose). Knows nothing about collision or input: it only consumes a small
## state dictionary from update_pose(). When the state carries a dyn pose from BodyDynamics (animation/body_dynamics.gd),
## the torso, pelvis, head, shoulders, arms and facing come from that spring model; without it (or with the model's
## master switch off) the original simple lean/dip pose is used, unchanged.
extends Node3D

const RigParams = preload("res://animation/rig_params.gd")

const FOOT_H := 0.07
const THIGH := 0.45
const SHIN := 0.44
const ANKLE_H := 0.065     # foot joint height above the ground when the sole is flat
const HIP_DROP := 0.05     # thigh joints sit this far below the pelvis joint
const HAND_LENGTH_RATIO := 0.42

## name, parent, rest origin (relative to the parent joint), colour. The meshes come from mesh_specs().
const BONES := [
	["pelvis", "", Vector3(0.0, 1.01, 0.0), "pants"],
	["spine", "pelvis", Vector3(0.0, 0.08, 0.0), "shirt"],
	["chest", "spine", Vector3(0.0, 0.20, 0.0), "shirt"],
	["neck", "chest", Vector3(0.0, 0.26, 0.0), "skin"],
	["head", "neck", Vector3(0.0, 0.08, 0.0), "skin"],
	["upper_arm_l", "chest", Vector3(-0.23, 0.22, 0.0), "shirt"],
	["forearm_l", "upper_arm_l", Vector3(0.0, -0.29, 0.0), "skin"],
	["upper_arm_r", "chest", Vector3(0.23, 0.22, 0.0), "shirt"],
	["forearm_r", "upper_arm_r", Vector3(0.0, -0.29, 0.0), "skin"],
	["thigh_l", "pelvis", Vector3(-0.10, -0.05, 0.0), "pants"],
	["shin_l", "thigh_l", Vector3(0.0, -THIGH, 0.0), "pants"],
	["foot_l", "shin_l", Vector3(0.0, -SHIN, 0.0), "shoe"],
	["thigh_r", "pelvis", Vector3(0.10, -0.05, 0.0), "pants"],
	["shin_r", "thigh_r", Vector3(0.0, -THIGH, 0.0), "pants"],
	["foot_r", "shin_r", Vector3(0.0, -SHIN, 0.0), "shoe"],
]
## Extra meshes riding a bone next to its main one: key, bone, node name, colour
const EXTRAS := [["hand_l", "forearm_l", "Hand", "skin"], ["hand_r", "forearm_r", "Hand", "skin"], ["nose", "head", "Nose", "skin"]]
const COLOURS := {"skin": Color(0.88, 0.70, 0.55), "shirt": Color(0.25, 0.45, 0.80), "pants": Color(0.22, 0.24, 0.30), "shoe": Color(0.12, 0.12, 0.13)}

var skeleton := Skeleton3D.new()
var bone_index: Dictionary = {}

var phase := 0.0
var gait_amount := 0.0   ## 0..1 from the horizontal speed (read by the body dynamics)
var crouch_blend := 0.0
var air_blend := 0.0
var lean := 0.0
var dip := 0.0
var _turn_yaw := 0.0
var _stand_hip := 0.0
var gait_weight := 0.0   ## how much of the pose comes from the gait model (0..1)
var dims: Dictionary = RigParams.dims(null)   ## the rig's real dimensions (metres), changed by apply_rig()
var _meshes: Dictionary = {}
var walk_animation
var _rotations: Dictionary = {}
var _positions: Dictionary = {}


func _ready() -> void:
	# Posed every rendered frame from the body's interpolated position, so it must not be physics-interpolated itself:
	# limb poses changed outside the physics tick would otherwise be sampled at the tick rate and beat against the display.
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	build()
	walk_animation = get_node_or_null("WalkAnimation")


## Places the whole humanoid at the body's (interpolated) feet position; call once per rendered frame before update_pose.
func follow(body: Node3D, vertical_offset := 0.0) -> void:
	global_position = body.get_global_transform_interpolated().origin + Vector3.UP * vertical_offset


func build() -> void:
	var existing := get_node_or_null("Skeleton3D") as Skeleton3D
	if existing != null and existing != skeleton:
		skeleton.free()
		skeleton = existing
		for b in BONES:
			bone_index[b[0]] = skeleton.find_bone(b[0])
			_meshes[b[0]] = skeleton.get_node("Attach_%s/Mesh" % b[0])
		for e in EXTRAS:
			var attach: Node = skeleton.get_node("Attach_%s" % e[1])
			_meshes[e[0]] = attach.get_node_or_null(NodePath(e[2]))
			if _meshes[e[0]] == null:   # a scene saved before the mesh existed
				_meshes[e[0]] = _add_mesh(attach, e[2], e[3])
		_apply_meshes()
		_stand_hip = _hip_height(0.0, 0.0)
	if skeleton.get_bone_count() > 0:
		return
	skeleton.name = "Skeleton3D"
	add_child(skeleton)
	for b in BONES:
		var idx := skeleton.add_bone(b[0])
		bone_index[b[0]] = idx
		if b[1] != "":
			skeleton.set_bone_parent(idx, bone_index[b[1]])
		skeleton.set_bone_rest(idx, Transform3D(Basis.IDENTITY, b[2]))
	skeleton.reset_bone_poses()
	for b in BONES:
		var attach := BoneAttachment3D.new()
		attach.name = "Attach_%s" % b[0]
		attach.bone_name = b[0]
		skeleton.add_child(attach)
		_meshes[b[0]] = _add_mesh(attach, "Mesh", b[3])
	for e in EXTRAS:
		_meshes[e[0]] = _add_mesh(skeleton.get_node("Attach_%s" % e[1]), e[2], e[3])
	_apply_meshes()
	_stand_hip = _hip_height(0.0, 0.0)


func _add_mesh(parent: Node, mesh_name: String, colour: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = mesh_name
	var mat := StandardMaterial3D.new()
	mat.albedo_color = COLOURS[colour]
	mat.roughness = 0.85
	mi.material_override = mat
	parent.add_child(mi)
	return mi


## The primitive body shapes for a set of rig dimensions (RigParams.dims): mesh key -> [kind, size, offset from the bone's
## joint, scale]. "box" size = extents; "sphere" size = (radius, height); "capsule" size = (radius, height). The trunk pieces
## are capsules squashed front-to-back, the pelvis an egg tipped back under the waist, the head an egg a little taller than
## wide whose centre sits forward of the neck, with a nose to show which way it faces.
static func mesh_specs(d: Dictionary) -> Dictionary:
	var k: float = d.scale
	var seg: float = d.torso * (0.20 / 0.28)
	var foot_t: float = FOOT_H * k
	var pelvis_hw: float = (d.hip_x + 0.075 * k) * d.torso_w
	var pelvis_hd: float = 0.11 * k * d.torso_d
	var spine_hw: float = 0.14 * k * d.torso_w
	var spine_hd: float = 0.095 * k * d.torso_d
	var chest_h := chest_half_size(d)
	var hr: float = d.head_r
	var specs := {
		"pelvis": ["sphere", Vector3(pelvis_hd, 0.22 * k, 0.0), Vector3(0.0, -0.015 * k, 0.012 * k), Vector3(pelvis_hw / pelvis_hd, 1.0, 1.0)],
		"spine": ["capsule", Vector3(spine_hd, seg * 1.7, 0.0), Vector3(0.0, seg * 0.6, 0.004 * k), Vector3(spine_hw / spine_hd, 1.0, 1.0)],
		"chest": ["capsule", Vector3(chest_h.z, chest_h.y * 2.0, 0.0), chest_centre(d), Vector3(chest_h.x / chest_h.z, 1.0, 1.0)],
		"neck": ["capsule", Vector3(0.045 * k, d.neck * 2.2, 0.0), Vector3(0.0, d.neck * 0.3, 0.0), Vector3.ONE],
		"head": ["sphere", Vector3(hr * 0.92, hr * 2.0, 0.0), head_centre(d), Vector3(0.84, 1.0, 1.0)],
		"nose": ["sphere", Vector3(hr * 0.16, hr * 0.36, 0.0), head_centre(d) + Vector3(0.0, -hr * 0.12, -hr * 0.86), Vector3.ONE],
	}
	for s in ["l", "r"]:
		specs["upper_arm_" + s] = ["capsule", Vector3(d.upper_arm_r, d.upper_arm * (0.30 / 0.29), 0.0), Vector3(0.0, -d.upper_arm * (0.14 / 0.29), 0.0), Vector3.ONE]
		specs["forearm_" + s] = ["capsule", Vector3(d.forearm_r, d.forearm * (0.28 / 0.29), 0.0), Vector3(0.0, -d.forearm * (0.13 / 0.29), 0.0), Vector3.ONE]
		var hand_len: float = d.forearm * HAND_LENGTH_RATIO
		var hand_r: float = d.forearm_r * 1.1
		specs["hand_" + s] = ["capsule", Vector3(hand_r, hand_len, 0.0), Vector3(0.0, -d.forearm - hand_len * 0.38, 0.0), Vector3(1.0, 1.0, 0.45)]
		specs["thigh_" + s] = ["capsule", Vector3(d.thigh_r, d.thigh * (0.46 / 0.45), 0.0), Vector3(0.0, -d.thigh * (0.22 / 0.45), 0.0), Vector3.ONE]
		specs["shin_" + s] = ["capsule", Vector3(d.shin_r, d.shin, 0.0), Vector3(0.0, -d.shin * (0.21 / 0.44), 0.0), Vector3.ONE]
		specs["foot_" + s] = ["box", Vector3(0.10 * k, foot_t, d.foot_len), Vector3(0.0, -(d.ankle_h - foot_t * 0.5), -(d.toe.x + d.heel.x) * 0.5), Vector3.ONE]
	return specs


## Centre of the chest shape relative to the chest joint, and its half width / height / depth (used by the rig editor too).
static func chest_centre(d: Dictionary) -> Vector3:
	return Vector3(0.0, d.chest * 0.5, 0.0)


static func chest_half_size(d: Dictionary) -> Vector3:
	var k: float = d.scale
	return Vector3(maxf(d.shoulder_x - 0.025 * k, 0.05 * k) * d.torso_w, d.chest * 0.62, 0.105 * k * d.torso_d)


## Centre of the head shape relative to the head joint (the top of the neck): above it and a little forward.
static func head_centre(d: Dictionary) -> Vector3:
	return Vector3(0.0, d.head_r * 0.85, -d.head_r * 0.15)


func _apply_meshes() -> void:
	var specs := mesh_specs(dims)
	for key in specs:
		var mi: MeshInstance3D = _meshes.get(key)
		if mi == null:
			continue
		mi.mesh = _mesh(specs[key][0], specs[key][1])
		mi.position = specs[key][2]
		mi.scale = specs[key][3]


static func _mesh(kind: String, size: Vector3) -> Mesh:
	match kind:
		"box":
			var m := BoxMesh.new()
			m.size = size
			return m
		"sphere":
			var s := SphereMesh.new()
			s.radius = size.x
			s.height = size.y
			return s
	var c := CapsuleMesh.new()
	c.radius = size.x
	c.height = maxf(size.y, size.x * 2.0)
	return c


## Height of the pelvis bone above the ground for a leg with the given thigh and knee angles.
func _hip_height(thigh_angle: float, knee_angle: float) -> float:
	return dims.ankle_h + dims.hip_drop + dims.thigh * cos(thigh_angle) + dims.shin * cos(thigh_angle + knee_angle)


## Re-proportions the humanoid live from a rig parameter set (animation/rig_params.gd): bone lengths and joint offsets move the
## skeleton's rest pose, limb sizes and thickness rebuild the primitive meshes. Safe to call every time a value changes.
func apply_rig(rig) -> void:
	build()
	dims = RigParams.dims(rig)
	var d := dims
	var k: float = d.scale
	var origins := {
		"pelvis": Vector3(0.0, d.ankle_h + d.hip_drop + d.thigh + d.shin + 0.005 * k, 0.0),
		"spine": Vector3(0.0, d.torso * (0.08 / 0.28), 0.0), "chest": Vector3(0.0, d.torso * (0.20 / 0.28), 0.0),
		"neck": Vector3(0.0, d.chest, 0.0), "head": Vector3(0.0, d.neck, 0.0),
		"upper_arm_l": Vector3(-d.shoulder_x, d.chest * (0.22 / 0.26), 0.0), "upper_arm_r": Vector3(d.shoulder_x, d.chest * (0.22 / 0.26), 0.0),
		"forearm_l": Vector3(0.0, -d.upper_arm, 0.0), "forearm_r": Vector3(0.0, -d.upper_arm, 0.0),
		"thigh_l": Vector3(-d.hip_x, -d.hip_drop, 0.0), "thigh_r": Vector3(d.hip_x, -d.hip_drop, 0.0),
		"shin_l": Vector3(0.0, -d.thigh, 0.0), "shin_r": Vector3(0.0, -d.thigh, 0.0),
		"foot_l": Vector3(0.0, -d.shin, 0.0), "foot_r": Vector3(0.0, -d.shin, 0.0),
	}
	for bone in origins:
		var idx: int = bone_index[bone]
		skeleton.set_bone_rest(idx, Transform3D(Basis.IDENTITY, origins[bone]))
		if bone != "pelvis":   # the pelvis' position is posed every frame
			skeleton.set_bone_pose_position(idx, origins[bone])
	_apply_meshes()
	_stand_hip = _hip_height(0.0, 0.0)


## state: {speed: horizontal m/s, vy: vertical m/s, grounded: bool, crouching: bool, accel_forward: m/s^2,
##         heading: world yaw of horizontal velocity (rad) or NAN, landed_impact: m/s (optional, one tick),
##         dyn: pose dictionary from BodyDynamics.update() (optional),
##         gait: pose dictionary from GaitModel.update() (optional; legs, feet, pelvis, arms and trunk twist come from it
##               while the character walks on the ground, fading back to the simple pose in the air, crouching or landing)}
func update_pose(state: Dictionary, delta: float) -> void:
	_calculate_pose(state, delta)
	if walk_animation != null and walk_animation.model != null:
		var full := pose_snapshot()
		var weight := gait_weight
		var fallback := state.duplicate()
		fallback.erase("gait")
		fallback.erase("landed_impact")
		_calculate_pose(fallback, 0.0)
		var legacy := pose_snapshot()
		gait_weight = weight
		walk_animation.apply_pose(full, legacy, weight)
	else:
		for bone in _rotations:
			skeleton.set_bone_pose_rotation(bone_index[bone], _rotations[bone])
		for bone in _positions:
			skeleton.set_bone_pose_position(bone_index[bone], _positions[bone])


func pose_snapshot() -> Dictionary:
	return {"rotations": _rotations.duplicate(), "positions": _positions.duplicate()}


func _set_rotation(bone: String, value: Quaternion) -> void:
	_rotations[bone] = value


func _set_position(bone: String, value: Vector3) -> void:
	_positions[bone] = value


func _calculate_pose(state: Dictionary, delta: float) -> void:
	if skeleton.get_bone_count() == 0:
		return
	var speed: float = state.get("speed", 0.0)
	var grounded: bool = state.get("grounded", true)
	var crouching: bool = state.get("crouching", false)
	var vy: float = state.get("vy", 0.0)
	var dyn: Dictionary = state.get("dyn", {})
	var use_dyn: bool = dyn.get("active", false)
	var gait_pose: Dictionary = state.get("gait", {})
	var use_gait: bool = gait_pose.get("active", false)

	crouch_blend = move_toward(crouch_blend, 1.0 if crouching else 0.0, delta * 7.0)
	air_blend = move_toward(air_blend, 0.0 if grounded else 1.0, delta * 9.0)
	var gait := clampf(speed / 6.5, 0.0, 1.0)
	gait_amount = gait
	if grounded and speed > 0.15:
		phase += delta * lerpf(5.0, 12.0, gait)
		phase = fmod(phase, TAU)
	var forward_lean := lean   # + = leaning forward
	var pelvis_drop := 0.0     # - = hips lowered by a landing
	if use_dyn:
		forward_lean = dyn.torso_pitch
		pelvis_drop = dyn.pelvis_drop
		_turn_yaw = dyn.facing_yaw
	else:
		var target_lean := clampf(speed * 0.022 + float(state.get("accel_forward", 0.0)) * 0.0035, -0.15, 0.38)
		lean = lerpf(lean, target_lean, 1.0 - exp(-8.0 * delta))
		forward_lean = lean
		if state.get("landed_impact", 0.0) > 0.0:
			dip = clampf(float(state.landed_impact) / 14.0, 0.0, 0.22)
		dip = lerpf(dip, 0.0, 1.0 - exp(-10.0 * delta))
		pelvis_drop = -dip
		var heading: float = state.get("heading", NAN)
		if not is_nan(heading) and speed > 0.4:
			_turn_yaw = lerp_angle(_turn_yaw, heading, 1.0 - exp(-12.0 * delta))
	rotation.y = _turn_yaw

	var swing := sin(phase) * lerpf(0.35, 0.85, gait)
	var swing_r := sin(phase + PI) * lerpf(0.35, 0.85, gait)
	var knee := lerpf(0.25, 1.25, gait)
	var knee_l := -(maxf(0.0, cos(phase)) * knee + 0.08)
	var knee_r := -(maxf(0.0, cos(phase + PI)) * knee + 0.08)
	var idle := 1.0 - clampf(speed / 0.6, 0.0, 1.0)
	if idle > 0.0:
		swing *= 1.0 - idle
		swing_r *= 1.0 - idle
		knee_l *= 1.0 - idle
		knee_r *= 1.0 - idle

	# crouch: deep knee bend; air: tucked legs, rising vs falling changes the spread
	var thigh_l := lerpf(swing, 1.30, crouch_blend)
	var thigh_r := lerpf(swing_r, 1.30, crouch_blend)
	var shin_l := lerpf(knee_l, -2.0, crouch_blend)
	var shin_r := lerpf(knee_r, -2.0, crouch_blend)
	var rising := clampf(vy / 6.0, -1.0, 1.0)
	thigh_l = lerpf(thigh_l, 0.55 + 0.25 * rising, air_blend)
	thigh_r = lerpf(thigh_r, -0.15 - 0.2 * rising, air_blend)
	shin_l = lerpf(shin_l, -0.9 - 0.3 * rising, air_blend)
	shin_r = lerpf(shin_r, -0.7, air_blend)
	if use_dyn and pelvis_drop < 0.0:
		# A landing lowers the hips by bending both knees (thigh forward, shin back twice as far keeps the foot under
		# the hip), so the feet stay on the ground instead of sinking into it.
		var flex := acos(clampf(1.0 + pelvis_drop / (dims.thigh + dims.shin), -1.0, 1.0)) * (1.0 - air_blend) * (1.0 - crouch_blend)
		thigh_l += flex
		thigh_r += flex
		shin_l -= 2.0 * flex
		shin_r -= 2.0 * flex

	var foot_l_a := -(thigh_l + shin_l) * 0.5 * (1.0 - air_blend) - 0.2 * air_blend
	var foot_r_a := -(thigh_r + shin_r) * 0.5 * (1.0 - air_blend) - 0.2 * air_blend
	var hip := maxf(_hip_height(thigh_l, shin_l), _hip_height(thigh_r, shin_r))
	if air_blend > 0.5:
		hip = _stand_hip - 0.10 * air_blend
	var gw := 0.0
	var gait_q := Quaternion.IDENTITY
	if use_gait:
		# The gait model owns the legs only while walking on the ground; a landing compression hands them back for its duration.
		gw = (1.0 - air_blend) * (1.0 - crouch_blend) * clampf(1.0 + pelvis_drop / 0.02, 0.0, 1.0)
		gait_q = gait_pose.pelvis_q
		thigh_l = lerpf(thigh_l, gait_pose.thigh_l, gw)
		thigh_r = lerpf(thigh_r, gait_pose.thigh_r, gw)
		shin_l = lerpf(shin_l, -float(gait_pose.knee_l), gw)
		shin_r = lerpf(shin_r, -float(gait_pose.knee_r), gw)
		foot_l_a = lerpf(foot_l_a, gait_pose.foot_l, gw)
		foot_r_a = lerpf(foot_r_a, gait_pose.foot_r, gw)
		hip = lerpf(hip, gait_pose.pelvis.y, gw)
	gait_weight = gw
	var bob := absf(cos(phase)) * 0.03 * gait * (1.0 - air_blend) * (1.0 - gw)
	var pelvis_y := hip + bob - dip * (1.0 - gw)
	var pelvis_x := 0.0
	var pelvis_z := 0.0
	var pelvis_rot := Quaternion.IDENTITY
	if use_dyn:
		pelvis_y = hip + dyn.bob * (1.0 - air_blend) * (1.0 - gw) + maxf(pelvis_drop, 0.0)   # compression is in the knees (above)
		pelvis_x = dyn.pelvis_shift.x + dyn.sway * (1.0 - gw)
		pelvis_z = dyn.pelvis_shift.z
		pelvis_rot = Quaternion(Vector3.UP, -dyn.pelvis_twist * (1.0 - gw))
	if use_gait:
		pelvis_x += gait_pose.pelvis.x * gw
		pelvis_rot = pelvis_rot.slerp(gait_q, gw) if gw > 0.0 else pelvis_rot
	_set_position("pelvis", Vector3(pelvis_x, pelvis_y, pelvis_z))
	_set_rotation("pelvis", pelvis_rot)

	# With the gait model the legs are posed in the world's forward plane whatever the hips do, so the planned feet land
	# where they were planned: the thighs undo the pelvis rotation.
	var leg_frame := Quaternion.IDENTITY.slerp(gait_q.inverse(), gw) if gw > 0.0 else Quaternion.IDENTITY
	_set_rotation("thigh_l", leg_frame * Quaternion(Vector3.RIGHT, thigh_l))
	_set_rotation("thigh_r", leg_frame * Quaternion(Vector3.RIGHT, thigh_r))
	_rot("shin_l", shin_l)
	_rot("shin_r", shin_r)
	_rot("foot_l", foot_l_a)
	_rot("foot_r", foot_r_a)

	# Convention: a positive rotation about X swings a hanging limb forward (-Z). Arms swing opposite to the legs,
	# elbows bend forward, and the arms rise forward when jumping.
	var arm: float = lerpf(0.25, 0.85, gait) * (1.0 - idle) * (float(dyn.arm_scale) if use_dyn else 1.0)
	var arm_l: float = -sin(phase) * arm
	var arm_r: float = -sin(phase + PI) * arm
	var fore := (0.15 + 0.7 * gait) * (1.0 - idle * 0.7)
	var arm_air := lerpf(-0.3, 1.0, (rising + 1.0) / 2.0)
	arm_l = lerpf(arm_l, arm_air, air_blend)
	arm_r = lerpf(arm_r, arm_air, air_blend)
	arm_l = lerpf(arm_l, 0.35, crouch_blend)
	arm_r = lerpf(arm_r, 0.35, crouch_blend)
	var elbow := fore + 0.3 * air_blend + 0.4 * crouch_blend
	var elbow_l := elbow
	var elbow_r := elbow
	if use_gait:
		arm_l = lerpf(arm_l, gait_pose.arm_l, gw)
		arm_r = lerpf(arm_r, gait_pose.arm_r, gw)
		elbow_l = lerpf(elbow_l, gait_pose.elbow_l, gw)
		elbow_r = lerpf(elbow_r, gait_pose.elbow_r, gw)
	_rot("forearm_l", elbow_l)
	_rot("forearm_r", elbow_r)
	var roll_l := 0.10 + 0.5 * air_blend   # + = away from the body
	var roll_r := 0.10 + 0.5 * air_blend
	if use_dyn:
		arm_l += dyn.arm_pitch_l
		arm_r += dyn.arm_pitch_r
		roll_l += dyn.arm_roll_l
		roll_r += dyn.arm_roll_r
	_set_rotation("upper_arm_l", Quaternion(Vector3.RIGHT, arm_l) * Quaternion(Vector3.FORWARD, roll_l))
	_set_rotation("upper_arm_r", Quaternion(Vector3.RIGHT, arm_r) * Quaternion(Vector3.FORWARD, -roll_r))

	var breathing := sin(Time.get_ticks_msec() / 650.0) * 0.012 * idle
	var chest_lean := -(forward_lean + 0.10 * crouch_blend) + breathing
	if use_dyn:
		# pitch + = forward (a negative rotation about X); roll + = to the right and yaw + = to the right (a negative
		# rotation about Y). The spine takes 40 % of the torso motion, the chest 60 % plus the shoulder counter-rotation.
		var roll: float = dyn.torso_roll
		var yaw: float = dyn.torso_yaw
		_set_rotation("spine", Quaternion(Vector3.UP, -yaw * 0.4) * Quaternion(Vector3.RIGHT, chest_lean * 0.4) * Quaternion(Vector3.FORWARD, roll * 0.4))
		_set_rotation("chest", Quaternion(Vector3.UP, -(yaw * 0.6 + dyn.shoulder_twist)) * Quaternion(Vector3.RIGHT, chest_lean * 0.6) * Quaternion(Vector3.FORWARD, roll * 0.6))
		var head_pitch_back: float = -dyn.head_pitch   # compensation tilts the upward-pointing bones backward (+X)
		_set_rotation("neck", Quaternion(Vector3.UP, -dyn.head_yaw * 0.5) * Quaternion(Vector3.RIGHT, head_pitch_back * 0.6) * Quaternion(Vector3.FORWARD, dyn.head_roll * 0.5))
		_set_rotation("head", Quaternion(Vector3.UP, -dyn.head_yaw * 0.5) * Quaternion(Vector3.RIGHT, head_pitch_back * 0.4) * Quaternion(Vector3.FORWARD, dyn.head_roll * 0.5))
	else:
		_set_rotation("spine", Quaternion(Vector3.RIGHT, chest_lean * 0.5) * Quaternion(Vector3.UP, sin(phase) * 0.14 * gait))
		_set_rotation("chest", Quaternion(Vector3.RIGHT, chest_lean * 0.5) * Quaternion(Vector3.UP, -sin(phase) * 0.10 * gait))
		_set_rotation("neck", Quaternion(Vector3.RIGHT, lean * 0.6))
		_set_rotation("head", Quaternion(Vector3.RIGHT, lean * 0.3))
	if gw > 0.0:
		# keep the trunk facing forward whatever the hips do, then turn the shoulders against them. The gait's posture:
		# the lean tilts the whole trunk straight from the waist, the upper back curve bends the chest and neck, and the
		# head turns back by the sum so the face stays level.
		var trunk := trunk_posture(gait_pose, gw)
		_set_rotation("spine", leg_frame * trunk.spine * _rotations.spine)
		_set_rotation("chest", Quaternion(Vector3.UP, float(gait_pose.chest_yaw) * gw) * trunk.chest * _rotations.chest)
		_set_rotation("neck", trunk.neck * _rotations.neck)
		_set_rotation("head", trunk.head * _rotations.head)


## The gait's trunk posture as rotations added at the spine, chest, neck and head joints (weight = how much of the gait applies).
static func trunk_posture(g: Dictionary, weight := 1.0) -> Dictionary:
	var lean: float = float(g.get("torso_lean", 0.0)) * weight
	var curve: float = float(g.get("spine_curve", 0.0)) * weight
	var level: float = float(g.get("head_level", 0.0))
	return {
		"spine": Quaternion(Vector3.RIGHT, -lean), "chest": Quaternion(Vector3.RIGHT, -curve * 0.6),
		"neck": Quaternion(Vector3.RIGHT, -curve * 0.4), "head": Quaternion(Vector3.RIGHT, (lean + curve) * level),
	}


func _rot(bone: String, angle: float) -> void:
	_set_rotation(bone, Quaternion(Vector3.RIGHT, angle))


## Current global height of a bone's joint above the character origin (used by tests and debugging).
func joint_height(bone: String) -> float:
	return skeleton.get_bone_global_pose(bone_index[bone]).origin.y


## Joint position in the character's local space (-Z is forward).
func joint_position(bone: String) -> Vector3:
	return skeleton.get_bone_global_pose(bone_index[bone]).origin


## The end of a limb bone: a point `length` below its joint along the bone (e.g. the wrist for a forearm).
func bone_tip(bone: String, length: float) -> Vector3:
	return skeleton.get_bone_global_pose(bone_index[bone]) * Vector3(0.0, -length, 0.0)
