## Authored pose/contact diagnostic. Constant straight displacement, not a substitute for collision-body trials.
extends SceneTree

const Reference = preload("res://scenes/animation_reference.tscn")
const Animator = preload("res://animation/authored_animation.gd")
const Params = preload("res://animation/locomotion_params.gd")
const DT := 1.0 / 120.0
const SPEEDS := [0.0, 1.0, 2.0, 4.0, 6.0, 8.0, 12.0]
var output := ""
var scene
var visual
var animator
var params
var camera: Camera3D


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out-dir="):
			output = arg.trim_prefix("--out-dir=")
	if not output.is_absolute_path() or DirAccess.make_dir_recursive_absolute(output) != OK:
		push_error("audit_authored_locomotion requires a writable absolute --out-dir")
		quit(1)
		return
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(960, 720)
	scene = Reference.instantiate()
	scene.options = {"mannequin": "true"}
	root.add_child(scene)
	await process_frame
	scene.set_process(false)
	scene.get_node("HUD/Panel/Controls/Clip").hide()
	scene.player.stop()
	visual = scene.skeleton.get_parent()
	params = Params.create()
	camera = scene.find_children("*", "Camera3D", true, false)[0]
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var report := {"dt": DT, "diagnostic": "straight belt displacement; actual rendered shoe corners; support = corner below 3 cm for consecutive samples", "cases": [], "jump_start": []}
	for clip in ["Jump_Start", "Jump_Land"]:
		scene.player.active = true
		for i in 21:
			var time: float = i / 20.0 * scene.player.get_animation(clip).length
			scene.player.play(clip)
			scene.player.seek(time, true)
			scene.player.advance(0.0)
			var hip: Vector3 = scene.skeleton.get_bone_global_pose(visual.bone_index.Hips).origin
			report.jump_start.append({"clip": clip, "time": time, "hip_y": hip.y})
	scene.player.stop()
	scene.player.active = false
	visual.skeleton.reset_bone_poses()
	animator = Animator.new()
	visual.add_child(animator)
	animator.setup(visual, params)
	for ik_enabled in [false, true]:
		params.set_value("foot_ik", 1.0 if ik_enabled else 0.0)
		var sheet := Image.create_empty(320 * 8, 240 * SPEEDS.size(), false, Image.FORMAT_RGBA8)
		for row in SPEEDS.size():
			var speed: float = SPEEDS[row]
			var previous := {}
			var slip: Array[float] = []
			var floor_min := INF
			var max_correction := 0.0
			var capture := 0
			for i in 600:
				visual.position.z = -speed * DT * i
				scene.get_node("Floor").position.z = visual.position.z
				animator.update(DT, {"speed": speed, "grounded": true, "vy": 0.0, "heading": 0.0, "teleported": i == 0})
				camera.position.z = visual.position.z
				camera.look_at(visual.position + Vector3.UP)
				scene.readout.text = "AUTHORED %.0f m/s | rate %.2fx | IK %s" % [speed, animator.model.cadence, "on" if ik_enabled else "off"]
				await process_frame
				if DisplayServer.get_name() != "headless":
					await RenderingServer.frame_post_draw
				if i < 120:
					continue
				for side in ["Left", "Right"]:
					var pose: Transform3D = animator.final_feet[side]
					for j in 4:
						var point: Vector3 = visual.to_global(pose * visual.sole_points[side][j])
						floor_min = minf(floor_min, point.y)
						var key: String = side + str(j)
						if previous.has(key) and point.y < 0.03 and previous[key].y < 0.03:
							slip.append(Vector2(point.x - previous[key].x, point.z - previous[key].z).length() / DT)
						previous[key] = point
				max_correction = maxf(max_correction, animator.max_correction)
				if i >= 120 + capture * 12 and capture < 8 and DisplayServer.get_name() != "headless":
					var image := root.get_texture().get_image()
					image.resize(320, 240, Image.INTERPOLATE_LANCZOS)
					image.convert(Image.FORMAT_RGBA8)
					sheet.blit_rect(image, Rect2i(0, 0, 320, 240), Vector2i(capture * 320, row * 240))
					capture += 1
			slip.sort()
			var result := {"speed": speed, "ik": ik_enabled, "minimum_sole": floor_min, "support_samples": slip.size(),
				"slip_p95": slip[int(slip.size() * 0.95)] if not slip.is_empty() else 0.0, "max_correction": max_correction,
				"cadence": animator.model.cadence, "stride": animator.model.stride}
			report.cases.append(result)
			print(JSON.stringify(result))
		if DisplayServer.get_name() != "headless":
			var error := sheet.save_png(output.path_join("authored_run.png" if ik_enabled else "authored_ik_off.png"))
			if error != OK:
				push_error("Authored sheet capture failed: %s" % error_string(error))
	var file := FileAccess.open(output.path_join("authored_metrics.json"), FileAccess.WRITE)
	if file == null:
		push_error("Cannot save authored audit: %s" % error_string(FileAccess.get_open_error()))
		quit(1)
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	scene.queue_free()
	await process_frame
	quit(0)
