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


func _initialize() -> void:
	for raw in OS.get_cmdline_user_args():
		var a := String(raw)
		if a.begins_with("--case="):
			case_name = a.substr(7)
		elif a.begins_with("--out="):
			out_dir = a.substr(6)
	scene = Scene.instantiate()
	scene.options = {"no-capture": "true", "no-hardware": "true", "no-window-state": "true", "tuning-state": "", "traversal-debug": "true", "no-tuning": "true",
		"landmark": {"mantle": "lane_e", "grab": "lane_e_ledge", "vault": "vault_a", "late": "vault_a", "cyber": "vault_a"}.get(case_name, "lane_e")}
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
		"vault", "cyber":
			press = not scene.vault.opportunity.is_empty()
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
