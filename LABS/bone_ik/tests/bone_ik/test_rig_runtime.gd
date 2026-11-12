## The live rig: modifier chain order, stage diagnostics, manual and neutral poses, limits, rebuilds, interfaces.
extends RefCounted

const Rig = preload("res://systems/bone_ik/vitruvian_rig.gd")
const Proportions = preload("res://systems/bone_ik/rig/proportions.gd")

var _tree: SceneTree
var rig


func before_each() -> void:
	_tree = Engine.get_main_loop()
	rig = Rig.new()
	_tree.root.add_child(rig)
	await _tree.process_frame


func after_each() -> void:
	rig.queue_free()
	await _tree.process_frame


## One real frame: the skeleton processes its modifiers in its own deferred update (idle callback mode).
func _step() -> void:
	await _tree.process_frame
	await _tree.process_frame


func test_modifier_chain_order(t) -> void:
	var names := []
	for c in rig.skeleton.get_children():
		names.append(String(c.name))
	t.eq(names, ["PoseSource", "ProbeAnimation", "ProbeIK", "HingeAlign", "JointLimits", "TwistHelpers", "ProbeFinal"],
		"animation/pose source -> probe -> (IK slot) -> probe -> hinge align -> limits -> helpers -> probe")


func test_rest_and_neutral_poses(t) -> void:
	rig.set_mode(Rig.Mode.REST)
	await _step()
	var g: Array[Transform3D] = rig.stage_globals("final")
	var worst := 0.0
	for b in rig.definition.bones:
		worst = maxf(worst, g[rig.definition.index[b.name]].origin.distance_to(b.global.origin))
	t.ok(worst < 1e-5, "T-pose equals the rest definition (%.7f m)" % worst)
	rig.set_mode(Rig.Mode.NEUTRAL)
	await _step()
	g = rig.stage_globals("final")
	var hand: Vector3 = g[rig.definition.index.LeftHand].origin
	t.ok(hand.y < 1.0 and absf(hand.x) < 0.35, "neutral stance: the hand hangs beside the thigh (%s)" % hand)
	t.near(rig.get_joint_angles("LeftLowerArm").x, 12.0, 1e-3, "neutral elbow flexion as specified")


func test_manual_pose_is_limited_and_stages_are_distinguished(t) -> void:
	rig.set_joint_angles("LeftLowerLeg", Vector3(-40, 0, 0))   # knee hyperextension, impossible
	rig.set_joint_angles("LeftUpperArm", Vector3(120, 0, 0))   # a legal shoulder flexion
	await _step()
	t.eq(rig.mode, Rig.Mode.MANUAL, "manual mode")
	t.near(rig.get_joint_angles("LeftLowerLeg", "animation").x, -40.0, 1e-3, "the incoming (animation stage) pose is kept for diagnostics")
	t.near(rig.get_joint_angles("LeftLowerLeg", "final").x, -6.0, 1e-3, "the final pose is clamped to the hard limit")
	t.near(rig.get_joint_angles("LeftUpperArm", "final").x, 120.0, 1e-3, "legal angles pass unchanged")
	var state: Dictionary = rig.pose_state()
	t.ok(state.violating_joints >= 1 and state.worst_violation_bone == "LeftLowerLeg", "pose state reports the violation (%s)" % state.worst_violation_bone)
	t.near(state.joints.LeftLowerLeg.incoming_beyond_hard_deg, 34.0, 1e-3, "violation measured in degrees")
	rig.set_limits_enforced(false)
	await _step()
	t.near(rig.get_joint_angles("LeftLowerLeg", "final").x, -40.0, 1e-3, "measure-only mode leaves the pose alone")


func test_twist_helpers_follow_forearm_rotation(t) -> void:
	rig.set_joint_angles("LeftHand", Vector3(0, 0, 0))
	rig.set_joint_angles("LeftLowerArm", Vector3(0, 0, 60))   # pronation on the forearm joint
	await _step()
	var sk: Skeleton3D = rig.skeleton
	var helper := sk.find_bone("LeftUpperArmTwist")
	# Modifier output exists only inside the update; the final probe holds it (get_bone_pose_* returns the input).
	t.ok(rig.probe_final.rotations[helper].get_angle() < 1e-3, "no upper-arm twist -> helper at rest")
	rig.set_joint_angles("LeftUpperArm", Vector3(0, 0, 40))
	await _step()
	t.near(rad_to_deg(rig.probe_final.rotations[helper].get_angle()), 20.0, 0.05, "upper-arm helper counter-rotates half the twist")
	var fore := sk.find_bone("LeftLowerArmTwist")
	rig.set_joint_angles("LeftHand", Vector3(0, 0, 16))
	await _step()
	t.near(rad_to_deg(rig.probe_final.rotations[fore].get_angle()), 8.0, 0.05, "forearm helper carries half the hand twist")


func test_animation_mode_runs_through_the_chain(t) -> void:
	t.ok(rig.play("Jog_Fwd", 0.2), "clip plays")
	rig.player.seek(0.2, true)
	await _step()
	var s: Dictionary = rig.pose_state()
	t.eq(s.mode, "Imported animation", "mode")
	t.ok(absf(s.hinge_transfer_deg.LeftLowerArm) + absf(s.hinge_transfer_deg.RightLowerArm) > 1.0, "hinge alignment active on the elbows (%s)" % [s.hinge_transfer_deg])
	t.eq(s.violating_joints, 0, "no joint beyond its hard limit after alignment")
	var a: Array[Transform3D] = rig.stage_globals("animation")
	var f: Array[Transform3D] = rig.stage_globals("final")
	var hand: int = rig.definition.index.LeftHand
	t.ok(a[hand].origin.distance_to(f[hand].origin) < 1e-4, "alignment changes no joint position")


func test_rebuild_with_new_proportions_keeps_playing(t) -> void:
	rig.play("Walk")
	rig.player.seek(0.4, true)
	var p := Proportions.new({"height": 1.62, "arm_span_ratio": 1.06})
	rig.build(p)
	await _step()
	t.eq(rig.mode, Rig.Mode.ANIMATION, "still animating")
	t.ok(rig.player.is_playing() and rig.player.current_animation == "Walk", "same clip")
	t.near(rig.definition.measurements.stature, 1.62, 1e-6, "new stature")
	t.eq(rig.skeleton.get_bone_count(), 29, "same skeleton layout")


func test_reserved_interfaces(t) -> void:
	t.eq(rig.request_ik_target("left_hand", Transform3D.IDENTITY, 0.5), ERR_UNAVAILABLE, "IK requests are reserved for phase 2")
	t.ok(rig.ik_requests.has("left_hand"), "the request is stored")
	t.eq(rig.apply_impact("Head", Vector3(0, 0, -50), Vector3.ZERO), ERR_UNAVAILABLE, "impacts are reserved for phase 3")
	t.eq(rig.set_response_state("full_ragdoll"), ERR_UNAVAILABLE, "only the animated state exists")
	t.eq(rig.set_response_state("animated"), OK, "animated state")
	t.eq(Rig.VERSION, "0.1.0", "system version")
