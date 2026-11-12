## Lossless axial alignment before the limits (JointProfile.align_axial):
##   * elbows / knees: rotation about the upper arm / thigh axis leaves the hinge and becomes that segment's roll;
##   * wrists: forearm rotation stored on the hand becomes the forearm's roll (pronation / supination).
## No joint moves; authored poses are then judged anatomically (a hinge cannot bend sideways, a wrist barely twists).
extends SkeletonModifier3D

var profile
var hinges := true
var forearms := true
var transferred := {}   ## child bone -> radians moved to its parent on the last update


func _process_modification_with_delta(_delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null or profile == null:
		return
	var r: Dictionary = profile.align_axial({}, skeleton.get_bone_pose_rotation, hinges, forearms)
	transferred = r.transfers
	for i in r.locals:
		skeleton.set_bone_pose_rotation(i, r.locals[i])
