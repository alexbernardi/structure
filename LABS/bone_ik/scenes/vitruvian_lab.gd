## Bone IK laboratory - the Vitruvian skeleton workbench (phase 1).
##
## An isolated scene: the Vitruvian rig as an exposed mechanical skeleton on a metric grid, with measurement
## references, the Vitruvian square and circle, joint labels and axes, the selected joint's rotation limits, live
## joint-angle readouts and stage diagnostics (rest / animation / IK / final).
##
## Keys: 1 front, 2 side, 3 perspective (right-drag orbits, wheel zooms), T T-pose, N neutral, A animation,
## M manual, Space play/pause, L labels, X axes, G grid, V Vitruvian, R rulers, Esc quits a capture run.
## Left-click a joint to select it. Command line (after --): --view=front|side|persp --mode=rest|neutral|anim|manual
## --clip=<name> --time=<s> --preset=modern|vitruvian --select=<bone> --pose=<bone>:<flex>,<abd>,<twist>[;...]
## --capture=<absolute .png> (renders, saves and quits) --overlays=+axes,-labels,...
extends Node3D

const Rig = preload("res://systems/bone_ik/vitruvian_rig.gd")
const Proportions = preload("res://systems/bone_ik/rig/proportions.gd")
const SkeletonView = preload("res://viz/skeleton_view.gd")
const Overlays = preload("res://viz/lab_overlays.gd")

const SLIDERS := ["height", "arm_span_ratio", "leg_weight", "torso_weight", "head_neck_weight", "neck_share",
	"shoulder_width_ratio", "pelvis_width_ratio", "upper_arm_share", "thigh_share", "hand_length_ratio",
	"foot_length_ratio", "left_arm_scale", "right_arm_scale", "left_leg_scale", "right_leg_scale"]

var rig
var view
var overlays
var camera: Camera3D
var cam_mode := "front"
var yaw := 0.6
var pitch := -0.25
var distance := 4.2
var proportions
var _rebuild_pending := false
var _syncing := false
var _readout: RichTextLabel
var _joint_select: OptionButton
var _clip_select: OptionButton
var _joint_sliders := []
var _joint_slider_labels := []
var _prop_sliders := {}
var _prop_labels := {}
var _mode_buttons := []
var _play_button: Button
var _speed: HSlider
var _readout_timer := 0.0
var _capture_path := ""
var _capture_frames := 0
var _args := {}


func _ready() -> void:
	_parse_args()
	proportions = Proportions.from_preset(_args.get("preset", "modern"))
	_build_environment()
	overlays = Overlays.new()
	add_child(overlays)
	rig = Rig.new(proportions)
	rig.name = "VitruvianRig"
	add_child(rig)
	view = SkeletonView.new()
	add_child(view)
	view.setup(rig)
	overlays.update_from(rig.definition)
	camera = Camera3D.new()
	add_child(camera)
	camera.make_current()
	_build_ui()
	_apply_args()
	_set_camera(cam_mode)
	_sync_mode_buttons()


func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			var kv := a.substr(2).split("=", true, 1)
			_args[kv[0]] = kv[1]
	_capture_path = _args.get("capture", "")


func _apply_args() -> void:
	cam_mode = _args.get("view", "front")
	if _args.has("select"):
		_select_joint(_args.select)
	for item in String(_args.get("overlays", "")).split(",", false):
		var on: bool = not item.begins_with("-")
		var key := item.trim_prefix("+").trim_prefix("-")
		match key:
			"labels": view.show_labels = on
			"axes": view.show_axes = on
			"limits": view.show_limits = on
			"rest": view.show_rest_ghost = on
			"anim": view.show_animation_ghost = on
			"grid": overlays.show_grid = on
			"rulers": overlays.show_rulers = on
			"vitruvian": overlays.show_vitruvian = on
	overlays.refresh_visibility()
	match _args.get("mode", "rest"):
		"neutral": rig.set_mode(Rig.Mode.NEUTRAL)
		"anim":
			rig.play(_args.get("clip", "Idle"), float(_args.get("time", "0")))
			for i in _clip_select.item_count:
				if _clip_select.get_item_text(i) == rig.clip:
					_clip_select.select(i)
		"manual": rig.set_mode(Rig.Mode.MANUAL)
		_: rig.set_mode(Rig.Mode.REST)
	if _args.has("pose"):
		for part in String(_args.pose).split(";", false):
			var bone_vals := part.split(":")
			var v := bone_vals[1].split(",")
			rig.set_joint_angles(bone_vals[0], Vector3(float(v[0]), float(v[1]), float(v[2])))
	if _args.get("mode", "") == "anim" and _capture_path != "":
		rig.player.pause()   # a still frame at --time
	_refresh_joint_sliders()


func _build_environment() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, 35, 0)
	sun.shadow_enabled = true
	sun.light_energy = 1.1
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, -140, 0)
	fill.light_energy = 0.45
	add_child(fill)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.93, 0.91, 0.86)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.74, 0.72)
	env.environment.ambient_light_energy = 0.6
	add_child(env)


# ------------------------------------------------------------------------------------------------ camera

func _set_camera(m: String) -> void:
	cam_mode = m
	var h: float = rig.definition.measurements.stature
	var span: float = rig.definition.measurements.arm_span
	match m:
		"front":
			camera.projection = Camera3D.PROJECTION_ORTHOGONAL
			camera.size = maxf(h, span) * 1.5
			# Lift the figure into the area between the panels (the readout covers the bottom of the window).
			camera.transform = Transform3D(Basis.IDENTITY, Vector3(0.1, h * 0.5 - camera.size * 0.11, 6.0))
		"side":
			camera.projection = Camera3D.PROJECTION_ORTHOGONAL
			camera.size = h * 1.5
			camera.transform = Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(6.0, h * 0.5 - camera.size * 0.11, 0.0))
		_:
			camera.projection = Camera3D.PROJECTION_PERSPECTIVE
			camera.fov = 45.0
			_orbit()


func _orbit() -> void:
	var h: float = rig.definition.measurements.stature
	var target := Vector3(0, h * 0.42, 0)
	var b := Basis.from_euler(Vector3(pitch, yaw, 0))
	camera.transform = Transform3D(b, target + b * Vector3(0, 0, distance))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and cam_mode == "persp" and (event.button_mask & MOUSE_BUTTON_MASK_RIGHT):
		yaw -= event.relative.x * 0.006
		pitch = clampf(pitch - event.relative.y * 0.006, -1.4, 1.2)
		_orbit()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom(0.9)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom(1.1)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			_pick(event.position)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1: _set_camera("front")
			KEY_2: _set_camera("side")
			KEY_3: _set_camera("persp")
			KEY_T: _set_mode(Rig.Mode.REST)
			KEY_N: _set_mode(Rig.Mode.NEUTRAL)
			KEY_A: _set_mode(Rig.Mode.ANIMATION)
			KEY_M: _set_mode(Rig.Mode.MANUAL)
			KEY_SPACE: _toggle_play()
			KEY_L: view.show_labels = not view.show_labels
			KEY_X: view.show_axes = not view.show_axes
			KEY_G: _toggle_overlay("show_grid")
			KEY_V: _toggle_overlay("show_vitruvian")
			KEY_R: _toggle_overlay("show_rulers")
			KEY_ESCAPE: if _capture_path != "": get_tree().quit()


func _zoom(f: float) -> void:
	if cam_mode == "persp":
		distance = clampf(distance * f, 1.0, 12.0)
		_orbit()
	else:
		camera.size = clampf(camera.size * f, 0.3, 6.0)


func _toggle_overlay(key: String) -> void:
	overlays.set(key, not overlays.get(key))
	overlays.refresh_visibility()


func _pick(screen: Vector2) -> void:
	var best := ""
	var best_d := 22.0
	var joints: Dictionary = view.joint_positions()
	for bone in joints:
		if camera.is_position_behind(joints[bone]):
			continue
		var d := camera.unproject_position(joints[bone]).distance_to(screen)
		if d < best_d and not rig.profile.joint(bone).is_empty():
			best_d = d
			best = bone
	if best != "":
		_select_joint(best)


# ------------------------------------------------------------------------------------------------ modes

func _set_mode(m) -> void:
	if m == Rig.Mode.ANIMATION:
		var clip: String = rig.clip if rig.clip != "" else _clip_select.get_item_text(_clip_select.selected)
		rig.play(clip)
	else:
		rig.set_mode(m)
	_sync_mode_buttons()
	_refresh_joint_sliders()


func _sync_mode_buttons() -> void:
	for i in _mode_buttons.size():
		_mode_buttons[i].set_pressed_no_signal(i == rig.mode)


func _toggle_play() -> void:
	if rig.mode != Rig.Mode.ANIMATION:
		_set_mode(Rig.Mode.ANIMATION)
		return
	if rig.player.is_playing():
		rig.player.pause()
	else:
		rig.player.play()


func _select_joint(bone: String) -> void:
	if rig.profile.joint(bone).is_empty():
		return
	view.selected = bone
	if _joint_select != null:
		for i in _joint_select.item_count:
			if _joint_select.get_item_text(i) == bone:
				_joint_select.select(i)
	_refresh_joint_sliders()


func _refresh_joint_sliders() -> void:
	if _joint_sliders.is_empty():
		return
	var j: Dictionary = rig.profile.joint(view.selected)
	var current: Vector3 = rig.manual_angles.get(view.selected, rig.get_joint_angles(view.selected, "final"))
	_syncing = true
	var keys := ["flex", "abd", "twist"]
	for i in 3:
		var lim: Vector2 = j.limits_deg[keys[i]].hard
		var s: HSlider = _joint_sliders[i]
		s.min_value = lim.x - 30.0
		s.max_value = lim.y + 30.0
		s.value = current[i]
		_joint_slider_labels[i].text = "%s  [%s]" % [keys[i], j.labels[keys[i]]]
	_syncing = false


func _on_joint_slider(_v: float) -> void:
	if _syncing:
		return
	rig.set_joint_angles(view.selected, Vector3(_joint_sliders[0].value, _joint_sliders[1].value, _joint_sliders[2].value))
	_sync_mode_buttons()


# ------------------------------------------------------------------------------------------------ UI

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var left := _panel(layer, Vector2(8, 8), Vector2(290, 0))
	var box: VBoxContainer = left.get_child(0)
	_title(box, "BONE IK LAB  -  Vitruvian rig %s" % Rig.VERSION)
	_title(box, "Mode")
	var group := ButtonGroup.new()
	for i in Rig.MODE_NAMES.size():
		var b := Button.new()
		b.text = Rig.MODE_NAMES[i]
		b.toggle_mode = true
		b.button_group = group
		b.pressed.connect(_set_mode.bind(i))
		box.add_child(b)
		_mode_buttons.append(b)
	_title(box, "Imported animation")
	_clip_select = OptionButton.new()
	var clips: PackedStringArray = rig.clips()
	for c in clips:
		_clip_select.add_item(c)
	var idle := clips.find("Idle")
	_clip_select.select(maxi(idle, 0))
	_clip_select.item_selected.connect(func(i): rig.play(_clip_select.get_item_text(i)); _sync_mode_buttons())
	box.add_child(_clip_select)
	var row := HBoxContainer.new()
	box.add_child(row)
	_play_button = Button.new()
	_play_button.text = "Play / pause"
	_play_button.pressed.connect(_toggle_play)
	row.add_child(_play_button)
	_speed = HSlider.new()
	_speed.min_value = 0.0
	_speed.max_value = 2.0
	_speed.step = 0.05
	_speed.value = 1.0
	_speed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_speed.value_changed.connect(func(v): rig.player.speed_scale = v)
	row.add_child(_speed)
	_title(box, "Camera  (1 / 2 / 3)")
	var cams := HBoxContainer.new()
	box.add_child(cams)
	for c in [["Front", "front"], ["Side", "side"], ["Persp.", "persp"]]:
		var b := Button.new()
		b.text = c[0]
		b.pressed.connect(_set_camera.bind(c[1]))
		cams.add_child(b)
	_title(box, "Show")
	_check(box, "Metric grid", overlays.show_grid, func(on): overlays.show_grid = on; overlays.refresh_visibility())
	_check(box, "Height / span rulers", overlays.show_rulers, func(on): overlays.show_rulers = on; overlays.refresh_visibility())
	_check(box, "Vitruvian square + circle", overlays.show_vitruvian, func(on): overlays.show_vitruvian = on; overlays.refresh_visibility())
	_check(box, "Bone labels", view.show_labels, func(on): view.show_labels = on)
	_check(box, "Joint axes (X red, Y green, Z blue)", view.show_axes, func(on): view.show_axes = on)
	_check(box, "Selected joint limits", view.show_limits, func(on): view.show_limits = on)
	_check(box, "Rest pose ghost (grey)", view.show_rest_ghost, func(on): view.show_rest_ghost = on)
	_check(box, "Animation-stage ghost (orange)", view.show_animation_ghost, func(on): view.show_animation_ghost = on)
	_title(box, "Constraints")
	_check(box, "Enforce hard joint limits", true, func(on): rig.set_limits_enforced(on))
	_check(box, "Hinge alignment (lossless)", true, func(on): rig.set_hinge_align(on))
	_title(box, "Joint (click a joint sphere)")
	_joint_select = OptionButton.new()
	for j in rig.profile.joints:
		_joint_select.add_item(j.bone)
	_joint_select.item_selected.connect(func(i): _select_joint(_joint_select.get_item_text(i)))
	box.add_child(_joint_select)
	for i in 3:
		var l := Label.new()
		l.add_theme_font_size_override("font_size", 11)
		box.add_child(l)
		_joint_slider_labels.append(l)
		var s := HSlider.new()
		s.step = 0.5
		s.value_changed.connect(_on_joint_slider)
		box.add_child(s)
		_joint_sliders.append(s)
	var reset := Button.new()
	reset.text = "Reset manual pose to neutral"
	reset.pressed.connect(func(): rig.reset_manual(); rig.set_mode(Rig.Mode.NEUTRAL); _sync_mode_buttons(); _refresh_joint_sliders())
	box.add_child(reset)
	_select_joint(view.selected)

	var right := _panel(layer, Vector2(0, 8), Vector2(300, 0))
	right.anchor_left = 1.0
	right.anchor_right = 1.0
	right.offset_left = -308
	right.offset_right = -8
	var rbox: VBoxContainer = right.get_child(0)
	_title(rbox, "Proportions")
	var presets := HBoxContainer.new()
	rbox.add_child(presets)
	for p in ["modern", "vitruvian"]:
		var b := Button.new()
		b.text = p.capitalize()
		b.pressed.connect(_apply_preset.bind(p))
		presets.add_child(b)
	for key in SLIDERS:
		var spec: Array = Proportions.SPEC[key]
		var l := Label.new()
		l.add_theme_font_size_override("font_size", 11)
		rbox.add_child(l)
		_prop_labels[key] = l
		var s := HSlider.new()
		s.min_value = spec[1]
		s.max_value = spec[2]
		s.step = 0.001 if spec[2] < 3.0 else 0.5
		s.value = proportions.get_value(key)
		s.value_changed.connect(_on_prop.bind(key))
		rbox.add_child(s)
		_prop_sliders[key] = s
	_update_prop_labels()

	var bottom := PanelContainer.new()
	bottom.anchor_top = 1.0
	bottom.anchor_bottom = 1.0
	bottom.anchor_left = 0.0
	bottom.anchor_right = 1.0
	bottom.offset_left = 306
	bottom.offset_right = -316
	bottom.offset_top = -205
	bottom.offset_bottom = -8
	bottom.self_modulate = Color(1, 1, 1, 0.9)
	layer.add_child(bottom)
	_readout = RichTextLabel.new()
	_readout.bbcode_enabled = true
	_readout.scroll_active = true
	_readout.add_theme_font_size_override("normal_font_size", 10)
	_readout.add_theme_font_size_override("mono_font_size", 10)
	bottom.add_child(_readout)


func _panel(layer: CanvasLayer, at: Vector2, size: Vector2) -> PanelContainer:
	var p := PanelContainer.new()
	p.position = at
	p.custom_minimum_size = size
	p.self_modulate = Color(1, 1, 1, 0.88)
	layer.add_child(p)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	p.add_child(box)
	return p


func _title(box: VBoxContainer, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Color(1.0, 0.85, 0.55))
	box.add_child(l)


func _check(box: VBoxContainer, text: String, on: bool, callback: Callable) -> void:
	var c := CheckBox.new()
	c.text = text
	c.button_pressed = on
	c.add_theme_font_size_override("font_size", 11)
	c.toggled.connect(callback)
	box.add_child(c)


func _apply_preset(name: String) -> void:
	proportions = Proportions.from_preset(name)
	_syncing = true
	for key in _prop_sliders:
		_prop_sliders[key].value = proportions.get_value(key)
	_syncing = false
	_rebuild_pending = true


func _on_prop(value: float, key: String) -> void:
	if _syncing:
		return
	proportions.set_value(key, value)
	_rebuild_pending = true


func _update_prop_labels() -> void:
	for key in _prop_labels:
		_prop_labels[key].text = "%s: %.3f" % [Proportions.SPEC[key][3], proportions.get_value(key)]


func _process(delta: float) -> void:
	if _rebuild_pending:
		_rebuild_pending = false
		rig.build(proportions)
		view.rebuild()
		overlays.update_from(rig.definition)
		_update_prop_labels()
		if cam_mode != "persp":
			_set_camera(cam_mode)
	_readout_timer -= delta
	if _readout_timer <= 0.0:
		_readout_timer = 0.12
		_update_readout()
	if _capture_path != "":
		_capture_frames += 1
		if _capture_frames == 12:
			_update_readout()
		if _capture_frames == 14:
			var img := get_viewport().get_texture().get_image()
			img.save_png(_capture_path)
			print("captured %s" % _capture_path)
			get_tree().quit()


func _update_readout() -> void:
	if _readout == null:
		return
	var s: Dictionary = rig.pose_state()
	var m: Dictionary = rig.definition.measurements
	var d: Dictionary = rig.definition.dims
	var t := "[font_size=12][b]%s[/b][/font_size]" % s.mode
	if rig.mode == Rig.Mode.ANIMATION:
		t += "  clip [b]%s[/b]  t = %.2f s" % [rig.clip, s.time]
	t += "    limits %s, hinge align %s, IK layer: %s\n" % ["ON" if s.limits_enforced else "measure only",
		"ON" if s.hinge_align else "off", s.ik_layer]
	t += "[code]stature %.3f m  span %.3f m (%.3f)  hip joints %.3f  navel %.3f (%.3f)  shoulders %.3f  pelvis %.3f  foot %.3f  hand %.3f[/code]\n" % [
		m.stature, m.arm_span, m.arm_span / m.stature, m.hip_joint_height, m.navel_height, m.navel_height / m.stature,
		m.shoulder_joint_width, m.hip_joint_width, m.foot_length, m.hand_length]
	t += "[code]upper arm %.3f  forearm %.3f  thigh %.3f  shank %.3f  torso %.3f  neck %.3f  head %.3f   body mass %.0f kg[/code]\n" % [
		d.left_upper_arm, d.left_forearm, d.left_thigh, d.left_shank, d.torso, d.neck, d.head, d.body_mass]
	if s.violating_joints > 0:
		t += "[b][color=#ffe14d]incoming pose beyond hard limits at %d joint(s); worst %s %.1f deg (clamped: %s)[/color][/b]\n" % [
			s.violating_joints, s.worst_violation_bone, s.worst_violation_deg, "yes" if s.limits_enforced else "no"]
	var j: Dictionary = rig.profile.joint(view.selected)
	if not j.is_empty():
		var fin: Vector3 = s.joints[view.selected].final_deg
		var ani: Vector3 = s.joints[view.selected].animation_deg
		t += "[b]%s[/b] - %s (%s)  soft load %.2f\n" % [view.selected, j.region, j.type, s.joints[view.selected].soft_load]
		var keys := ["flex", "abd", "twist"]
		for i in 3:
			var l: Dictionary = j.limits_deg[keys[i]]
			t += "[code]  %-5s %7.1f final  %7.1f anim   soft [%5.0f, %4.0f]  hard [%5.0f, %4.0f]  %s[/code]\n" % [
				keys[i], fin[i], ani[i], l.soft.x, l.soft.y, l.hard.x, l.hard.y, j.labels[keys[i]]]
		var i_bone: int = j.bone_index
		var rest: Transform3D = rig.stage_globals("rest")[i_bone]
		var an: Transform3D = rig.stage_globals("animation")[i_bone]
		var ik: Transform3D = rig.stage_globals("ik")[i_bone]
		var fn: Transform3D = rig.stage_globals("final")[i_bone]
		t += "[code]  stages (model space): rest->anim %.3f m %.1f deg | anim->IK %.3f m %.1f deg | IK->final %.3f m %.1f deg[/code]\n" % [
			rest.origin.distance_to(an.origin), _deg(rest.basis, an.basis), an.origin.distance_to(ik.origin), _deg(an.basis, ik.basis),
			ik.origin.distance_to(fn.origin), _deg(ik.basis, fn.basis)]
		t += "  sources: %s\n" % ", ".join(j.sources)
	t += "[code]"
	var col := 0
	for jj in rig.profile.joints:
		var a: Vector3 = s.joints[jj.bone].final_deg
		var flag := " "
		if s.joints[jj.bone].incoming_beyond_hard_deg > 0.01:
			flag = "!"
		elif s.joints[jj.bone].soft_load > 0.0:
			flag = "~"
		t += "%s%-13s %6.1f %6.1f %6.1f   " % [flag, jj.bone, a.x, a.y, a.z]
		col += 1
		if col % 3 == 0:
			t += "\n"
	t += "[/code]\n(final flex / abd / twist in degrees; ~ in the soft resistance zone, ! incoming pose beyond the hard limit)"
	_readout.text = t


static func _deg(a: Basis, b: Basis) -> float:
	var q := a.get_rotation_quaternion().inverse() * b.get_rotation_quaternion()
	return rad_to_deg(2.0 * atan2(Vector3(q.x, q.y, q.z).length(), absf(q.w)))
