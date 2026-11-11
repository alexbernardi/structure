## Native visual check of a traversal move: runs the Playground with a scripted press, in the side view, and saves
## frames while the move presents. Needs a rendering window (not --headless).
##   godot --path utility/movement/flat-plane --script res://tools/capture_traversal.gd -- --case=mantle --out=<dir>
## Cases: mantle (lane E 2.5 m block), grab (lane E 1.9 m ledge, jump + hold), vault (lane A first wall),
##        late (lane A, late press), cyber (lane A 1.6 m wall with the cybernetic legs)
extends SceneTree

const Scene = preload("res://scenes/flat_plane.tscn")
const RUN_YAW := -PI / 2.0

var scene
var case_name := "mantle"
var out_dir := ""
var ticks := 0
var pressed := false
var holding := false
var shots := 0
var last_shot := -1.0
var done_at := -1
var shot_vault := -1


func _initialize() -> void:
	for raw in OS.get_cmdline_user_args():
		var a := String(raw)
		if a.begins_with("--case="):
			case_name = a.substr(7)
		elif a.begins_with("--out="):
			out_dir = a.substr(6)
	scene = Scene.instantiate()
	scene.options = {"no-capture": "true", "no-hardware": "true", "no-window-state": "true", "tuning-state": "", "traversal-debug": "true", "no-tuning": "true",
		"landmark": {"mantle": "lane_e", "grab": "lane_e_ledge", "vault": "vault_a", "late": "vault_a", "cyber": "vault_a",
			"rhythm": "lane_d", "angled": "lane_h_walls", "bar": "lane_f_bar", "catch": "lane_e_ledge",
			"hang": "lane_j", "fence": "lane_i", "slide": "lane_k"}.get(case_name, "lane_e")}
	if case_name == "cyber":
		scene.options["profile"] = "cyber"
	root.add_child(scene)
	scene.live = Feed.new(self)   # the scene ticks itself exactly as in play; only the input source is scripted
	process_frame.connect(_frame)


class Feed:
	extends RefCounted
	var tool

	func _init(owner) -> void:
		tool = owner

	func sample(_yaw: float) -> Dictionary:
		return tool._next_input()


func _next_input() -> Dictionary:
	ticks += 1
	if ticks == 2:
		if case_name == "cyber":
			scene.body.teleport(Vector3(11.0, 0.05, -25.0))
		if case_name == "hang":
			scene.body.teleport(Vector3(45.0, 0.05, -61.0))
		if case_name == "fence":
			scene.body.teleport(Vector3(52.0, 0.05, -55.0))
		scene.toggle_side_view()
		# A close outside view between the lanes (lanes are 6 m apart), like the 4.0 lane C view.
		scene._side_offset = Vector3(0.0, 0.0, -3.4) if case_name in ["mantle", "grab"] else Vector3(0.0, 0.0, 4.0)
		scene._side_cam.fov = 60.0
	var input := {"move": Vector2(0, 1), "yaw": RUN_YAW, "sprint": false, "jump_pressed": false, "jump_held": holding}
	var x: float = scene.body.global_position.x
	var press := false
	match case_name:
		"mantle":
			press = x > 39.0
		"grab":
			press = x > 57.6
		"vault", "cyber", "rhythm", "angled":
			press = not scene.vault.opportunity.is_empty() and scene.vault.phase == scene.vault.Phase.IDLE
			if press:
				input.jump_pressed = true
				input.jump_held = true
				pressed = true
				return input
		"bar":
			# jump at the wall (missed window), then catch its top in the air
			if not pressed and x > 38.9:
				pressed = true
				input.jump_pressed = true
				return input
			if pressed and not holding and not scene.body.core.grounded:
				holding = true
				input.jump_pressed = true
				return input
			return input
		"hang":
			# jump at the 2.6 m wall, hang on contact for 0.5 s, then one press pulls up
			if not pressed and x > 48.4:
				pressed = true
				input.jump_pressed = true
				return input
			if pressed and not holding and scene.traversal.mantle.hanging() and scene.traversal.mantle._hang_time > 0.5:
				holding = true
				input.jump_pressed = true
			return input
		"fence":
			# the 60 degree fence (centre x 58): press near it
			var gap: float = absf((scene.body.global_position - Vector3(58, 0, -55)).dot(Vector3(-1, 0, 0).rotated(Vector3.UP, deg_to_rad(60.0))))
			if not pressed and gap < 0.9:
				pressed = true
				input.jump_pressed = true
			return input
		"slide":
			input.sprint = true
			input["crouch"] = x > 44.0
			pressed = pressed or scene.traversal.sliding
			return input
		"catch":
			if not pressed and x > 57.6:
				pressed = true
				input.jump_pressed = true
				return input
			if pressed and not holding and scene.body.velocity.y < -1.0:
				holding = true
				input.jump_pressed = true
				return input
			return input
		"late":
			press = not scene.vault.opportunity.is_empty() and scene.vault.opportunity.late
	if press and not pressed:
		pressed = true
		holding = case_name == "grab"
		input.jump_pressed = true
		input.jump_held = true
	return input


func _frame() -> void:
	var t := -1.0
	if scene.traversal.mantle.presenting:
		t = scene.traversal.mantle.time
	elif scene.vault.presenting:
		t = scene.vault.time
	if case_name in ["rhythm", "angled"]:
		# One frame per vault, at the hand plant, to compare consecutive vaults side by side.
		if scene.vault.presenting and scene.vault.time >= 0.2 and shot_vault != scene.vault.vaults and out_dir != "":
			shot_vault = scene.vault.vaults
			root.get_texture().get_image().save_png("%s/%s_vault%d_%s.png" % [out_dir, case_name, shots, "left" if scene.authored_animation.vault_mirrored else "right"])
			shots += 1
		if ticks > (900 if case_name == "rhythm" else 700):
			print("CAPTURE %s: %d frames, vaults %d, variants %s, sides %s" % [case_name, shots, scene.vault.vaults, scene.authored_animation.vault_variants, scene.vault.sides])
			quit(0)
		return
	if case_name in ["hang", "slide"] and t < 0.0:
		if scene.traversal.mantle.hanging():
			t = 0.2 + scene.traversal.mantle._hang_time * 0.1
		elif scene.traversal.sliding:
			t = scene.traversal.slide_time
	if t >= 0.0 and t - last_shot >= 0.08 and shots < 10 and out_dir != "":
		last_shot = t
		var path := "%s/%s_%02d_t%.2f.png" % [out_dir, case_name, shots, t]
		root.get_texture().get_image().save_png(path)
		shots += 1
	if pressed and t < 0.0 and shots > 0 and done_at < 0:
		done_at = ticks
	if (done_at > 0 and ticks > done_at + 30) or ticks > 1200:
		print("x %.2f reason %s region %s" % [scene.body.global_position.x, scene.vault.reason, scene.vault.region.keys()])
		print("CAPTURE %s: %d frames, vaults %d, mantles %d, aborts %d, choice %s, refusal %s" % [case_name, shots, scene.vault.vaults,
			scene.traversal.mantle.mantles, scene.vault.aborts + scene.traversal.mantle.aborts, scene.traversal.last_choice, scene.traversal.last_refusal])
		quit(0)
