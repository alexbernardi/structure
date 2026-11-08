## Writes an explicit, deterministic input recording for side-view A/B. It never changes controller code or defaults.
extends SceneTree


func _initialize() -> void:
	var frames := []
	for speed in [0.0, 1.0, 2.0, 4.0, 6.0, 8.0]:
		for i in 360:
			frames.append([0.0, speed / (12.0 if speed > 6.0 else 6.0), 0.0, speed > 6.0, false, false, false])
	for i in 360:
		frames.append([0.0, 1.0, float(i) / 120.0, false, i == 120, i >= 120 and i < 145, false])
	for i in 120:
		frames.append([0.0, 0.0, 3.0, false, false, false, false])
	for i in 240:
		frames.append([0.0, 1.0, 3.0, false, false, false, true])
	for i in 120:
		frames.append([0.0, 0.0, 3.0, false, false, false, false])
	var file := FileAccess.open("res://config/locomotion_trial.json", FileAccess.WRITE)
	if file == null:
		push_error("Cannot save locomotion input recording: %s" % error_string(FileAccess.get_open_error()))
		quit(1)
		return
	file.store_string(JSON.stringify({"schema": 1, "hz": 120, "fields": ["move_x", "move_y", "yaw", "sprint", "jump_pressed", "jump_held", "crouch"],
		"description": "0,1,2,4,6,8 m/s targets; turning/jumping; stop; crouch; stop. Same frames and physics parameters for A and B.",
		"frames": frames}))
	file.close()
	print("Recorded ", frames.size(), " shared input frames at 120 Hz")
	quit(0)
