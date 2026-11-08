## Records the unchanged legacy pipeline at the 3.0 audit speeds, without running movement physics.
## --script res://tools/audit_locomotion.gd -- --out-dir=<absolute directory>
## Native rendering also saves side-view pose sheets; headless saves the same measurements and bone samples.
extends SceneTree

const Treadmill = preload("res://scenes/gait_treadmill.tscn")
const SPEEDS := [0.0, 1.0, 2.0, 4.0, 6.0, 8.0]
const DT := 1.0 / 120.0
const PHASES := 8
const TILE := Vector2i(320, 240)

var scene
var output := ""
var caption: Label


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out-dir="):
			output = arg.trim_prefix("--out-dir=")
	if output.is_empty() or not output.is_absolute_path():
		push_error("audit_locomotion requires --out-dir=<absolute directory>")
		quit(1)
		return
	var error := DirAccess.make_dir_recursive_absolute(output)
	if error != OK:
		push_error("Cannot create audit output: %s" % error_string(error))
		quit(1)
		return
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(960, 720)
	scene = Treadmill.instantiate()
	scene.options = {"no-tuning": "true", "no-hardware": "true", "no-window-state": "true", "view": "side-left"}
	root.add_child(scene)
	await process_frame
	scene.set_process(false)
	scene.view_controls.hide()
	scene.overlay.hide()
	scene.rig_editor.hide()
	scene.path_editor.hide()
	scene.model.rig = null
	scene.visual.apply_rig(null)
	caption = Label.new()
	caption.position = Vector2(16, 16)
	caption.add_theme_font_size_override("font_size", 28)
	root.add_child(caption)
	var report := {"engine": Engine.get_version_info().string, "rig": "original Playground primitives",
		"dt": DT, "physics": "not simulated; steady straight belt-relative diagnostic", "cases": []}
	for running in [false, true]:
		var sheet := Image.create_empty(TILE.x * PHASES, TILE.y * SPEEDS.size(), false, Image.FORMAT_RGBA8)
		var mode := "run" if running else "walk"
		scene.gait_params.set_value("run_mode", 1.0 if running else 0.0)
		for row in SPEEDS.size():
			var speed: float = SPEEDS[row]
			scene.model.phase = 0.0
			scene.dynamics.reset()
			for i in 240:
				_pose(speed, DT)
			var metrics := _measure(speed)
			metrics["mode"] = mode
			metrics["speed_mps"] = speed
			metrics["poses"] = []
			for col in PHASES:
				var phase := float(col) / PHASES
				var rate: float = scene.model.cycle.rate
				if rate > 0.0:
					var remaining := fposmod(phase - scene.model.phase, 1.0) / rate
					while remaining > DT:
						_pose(speed, DT)
						remaining -= DT
					_pose(speed, remaining)
				scene.model.phase = phase
				_pose(speed, 0.0)
				var bones := {}
				for bone in scene.visual.bone_index:
					var p: Vector3 = scene.visual.joint_position(bone)
					bones[bone] = [p.x, p.y, p.z]
				metrics.poses.append({"phase": phase, "joints_m": bones})
				if DisplayServer.get_name() != "headless":
					caption.text = "LEGACY %s | %.0f m/s | phase %.3f" % [mode.to_upper(), speed, phase]
					await process_frame
					await RenderingServer.frame_post_draw
					var image := root.get_texture().get_image()
					image.resize(TILE.x, TILE.y, Image.INTERPOLATE_LANCZOS)
					image.convert(Image.FORMAT_RGBA8)
					sheet.blit_rect(image, Rect2i(Vector2i.ZERO, TILE), Vector2i(col * TILE.x, row * TILE.y))
			report.cases.append(metrics)
			print("%s %.0f m/s: cadence %.1f steps/min, support slip %.4f m/s, min sole %.4f m" % [
				mode, speed, metrics.cadence_spm, metrics.max_support_slip_mps, metrics.minimum_sole_m])
		if DisplayServer.get_name() != "headless":
			var error := sheet.save_png(output.path_join("legacy_%s.png" % mode))
			if error != OK:
				push_error("Cannot save pose sheet: %s" % error_string(error))
				quit(1)
				return
	var file := FileAccess.open(output.path_join("legacy_metrics.json"), FileAccess.WRITE)
	if file == null:
		push_error("Cannot write audit metrics: %s" % error_string(FileAccess.get_open_error()))
		quit(1)
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	scene.queue_free()
	caption.queue_free()
	await process_frame
	quit(0)


func _pose(speed: float, dt: float) -> void:
	var pose: Dictionary = scene.model.update(dt, speed)
	var dynamics: Dictionary = scene.dynamics.update(dt, {"velocity": Vector3(0, 0, -speed), "accel": Vector3.ZERO,
		"heading": 0.0, "grounded": true, "gait_phase": pose.phase * TAU, "gait_amount": pose.gait_amount})
	scene.visual.update_pose({"speed": speed, "vy": 0.0, "grounded": true, "crouching": false,
		"heading": 0.0, "accel_forward": 0.0, "gait": pose, "dyn": dynamics}, dt)


func _measure(speed: float) -> Dictionary:
	var previous: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
	var valid := [false, false, false, false]
	var slip := 0.0
	var floor_min := INF
	var support_samples := 0
	var frames := maxi(240, int(ceil(2.0 / maxf(scene.model.cycle.rate, 0.1) / DT)))
	for i in frames:
		_pose(speed, DT)
		var c: Dictionary = scene.model.cycle
		for side in 2:
			var suffix := "l" if side == 0 else "r"
			var transform: Transform3D = scene.visual.skeleton.get_bone_global_pose(scene.visual.bone_index["foot_" + suffix])
			for k in 2:
				var index := side * 2 + k
				var point := transform * Vector3(0, -c.ankle_h, -c.heel.x if k == 0 else -c.toe.x)
				floor_min = minf(floor_min, point.y)
				var planted: bool = scene.model.pose["contact_" + suffix] and point.y < 0.002
				if planted and valid[index]:
					slip = maxf(slip, absf((point.z - previous[index].z) / DT - speed))
					support_samples += 1
				previous[index] = point
				valid[index] = planted
	var cycle: Dictionary = scene.model.cycle
	return {"cadence_spm": cycle.rate * 120.0, "stride_m": cycle.stride, "stance_fraction": cycle.d,
		"minimum_sole_m": floor_min, "max_support_slip_mps": slip, "support_samples": support_samples}
