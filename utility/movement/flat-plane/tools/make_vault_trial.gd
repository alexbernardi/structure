## Writes the deterministic input recording for the vault A/B (locomotion_comparison --trial=vault). It never changes
## controller code or defaults: stand, run down the lane at the default running speed, stop.
extends SceneTree


func _initialize() -> void:
	var frames := []
	var yaw := -PI / 2.0   # the vault lanes run toward +X
	for i in 60:
		frames.append([0.0, 0.0, yaw, false, false, false, false])
	for i in 840:
		frames.append([0.0, 1.0, yaw, false, false, false, false])
	for i in 120:
		frames.append([0.0, 0.0, yaw, false, false, false, false])
	var file := FileAccess.open("res://config/vault_trial.json", FileAccess.WRITE)
	if file == null:
		push_error("Cannot save vault input recording: %s" % error_string(FileAccess.get_open_error()))
		quit(1)
		return
	file.store_string(JSON.stringify({"schema": 1, "hz": 120, "lane": "a",
		"fields": ["move_x", "move_y", "yaw", "sprint", "jump_pressed", "jump_held", "crouch"],
		"description": "Stand, run 7 s down a vault-course lane at the default running speed, stop. Same frames and physics parameters for A and B.",
		"frames": frames}))
	file.close()
	print("Recorded ", frames.size(), " shared vault-trial input frames at 120 Hz")
	quit(0)
