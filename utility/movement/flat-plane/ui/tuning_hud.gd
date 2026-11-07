## On-screen tuning HUD (top right): bank, preset, MIDI status, one row per strip with the live value, a bar showing
## the value within its range (white tick = default), the physical fader position while it still has to pick up,
## lock / modified / just-changed markers, details of the selected parameter, and short notifications.
## Modes (F3 or the HUD button): 0 = full, 1 = compact, 2 = hidden.
extends Control

const Catalog = preload("res://midi/control_catalog.gd")

const WIDTH := 500.0
const ROW := 44.0
const PAD := 10.0
const FLASH_MSEC := 1200
const TOAST_SEC := 3.5

const C_BG := Color(0.04, 0.05, 0.08, 0.80)
const C_TEXT := Color(0.92, 0.94, 0.98)
const C_DIM := Color(0.55, 0.58, 0.66)
const C_OK := Color(0.40, 0.90, 0.50)
const C_BAD := Color(1.0, 0.45, 0.40)
const C_WARN := Color(1.0, 0.75, 0.30)
const C_FLASH := Color(0.45, 0.90, 1.0)
const C_BAR := Color(0.30, 0.55, 0.95)

var mode := 0
var system
var _font: Font = ThemeDB.fallback_font
var _toasts: Array[Dictionary] = []


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	custom_minimum_size = Vector2(WIDTH, 100)
	size = Vector2(WIDTH, 100)
	position = Vector2(-WIDTH - 12, 12)
	grow_horizontal = Control.GROW_DIRECTION_BEGIN


func bind(sys) -> void:
	system = sys


func cycle() -> void:
	mode = (mode + 1) % 3
	visible = mode != 2
	notify(["HUD: full", "HUD: compact", "HUD: hidden (F3 to bring it back)"][mode], "info", mode == 2)


func notify(text: String, level := "info", force_visible := false) -> void:
	_toasts.append({"text": text, "level": level, "t": TOAST_SEC})
	if _toasts.size() > 4:
		_toasts.pop_front()


func _process(delta: float) -> void:
	for t in _toasts:
		t.t -= delta
	_toasts = _toasts.filter(func(t: Dictionary) -> bool: return t.t > 0.0)
	if mode == 2 and not _toasts.is_empty():
		visible = true   # a toast always gets through, even with the HUD hidden
	elif mode == 2:
		visible = false
	queue_redraw()


func _level_colour(level: String) -> Color:
	return {"ok": C_OK, "warn": C_WARN, "error": C_BAD}.get(level, C_TEXT)


func _text(p: Vector2, s: String, size: int, c: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	draw_string(_font, p, s, align, width, size, c)


func _draw() -> void:
	if system == null or system.engine == null:
		return
	var e = system.engine
	var y := 0.0
	var full := mode == 0
	var h := PAD * 2 + 54.0 + (ROW * Catalog.STRIPS + 70.0 if full else 24.0) + float(_toasts.size()) * 20.0
	if mode == 2:
		h = PAD * 2 + float(_toasts.size()) * 20.0
	size.y = h
	draw_rect(Rect2(0, 0, WIDTH, h), C_BG, true)
	if mode != 2:
		y = _header(e, PAD)
		if full:
			for strip in range(1, Catalog.STRIPS + 1):
				_row(e, strip, y)
				y += ROW
			y = _detail(e, y + 4.0)
		else:
			y = _last_change_line(e, y)
	else:
		y = PAD
	for t in _toasts:
		var a := clampf(t.t / 0.6, 0.0, 1.0)
		_text(Vector2(PAD, y + 15.0), String(t.text), 14, _level_colour(t.level) * Color(1, 1, 1, a), HORIZONTAL_ALIGNMENT_LEFT, WIDTH - PAD * 2)
		y += 20.0


func _header(e, y: float) -> float:
	var bname: String = system.bindings.bank_name(e.bank)
	_text(Vector2(PAD, y + 20.0), "BANK %d/%d  %s" % [e.bank + 1, system.bindings.bank_count(), bname], 20, C_TEXT)
	var pname: String = e.preset_name if e.preset_name != "" else "(unsaved)"
	var modified: bool = e.is_modified()
	_text(Vector2(0, y + 20.0), "preset: %s%s" % [pname, " *" if modified else ""], 15, C_WARN if modified else C_DIM, HORIZONTAL_ALIGNMENT_RIGHT, WIDTH - PAD)
	var connected: bool = system.midi != null and system.midi.connected
	var status := "● %s" % system.midi.config.data.get("device_hint", "MIDI") if connected else "○ no MIDI device"
	_text(Vector2(PAD, y + 42.0), status, 14, C_OK if connected else C_BAD)
	if system.last_midi_text != "":
		_text(Vector2(150, y + 42.0), system.last_midi_text, 12, C_DIM, HORIZONTAL_ALIGNMENT_LEFT, WIDTH - 160)
	return y + 54.0


func _last_change_line(e, y: float) -> float:
	if e.last_change.is_empty():
		_text(Vector2(PAD, y + 16.0), "no changes yet", 13, C_DIM)
	else:
		var lc: Dictionary = e.last_change
		var fresh := Time.get_ticks_msec() - int(lc.msec) < FLASH_MSEC
		_text(Vector2(PAD, y + 16.0), "%s = %s" % [system.registry.label_of(lc.key), system.registry.format_value(lc.key, lc.value)], 14, C_FLASH if fresh else C_TEXT)
	return y + 24.0


func _row(e, strip: int, y: float) -> void:
	var reg = system.registry
	var key: String = e.strip_key(strip)
	_text(Vector2(PAD, y + 24.0), str(strip), 16, C_DIM)
	if key == "":
		_text(Vector2(34, y + 24.0), "— unassigned —", 13, Color(C_DIM, 0.6))
		return
	var v: float = reg.value(key)
	var fresh: bool = Time.get_ticks_msec() - int(e.last_change.get("msec", -100000)) < FLASH_MSEC and e.last_change.get("key", "") == key
	var is_mod: bool = not is_equal_approx(v, float(e.baseline.get(key, reg.default_of(key))))
	var vcol := C_FLASH if fresh else (C_WARN if is_mod else C_TEXT)
	_text(Vector2(34, y + 17.0), reg.label_of(key), 14, vcol if fresh else C_TEXT)
	_text(Vector2(0, y + 17.0), reg.format_value(key, v), 15, vcol, HORIZONTAL_ALIGNMENT_RIGHT, WIDTH - PAD)
	if e.locked.has(key):
		var lx := 34.0 + _font.get_string_size(reg.label_of(key), HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 10.0
		draw_rect(Rect2(lx - 3, y + 5.0, 42, 16), Color(C_BAD, 0.25), true)
		_text(Vector2(lx, y + 17.0), "LOCK", 12, C_BAD)
	# bar
	var bx := 34.0
	var bw := WIDTH - 34.0 - PAD
	var by := y + 26.0
	draw_rect(Rect2(bx, by, bw, 8), Color(0.18, 0.20, 0.26), true)
	draw_rect(Rect2(bx, by, bw * reg.norm(key), 8), C_FLASH if fresh else C_BAR, true)
	var dn: float = clampf((reg.default_of(key) - float(reg.def_of(key).min)) / (float(reg.def_of(key).max) - float(reg.def_of(key).min)), 0.0, 1.0)
	draw_line(Vector2(bx + bw * dn, by - 2), Vector2(bx + bw * dn, by + 10), Color(1, 1, 1, 0.75), 1.5)
	var info: Dictionary = e.fader_info(strip)
	if not info.is_empty() and not info.engaged:
		_pickup_marker(info, bx, bw, by, y)


## The fader has to travel to the value before it takes over: show where it is and which way to move it.
func _pickup_marker(info: Dictionary, bx: float, bw: float, by: float, y: float) -> void:
	if info.physical < 0.0:
		return   # this fader has not been touched yet: its position is unknown, so there is nothing to point at
	var px: float = bx + bw * clampf(info.physical, 0.0, 1.0)
	draw_colored_polygon(PackedVector2Array([Vector2(px - 6, by + 17), Vector2(px, by + 9), Vector2(px + 6, by + 17)]), C_WARN)
	var hint := "lower the fader" if info.physical > info.target else "raise the fader"
	_text(Vector2(WIDTH - 250, y + 17.0), hint, 12, C_WARN, HORIZONTAL_ALIGNMENT_RIGHT, 140)


func _detail(e, y: float) -> float:
	var reg = system.registry
	draw_line(Vector2(PAD, y), Vector2(WIDTH - PAD, y), Color(1, 1, 1, 0.15), 1.0)
	if e.selected_key == "" or not reg.has_key(e.selected_key):
		_text(Vector2(PAD, y + 20.0), "Select (strip button 4) shows a parameter's range and default", 12, C_DIM)
		return y + 28.0
	var k: String = e.selected_key
	var d: Dictionary = reg.def_of(k)
	_text(Vector2(PAD, y + 20.0), "%s  [%s]" % [reg.label_of(k), k], 14, C_FLASH)
	_text(Vector2(PAD, y + 40.0), "range %s .. %s %s    default %s    step %s    preset %s" % [
		str(d.min), str(d.max), d.unit, reg.format_value(k, float(d.default)), str(d.step), reg.format_value(k, float(e.baseline.get(k, d.default)))], 12, C_DIM, HORIZONTAL_ALIGNMENT_LEFT, WIDTH - PAD * 2)
	return y + 52.0
