extends RefCounted

## The gait pose through the real skeleton: the model plans ankle positions, the visual poses bones from angles; these
## tests close the loop by reading the bones back.

const Visual = preload("res://character/character_visual.gd")
const GaitParams = preload("res://animation/gait_params.gd")
const GaitModel = preload("res://animation/gait_model.gd")

var _tree: SceneTree
var _v
var _p
var _m


func before_each() -> void:
	_tree = Engine.get_main_loop()
	_v = Visual.new()
	_tree.root.add_child(_v)
	await _tree.process_frame
	_p = GaitParams.create()
	_m = GaitModel.new(_p)


func after_each() -> void:
	_v.queue_free()
	await _tree.process_frame
	_v = null
	_m = null
	_p = null


func _pose(q: float, speed: float) -> Dictionary:
	_m.cycle = _m.cycle_for(speed)
	var pose: Dictionary = _m.pose_at(q)
	_v.update_pose({"speed": speed, "grounded": true, "gait": pose}, 1.0 / 60.0)
	return pose


func _lowest_sole(side: String) -> float:
	var fp: Transform3D = _v.skeleton.get_bone_global_pose(_v.bone_index["foot_" + side])
	var heel: Vector3 = fp * Vector3(0.0, -GaitModel.ANKLE_H, -GaitModel.HEEL.x)
	var toe: Vector3 = fp * Vector3(0.0, -GaitModel.ANKLE_H, -GaitModel.TOE.x)
	return minf(heel.y, toe.y)


func test_the_posed_ankles_are_where_the_model_planned(t) -> void:
	var worst := 0.0
	for speed in [0.6, 1.2, 1.8]:
		for i in 24:
			var pose := _pose(float(i) / 24.0, speed)
			for side in ["l", "r"]:
				var sx := -1.0 if side == "l" else 1.0
				var hip: Vector3 = Vector3(pose.pelvis.x, pose.pelvis.y, pose.pelvis.z) + pose.pelvis_q * Vector3(sx * GaitModel.HIP_X, -GaitModel.HIP_DROP, 0.0)
				var reach := GaitModel.leg_reach(pose["thigh_" + side], pose["knee_" + side])
				var expected := hip + Vector3(0.0, reach.y, -reach.x)
				worst = maxf(worst, expected.distance_to(_v.joint_position("foot_" + side)))
	t.eq(_v.gait_weight, 1.0, "the gait model owns the legs while walking on the ground")
	t.ok(worst < 2e-4, "3 speeds x 24 phases x 2 feet: the skeleton's ankle is within %s m of the plan" % worst)


func test_the_posed_feet_stand_on_the_ground(t) -> void:
	var sunk := 0.0
	var planted_error := 0.0
	var planted := 0
	for i in 48:
		var pose := _pose(float(i) / 48.0, 1.2)
		for side in ["l", "r"]:
			var low := _lowest_sole(side)
			sunk = maxf(sunk, -low)
			if pose["contact_" + side]:
				planted_error = maxf(planted_error, absf(low))
				planted += 1
	t.ok(sunk < 5e-4, "no sole sinks into the ground: deepest %s m" % sunk)
	t.ok(planted > 40 and planted_error < 5e-4, "and the %d planted feet touch it: worst gap %s m" % [planted, planted_error])


func test_pelvis_rotation_does_not_swing_the_feet_sideways(t) -> void:
	_p.set_value("pelvis_rotation", 15.0)
	_p.set_value("pelvic_tilt", 12.0)
	var worst := 0.0
	for i in 24:
		var pose := _pose(float(i) / 24.0, 1.4)
		for side in ["l", "r"]:
			var sx := -1.0 if side == "l" else 1.0
			var hip: Vector3 = Vector3(pose.pelvis.x, pose.pelvis.y, 0.0) + pose.pelvis_q * Vector3(sx * GaitModel.HIP_X, -GaitModel.HIP_DROP, 0.0)
			worst = maxf(worst, absf(_v.joint_position("foot_" + side).x - hip.x))
	t.ok(worst < 2e-4, "the legs stay in the forward plane whatever the hips do (max 15 deg yaw, 12 deg tilt): %s m" % worst)


func test_the_trunk_keeps_facing_forward_while_the_shoulders_counter_rotate(t) -> void:
	_p.set_value("pelvis_rotation", 12.0)
	_p.set_value("shoulder_counter", 20.0)
	var pose := _pose(0.0, 1.4)
	var spine: Quaternion = _v.skeleton.get_bone_global_pose(_v.bone_index.spine).basis.get_rotation_quaternion()
	var chest: Quaternion = _v.skeleton.get_bone_global_pose(_v.bone_index.chest).basis.get_rotation_quaternion()
	var spine_f: Vector3 = spine * Vector3.FORWARD
	var chest_f: Vector3 = chest * Vector3.FORWARD
	var spine_yaw := atan2(-spine_f.x, -spine_f.z)   # the skeleton's yaw convention: positive = turned to the left
	var chest_yaw := atan2(-chest_f.x, -chest_f.z)
	t.ok(absf(spine_yaw) < 0.03, "the spine is not turned by the hips (%s rad)" % spine_yaw)
	t.near(chest_yaw, pose.chest_yaw, 0.03, "the chest turns by the counter-rotation: %s vs %s" % [chest_yaw, pose.chest_yaw])
	t.ok(chest_yaw > 0.05 and pose.pelvis_yaw < -0.05, "against the pelvis, which leads with the left hip")


func test_the_gait_pose_fades_out_in_the_air_and_when_crouching(t) -> void:
	var pose := _pose(0.2, 1.4)
	t.eq(_v.gait_weight, 1.0, "walking")
	for i in 30:
		_v.update_pose({"speed": 1.4, "grounded": false, "vy": 2.0, "gait": pose}, 1.0 / 60.0)
	t.eq(_v.gait_weight, 0.0, "airborne: the simple jump pose takes over completely")
	for i in 30:
		_v.update_pose({"speed": 1.4, "grounded": true, "gait": pose}, 1.0 / 60.0)
	t.eq(_v.gait_weight, 1.0, "back on the ground")
	for i in 30:
		_v.update_pose({"speed": 1.4, "grounded": true, "crouching": true, "gait": pose}, 1.0 / 60.0)
	t.eq(_v.gait_weight, 0.0, "crouching hands the legs back too")


func test_without_a_gait_pose_nothing_changes(t) -> void:
	var other := Visual.new()
	_tree.root.add_child(other)
	await _tree.process_frame
	var state := {"speed": 3.0, "grounded": true, "heading": 0.0}
	for i in 20:
		_v.update_pose(state, 1.0 / 60.0)
		other.update_pose(state.merged({"gait": {"active": false}}), 1.0 / 60.0)
	t.eq(_v.gait_weight, 0.0, "no weight")
	t.eq(other.gait_weight, 0.0, "an inactive pose has no weight either")
	for bone in ["thigh_l", "shin_r", "foot_l", "pelvis", "chest", "upper_arm_r"]:
		t.eq(_v.skeleton.get_bone_pose_rotation(_v.bone_index[bone]), other.skeleton.get_bone_pose_rotation(other.bone_index[bone]), "%s identical" % bone)
	other.queue_free()
