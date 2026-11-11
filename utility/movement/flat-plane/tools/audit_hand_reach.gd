## Measures the mannequin's arms for hanging (Movement Lab 5.4): rest positions of the arm chain, the overhead reach
## (soles to the fingertips with the arm straight up), and the hand mesh's extent along each bone axis, so the grip
## can put the palm on the lip and the fingers over it.
##   godot --headless --path utility/movement/flat-plane --script res://tools/audit_hand_reach.gd
extends SceneTree

const Visual = preload("res://character/authored_mannequin.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var visual = Visual.new()
	root.add_child(visual)
	await process_frame
	var sk: Skeleton3D = visual.skeleton
	var index: Dictionary = visual.bone_index
	print("skeleton scale %s  proportion %.4f" % [sk.global_transform.basis.get_scale(), visual.proportion_scale])
	for side in ["Left", "Right"]:
		var names := [side + "Shoulder", side + "UpperArm", side + "LowerArm", side + "Hand"]
		var pts := []
		for n in names:
			var p: Vector3 = sk.global_transform * sk.get_bone_global_rest(index[n]).origin
			pts.append(p)
			print("%-14s rest %s" % [n, p])
		var upper: float = pts[1].distance_to(pts[2])
		var lower: float = pts[2].distance_to(pts[3])
		print("%s upper %.3f lower %.3f" % [side, upper, lower])
		var hand: Transform3D = sk.global_transform * sk.get_bone_global_rest(index[side + "Hand"])
		print("%s hand rest basis x %s y %s z %s" % [side, hand.basis.x.normalized(), hand.basis.y.normalized(), hand.basis.z.normalized()])
		# The hand mesh: its vertices in the hand bone's frame.
		for att in sk.get_children():
			if att is BoneAttachment3D and att.bone_name == side + "Hand":
				for mi in att.get_children():
					if mi is MeshInstance3D:
						var aabb: AABB = mi.mesh.get_aabb()
						var lo := Vector3(INF, INF, INF)
						var hi := -lo
						for corner in 8:
							var c: Vector3 = aabb.get_endpoint(corner)
							var w: Vector3 = mi.global_transform * c
							var local: Vector3 = hand.affine_inverse() * w
							lo = lo.min(local)
							hi = hi.max(local)
						print("%s hand mesh in bone frame: min %s max %s" % [side, lo, hi])
		var head: Vector3 = sk.global_transform * sk.get_bone_global_rest(index["Head"]).origin
		print("head bone %.3f" % head.y)
		var shoulder_y: float = pts[1].y
		print("%s overhead reach to wrist %.3f (shoulder %.3f + arm %.3f)" % [side, shoulder_y + upper + lower, shoulder_y, upper + lower])
	visual.free()
	quit(0)
