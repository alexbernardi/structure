## Constrained editing of the ankle loop, not a free spline: stance must still travel at belt speed.
extends Control

const GRAB_PX := 16.0
const GaitParams = preload("res://animation/gait_params.gd")
const PATH_PARAMS := ["step_length", "midstance_at", "step_height", "swing_forward", "stand_height"]
const COLOUR := Color(0.35, 1.0, 0.7)

var scene
var hovered := -1
var dragging := -1
var _handles: Array[Dictionary] = []
var _values := {}
var _original := {}
var _cycle := {}
var _mouse := Vector2.ZERO
var _target_forward := 0.0
var _anchor_forward := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func active() -> bool:
	return scene != null and scene.gait_params.is_on("edit_path") and not (
		scene.tuning != null and scene.tuning.editor != null and scene.tuning.editor.visible)


func editable() -> bool:
	return active() and scene.view in ["side", "side-left"] and scene.model.pose.get("active", false) and scene.speed > 0.01


func _process(_delta: float) -> void:
	if editable():
		_handles = build_handles()
	else:
		if dragging >= 0:
			cancel_drag()
		_handles.clear()
		if hovered >= 0:
			Input.set_default_cursor_shape(Input.CURSOR_ARROW)
		hovered = -1
	queue_redraw()


func build_handles() -> Array[Dictionary]:
	var c: Dictionary = scene.model.cycle_for(scene.speed)
	var q: float = c.d + (1.0 - c.d) * c.swing_peak
	var landing: Vector3 = scene.model.ankle_at(0.0, c)
	var push_off: Vector3 = scene.model.ankle_at(c.d, c)
	var swing: Vector3 = scene.model.ankle_at(q, c)
	var hip_height: float = c.ankle_h + c.hip_drop + float(scene.gait_params.get_value("stand_height")) * (c.thigh + c.shin)
	return [
		{"id": "landing", "label": "Landing: drag horizontally", "point": Vector2(landing.x, landing.y), "phase": 0.0},
		{"id": "push_off", "label": "Push-off: drag horizontally", "point": Vector2(push_off.x, push_off.y), "phase": c.d},
		{"id": "swing", "label": "Heel recovery: drag forward/back and up/down" if c.running else "Swing arc: drag forward/back and up/down",
			"point": Vector2(swing.x, swing.y), "phase": q},
		{"id": "hip", "label": "Requested hip height: up = straighter knees", "point": Vector2(0.0, hip_height), "phase": -1.0},
	]


func screen(point: Vector2) -> Vector2:
	return scene.cam.unproject_position(Vector3(0.0, point.y, -point.x))


func _on_plane(mouse: Vector2) -> Vector2:
	var ray: Vector3 = scene.cam.project_ray_normal(mouse)
	var origin: Vector3 = scene.cam.project_ray_origin(mouse)
	var hit := origin - ray * (origin.x / ray.x)
	return Vector2(-hit.z, hit.y)


func nearest(mouse: Vector2) -> int:
	var best := -1
	var distance := GRAB_PX
	for i in _handles.size():
		var d := screen(_handles[i].point).distance_to(mouse)
		if d < distance:
			best = i
			distance = d
	return best


func _over_hud(mouse: Vector2) -> bool:
	return scene.tuning != null and scene.tuning.hud != null and scene.tuning.hud.visible and scene.tuning.hud.get_global_rect().has_point(mouse)


func handle_input(event: InputEvent) -> bool:
	if not editable():
		return false
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE and dragging >= 0:
			cancel_drag()
			return true
		if event.keycode == KEY_BACKSPACE:
			cancel_drag()
			for id in PATH_PARAMS:
				var key := _param_id(id)
				scene.gait_params.set_value(key, scene.gait_params.def(key).default)
			if scene.tuning != null:
				scene.tuning.toast.emit("Ankle path and hip height reset to defaults", "info")
			return true
	if event is InputEventMouseMotion:
		if dragging >= 0:
			var point := _on_plane(event.position)
			drag_by(point - _mouse)
			_mouse = point
			return true
		hovered = -1 if _over_hud(event.position) else nearest(event.position)
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if hovered >= 0 else Input.CURSOR_ARROW)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not event.pressed and dragging >= 0:
			dragging = -1
			return true
		if event.pressed and not _over_hud(event.position):
			_handles = build_handles()
			var i := nearest(event.position)
			if i >= 0:
				dragging = i
				hovered = i
				_mouse = _on_plane(event.position)
				_cycle = scene.model.cycle_for(scene.speed).duplicate()
				_original.clear()
				for id in PATH_PARAMS:
					_original[id] = scene.gait_params.get_value(_param_id(id))
				_values = _original.duplicate()
				_target_forward = _handles[i].point.x
				_anchor_forward = _handles[1 if i == 0 else 0].point.x
				if _handles[i].phase >= 0.0:
					scene.gait_params.set_value("scrub", _handles[i].phase)
				return true
	return false


func _param_id(id: String) -> String:
	var running: bool = _cycle.running if dragging >= 0 else scene.gait_params.is_on("run_mode")
	return GaitParams.profile_id(id, running)


func _set_value(id: String, value: float) -> void:
	var key := _param_id(id)
	var definition: Dictionary = scene.gait_params.def(key)
	_values[id] = clampf(value, definition.min, definition.max)
	scene.gait_params.set_value(key, _values[id])


func drag_by(delta: Vector2) -> void:
	var id: String = _handles[dragging].id
	if id == "swing":
		_set_value("swing_forward", float(_values.swing_forward) + delta.x / _cycle.g)
		_set_value("step_height", float(_values.step_height) + delta.y / clampf(_cycle.v / 0.3, 0.0, 1.0))
	elif id == "hip":
		_set_value("stand_height", float(_values.stand_height) + delta.y / (_cycle.thigh + _cycle.shin))
	else:
		_target_forward += delta.x
		var front := _target_forward if id == "landing" else _anchor_forward
		var back := _anchor_forward if id == "landing" else _target_forward
		var start: Vector3 = scene.model.stance(0.0, _cycle)
		var end: Vector3 = scene.model.stance(_cycle.d, _cycle)
		# Remove the rolled foot offsets: the remaining endpoint separation is stride * stance fraction.
		var a: float = start.x - _cycle.stride * _cycle.d * float(_original.midstance_at)
		var b: float = end.x - _cycle.stride * _cycle.d * (float(_original.midstance_at) - 1.0)
		var stride: float = (front - back - a + b) / _cycle.d
		var speed_scale: float = _cycle.step_len / float(_original.step_length)
		var step := stride / (2.0 * speed_scale)
		_set_value("step_length", step)
		var actual_stride: float = 2.0 * speed_scale * float(scene.gait_params.get_value(_param_id("step_length")))
		var midstance: float = (front - a) / (actual_stride * _cycle.d)
		_set_value("midstance_at", midstance)
		if step != float(_values.step_length) or midstance != float(_values.midstance_at):
			var c: Dictionary = scene.model.cycle_for(scene.speed)
			_target_forward = scene.model.stance(0.0 if id == "landing" else c.d, c).x
			_anchor_forward = scene.model.stance(c.d if id == "landing" else 0.0, c).x


func cancel_drag() -> void:
	if dragging < 0:
		return
	var ids: Array = ["step_length", "midstance_at"]
	if dragging == 2:
		ids = ["swing_forward", "step_height"]
	elif dragging == 3:
		ids = ["stand_height"]
	for id in ids:
		scene.gait_params.set_value(_param_id(id), _original[id])
	dragging = -1


func _text(pos: Vector2, text: String, colour := COLOUR) -> void:
	draw_string_outline(ThemeDB.fallback_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 4, Color(0, 0, 0, 0.9))
	draw_string(ThemeDB.fallback_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, colour)


func _draw() -> void:
	if not active():
		return
	var banner := "EDIT ANKLE PATH: drag handles | Space previews | Esc cancels drag | Backspace resets | F5 saves | P leaves"
	if scene.view not in ["side", "side-left"]:
		banner = "Ankle path editing needs a side view: press 1 or 2 (P leaves)"
	elif not editable():
		banner = "Enable the gait model and set the current mode's speed above zero to edit its ankle path (P leaves)"
	else:
		for i in _handles.size():
			var h: Dictionary = _handles[i]
			var pos := screen(h.point)
			var live := i == hovered or i == dragging
			draw_circle(pos, 7.0 if live else 5.5, COLOUR)
			draw_arc(pos, 11.0, 0.0, TAU, 24, COLOUR, 1.5)
			var offset := Vector2(14.0, -16.0 if h.id != "push_off" else 30.0)
			_text(pos + offset, h.label)
			if h.id == "hip":
				var actual: Vector3 = scene.model.pose.pelvis
				draw_line(pos, screen(Vector2(0.0, actual.y)), Color(COLOUR, 0.5), 1.0)
	_text(Vector2(18.0, size.y - 20.0), banner)
