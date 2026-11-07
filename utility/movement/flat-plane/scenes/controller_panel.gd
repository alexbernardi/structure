## Drawn replica of the SMC-Mixer front panel (layout from the official photo). Shows, per control:
## grey = unmapped, blue = mapped, green tick = verified by a real actuation, bright = active now, orange = learning.
## Click a control to select it; the monitor decides what clicking does.
extends Control

const Catalog = preload("res://midi/control_catalog.gd")

signal control_clicked(control_id: String)

const PITCH := 104.0
const FLASH_SEC := 0.25
const C_UNMAPPED := Color(0.45, 0.47, 0.52)
const C_MAPPED := Color(0.36, 0.62, 1.0)
const C_VERIFIED := Color(0.30, 0.85, 0.45)
const C_ACTIVE := Color(1.0, 0.95, 0.45)
const C_LEARN := Color(1.0, 0.55, 0.15)

var manager: Node
var selected := ""
var learning := ""

var _rects: Dictionary = {}     # id -> Rect2
var _view: Dictionary = {}      # id -> {value, angle, pressed, flash}
var _font: Font = ThemeDB.fallback_font


func _init() -> void:
	custom_minimum_size = Vector2(930, 410)
	_layout()


func bind(m: Node) -> void:
	manager = m
	m.control_changed.connect(_on_control_changed)


func _layout() -> void:
	for s in range(1, Catalog.STRIPS + 1):
		var x0 := 20.0 + (s - 1) * PITCH
		_rects["strip%d_knob" % s] = Rect2(x0 + 6, 24, 52, 52)
		_rects["strip%d_fader" % s] = Rect2(x0 + 6, 112, 32, 192)
		var j := 0
		for b in Catalog.STRIP_BUTTONS:
			_rects["strip%d_%s" % [s, b[0]]] = Rect2(x0 + 52, 112 + j * 50, 36, 38)
			j += 1
	var i := 0
	for b in Catalog.GLOBAL_BUTTONS:
		_rects["global_%s" % b[0]] = Rect2(20 + i * 76.0, 340, 66, 38)
		i += 1
	_rects["global_bt"] = Rect2(868, 34, 50, 26)
	_rects["global_shift"] = Rect2(868, 70, 50, 26)


func _on_control_changed(id: String, st: Dictionary) -> void:
	var v: Dictionary = _view.get(id, {"value": 0.0, "angle": 0.0, "pressed": false, "flash": 0.0})
	if st.has("value"):
		v.value = st.value
	if st.has("delta"):
		v.angle += float(st.delta) * 0.18
	if st.has("pressed"):
		v.pressed = st.pressed
	v.flash = FLASH_SEC
	_view[id] = v


func _process(delta: float) -> void:
	for id in _view:
		_view[id].flash = maxf(0.0, _view[id].flash - delta)
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for id in _rects:
			if (_rects[id] as Rect2).grow(3).has_point(event.position):
				control_clicked.emit(id)
				return


func rect_of(id: String) -> Rect2:
	return _rects.get(id, Rect2())


func _colour(id: String) -> Color:
	if id == learning:
		var pulse := 0.65 + 0.35 * sin(Time.get_ticks_msec() / 120.0)
		return C_LEARN * Color(pulse, pulse, pulse, 1.0)
	if manager == null or not manager.config.is_mapped(id):
		return C_UNMAPPED
	if _view.get(id, {}).get("flash", 0.0) > 0.0:
		return C_ACTIVE
	return C_VERIFIED if manager.config.is_verified(id) else C_MAPPED


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.88, 0.89, 0.91), true)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.6, 0.62, 0.66), false, 2.0)
	for s in range(1, Catalog.STRIPS + 1):
		_draw_knob("strip%d_knob" % s)
		_draw_fader("strip%d_fader" % s)
		for b in Catalog.STRIP_BUTTONS:
			_draw_button("strip%d_%s" % [s, b[0]], "M" if b[0] == "mute" else "S" if b[0] == "solo" else "R" if b[0] == "rec" else "#")
	var short := {"play": "PLAY", "stop": "STOP", "record": "REC", "rewind": "REW", "forward": "FFW", "bank_prev": "<<",
		"bank_next": ">>", "nav_up": "UP", "nav_down": "DOWN", "nav_left": "LEFT", "nav_right": "RIGHT"}
	for b in Catalog.GLOBAL_BUTTONS:
		_draw_button("global_%s" % b[0], short[b[0]])
	_draw_button("global_bt", "BT")
	_draw_button("global_shift", "SHIFT")
	_draw_text(Vector2(20, 400), "blue = mapped   green + tick = verified   grey = unmapped   orange = learning   BT / SHIFT are firmware keys (optional)   click a control to select it", 12, Color(0.3, 0.3, 0.35))


func _outline(id: String, r: Rect2, fill: bool) -> Color:
	var c := _colour(id)
	if fill:
		draw_rect(r, c.darkened(0.2) if c != C_UNMAPPED else Color(0.80, 0.81, 0.84), true)
	draw_rect(r, c, false, 3.0 if (id == selected or id == learning) else 2.0)
	if id == selected:
		draw_rect(r.grow(4), Color(0.1, 0.1, 0.12), false, 1.5)
	if manager and manager.config.is_verified(id):
		_draw_tick(Vector2(r.end.x - 6, r.position.y + 6))
	return c


func _draw_tick(p: Vector2) -> void:
	draw_polyline(PackedVector2Array([p + Vector2(-6, 0), p + Vector2(-2, 4), p + Vector2(6, -5)]), C_VERIFIED.darkened(0.15), 2.5)


func _draw_text(p: Vector2, text: String, fsize: int, colour: Color) -> void:
	draw_string(_font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, colour)


func _draw_button(id: String, label: String) -> void:
	var r: Rect2 = _rects[id]
	var v: Dictionary = _view.get(id, {})
	var c := _outline(id, r, true)
	if v.get("pressed", false):
		draw_rect(r.grow(-4), C_ACTIVE, true)
	var w := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	_draw_text(r.position + Vector2((r.size.x - w) / 2.0, r.size.y / 2.0 + 5), label, 14, Color(0.12, 0.12, 0.14))


func _draw_knob(id: String) -> void:
	var r: Rect2 = _rects[id]
	var v: Dictionary = _view.get(id, {})
	var centre := r.get_center()
	var c := _colour(id)
	draw_circle(centre, 25.0, Color(0.16, 0.16, 0.18))
	draw_arc(centre, 27.0, 0.0, TAU, 40, c, 3.0 if (id == selected or id == learning) else 2.0)
	var mapped: bool = manager != null and manager.config.is_mapped(id)
	var m: Dictionary = manager.config.mapping_of(id) if mapped else {}
	var ang: float = v.get("angle", 0.0)
	if m.get("behavior", "") == "absolute":
		ang = lerpf(-2.35, 2.35, v.get("value", 0.0))
	var dir := Vector2(sin(ang), -cos(ang))
	draw_line(centre + dir * 6.0, centre + dir * 22.0, c if mapped else Color(0.75, 0.75, 0.78), 3.0)
	if id == selected:
		draw_arc(centre, 32.0, 0.0, TAU, 40, Color(0.1, 0.1, 0.12), 1.5)
	if manager and manager.config.is_verified(id):
		_draw_tick(Vector2(r.end.x + 4, r.position.y + 4))
	_draw_text(Vector2(r.position.x + 12, r.position.y - 6), "K%s" % id.substr(5, 1), 12, Color(0.3, 0.3, 0.35))


func _draw_fader(id: String) -> void:
	var r: Rect2 = _rects[id]
	var v: Dictionary = _view.get(id, {})
	var c := _colour(id)
	var slot := Rect2(r.position.x + r.size.x / 2.0 - 4, r.position.y, 8, r.size.y)
	draw_rect(slot, Color(0.1, 0.1, 0.12), true)
	draw_rect(r, c, false, 3.0 if (id == selected or id == learning) else 2.0)
	var value: float = v.get("value", 0.0)
	var cap := Rect2(r.position.x - 2, r.end.y - 20 - value * (r.size.y - 20), r.size.x + 4, 20)
	draw_rect(cap, Color(0.2, 0.2, 0.23), true)
	draw_rect(cap, c, false, 2.0)
	if id == selected:
		draw_rect(r.grow(4), Color(0.1, 0.1, 0.12), false, 1.5)
	if manager and manager.config.is_verified(id):
		_draw_tick(Vector2(r.end.x + 2, r.position.y - 6))
	_draw_text(Vector2(r.position.x + 8, r.end.y + 16), "F%s" % id.substr(5, 1), 12, Color(0.3, 0.3, 0.35))
