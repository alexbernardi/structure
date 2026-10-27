## Heads-up display: crosshair, interaction prompt, status line, toasts and the F3 debug overlay.
extends Control

var _status: Label
var _prompt: Label
var _toast: Label
var _debug: Label
var _crosshair: Label
var _toast_left := 0.0


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status = _label(Control.PRESET_TOP_LEFT, HORIZONTAL_ALIGNMENT_LEFT, Vector2(16, 12))
	_debug = _label(Control.PRESET_TOP_RIGHT, HORIZONTAL_ALIGNMENT_RIGHT, Vector2(-16, 12))
	_debug.visible = false
	_prompt = _label(Control.PRESET_CENTER_BOTTOM, HORIZONTAL_ALIGNMENT_CENTER, Vector2(0, -90))
	_toast = _label(Control.PRESET_CENTER_TOP, HORIZONTAL_ALIGNMENT_CENTER, Vector2(0, 60))
	_crosshair = _label(Control.PRESET_CENTER, HORIZONTAL_ALIGNMENT_CENTER, Vector2.ZERO)
	_crosshair.text = "+"
	_crosshair.visible = false


func _label(preset: int, align: int, offset: Vector2) -> Label:
	var l := Label.new()
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	l.set_anchors_and_offsets_preset(preset, Control.PRESET_MODE_KEEP_SIZE)
	l.grow_horizontal = Control.GROW_DIRECTION_BOTH if align == HORIZONTAL_ALIGNMENT_CENTER else (
		Control.GROW_DIRECTION_BEGIN if align == HORIZONTAL_ALIGNMENT_RIGHT else Control.GROW_DIRECTION_END)
	l.position += offset
	return l


func set_status(text: String) -> void:
	_status.text = text


func set_prompt(text: String) -> void:
	_prompt.text = text


func set_crosshair(on: bool) -> void:
	_crosshair.visible = on


func toast(text: String, seconds := 3.0) -> void:
	_toast.text = text
	_toast_left = seconds
	_toast.modulate.a = 1.0


func toggle_debug() -> void:
	_debug.visible = not _debug.visible


func debug_visible() -> bool:
	return _debug.visible


func set_debug(text: String) -> void:
	_debug.text = text


func _process(delta: float) -> void:
	if _toast_left > 0.0:
		_toast_left -= delta
		_toast.modulate.a = clampf(_toast_left, 0.0, 1.0)
