## Smoke test of the visual laboratory scene (headless): it builds, switches modes and cameras, rebuilds on a
## proportion edit, and draws a frame without engine errors. Looks are judged by a human (see BONE-IK-LAB.md).
extends RefCounted

const Scene = preload("res://scenes/vitruvian_lab.tscn")
const Rig = preload("res://systems/bone_ik/vitruvian_rig.gd")

var _tree: SceneTree
var lab


func before_each() -> void:
	_tree = Engine.get_main_loop()
	lab = Scene.instantiate()
	_tree.root.add_child(lab)
	await _tree.process_frame
	await _tree.process_frame


func after_each() -> void:
	lab.queue_free()
	await _tree.process_frame


func test_scene_builds_the_rig_and_its_views(t) -> void:
	t.ok(lab.rig != null and lab.rig.skeleton.get_bone_count() == 29, "rig built")
	t.ok(lab.view._bones.size() == 28 and lab.view._joints.size() == 22, "a bone per segment, a sphere per joint")
	t.ok(lab.rig.clips().size() > 40, "authored clips listed (%d)" % lab.rig.clips().size())
	t.ok(lab._readout.text.contains("stature 1.800 m"), "measurement readout")


func test_modes_cameras_and_overlays(t) -> void:
	for m in [Rig.Mode.NEUTRAL, Rig.Mode.ANIMATION, Rig.Mode.MANUAL, Rig.Mode.REST]:
		lab._set_mode(m)
		await _tree.process_frame
		t.eq(lab.rig.mode, m, "mode %s" % Rig.MODE_NAMES[m])
	for c in ["side", "persp", "front"]:
		lab._set_camera(c)
		t.eq(lab.cam_mode, c, "camera %s" % c)
	lab.view.show_axes = true
	lab.view.show_rest_ghost = true
	lab._select_joint("RightUpperLeg")
	await _tree.process_frame
	t.eq(lab.view.selected, "RightUpperLeg", "joint selection")


func test_manual_slider_poses_the_selected_joint(t) -> void:
	lab._select_joint("LeftLowerLeg")
	lab._joint_sliders[0].value = 70.0
	await _tree.process_frame
	await _tree.process_frame
	t.eq(lab.rig.mode, Rig.Mode.MANUAL, "slider switches to manual")
	t.near(lab.rig.get_joint_angles("LeftLowerLeg").x, 70.0, 1e-3, "knee at 70 degrees")


func test_proportion_edit_rebuilds_everything(t) -> void:
	lab._prop_sliders["height"].value = 1.55
	await _tree.process_frame
	await _tree.process_frame
	t.near(lab.rig.definition.measurements.stature, 1.55, 1e-3, "rig rebuilt at the new stature")
	t.eq(lab.view._bones.size(), 28, "views rebuilt")
	lab._apply_preset("vitruvian")
	await _tree.process_frame
	await _tree.process_frame
	t.near(lab.rig.definition.measurements.arm_span, lab.rig.definition.measurements.stature, 1e-6, "Vitruvian preset applied")
