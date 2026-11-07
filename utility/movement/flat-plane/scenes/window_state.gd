## Window placement for the lab: resizable and movable, remembered between runs, with snap hotkeys.
## First launch opens on the left half of the primary screen. Add one instance to a scene and call attach().
##   F6 snap left half   F7 snap right half   F8 centre   F11 fullscreen toggle
## Placement is per-machine, so it is stored under user://, not in the repository.
extends Node

const SAVE_PATH := "user://window_state.json"
const MIN_SIZE := Vector2i(640, 360)
const CENTER_MAX := Vector2i(1600, 900)   ## a centred window never sprawls across an ultrawide screen
const SAVE_DELAY := 1.0

var window: Window
var save_path := SAVE_PATH

var _last := {}
var _since_change := 0.0
var _dirty := false


## `first_run_side`: "left", "right" or "center" - where to open when nothing is saved yet.
func attach(w: Window, first_run_side := "left", path := SAVE_PATH) -> void:
	window = w
	save_path = path
	window.min_size = MIN_SIZE
	window.unresizable = false
	window.borderless = false
	var saved := load_state(save_path)
	if saved.is_empty():
		apply_rect(side_rect(first_run_side))
	else:
		var r := Rect2i(Vector2i(int(saved.x), int(saved.y)), Vector2i(int(saved.w), int(saved.h)))
		var fitted := fit_to_screens(r, screens())
		apply_rect(fitted)
		if saved.get("fullscreen", false):
			window.mode = Window.MODE_FULLSCREEN
	_last = snapshot()
	print("window.placed first_run=%s side=%s pos=%s size=%s usable=%s deco=%s" % [saved.is_empty(), first_run_side, window.position, window.size, DisplayServer.screen_get_usable_rect(window.current_screen), decoration()])


# ------------------------------------------------------------------ pure helpers (unit-tested)

## Window rectangle for a screen side. `usable` is the screen minus taskbars; `deco` the title bar and borders.
static func side_rect_for(usable: Rect2i, deco: Vector2i, side: String) -> Rect2i:
	var avail := Vector2i(usable.size.x - deco.x, usable.size.y - deco.y)
	var size := Vector2i(maxi(MIN_SIZE.x, avail.x), maxi(MIN_SIZE.y, avail.y))
	var pos := usable.position + Vector2i(0, deco.y)
	match side:
		"left":
			size.x = maxi(MIN_SIZE.x, avail.x / 2)
		"right":
			size.x = maxi(MIN_SIZE.x, avail.x / 2)
			pos.x = usable.position.x + usable.size.x - size.x - deco.x / 2
		_:
			size = Vector2i(clampi(avail.x * 3 / 4, MIN_SIZE.x, CENTER_MAX.x), clampi(avail.y * 3 / 4, MIN_SIZE.y, CENTER_MAX.y))
			pos = usable.position + Vector2i((usable.size.x - size.x) / 2, deco.y + (avail.y - size.y) / 2)
	return Rect2i(pos, size)


## Keeps a saved rectangle reachable: if it is mostly off every screen (a monitor was unplugged), move it onto the
## nearest one; if it is bigger than that screen, shrink it.
static func fit_to_screens(r: Rect2i, usable_rects: Array[Rect2i]) -> Rect2i:
	if usable_rects.is_empty():
		return r
	var size := Vector2i(maxi(MIN_SIZE.x, r.size.x), maxi(MIN_SIZE.y, r.size.y))
	var best := usable_rects[0]
	var best_overlap := -1
	for u in usable_rects:
		var o := u.intersection(Rect2i(r.position, size))
		var area := o.size.x * o.size.y
		if area > best_overlap:
			best_overlap = area
			best = u
	size = Vector2i(mini(size.x, best.size.x), mini(size.y, best.size.y))
	var visible_area := best.intersection(Rect2i(r.position, size))
	if visible_area.size.x * visible_area.size.y >= size.x * size.y / 2:
		# mostly visible: only make sure the title bar stays reachable
		var pos := Vector2i(clampi(r.position.x, best.position.x - size.x + 120, best.end.x - 120), clampi(r.position.y, best.position.y, best.end.y - 60))
		return Rect2i(pos, size)
	return Rect2i(best.position + Vector2i(40, 40), size)


static func encode(r: Rect2i, fullscreen: bool) -> Dictionary:
	return {"x": r.position.x, "y": r.position.y, "w": r.size.x, "h": r.size.y, "fullscreen": fullscreen}


static func valid_state(d: Variant) -> bool:
	if typeof(d) != TYPE_DICTIONARY:
		return false
	for k in ["x", "y", "w", "h"]:
		if not d.has(k) or not (d[k] is float or d[k] is int):
			return false
	return int(d.w) >= MIN_SIZE.x and int(d.h) >= MIN_SIZE.y and int(d.w) <= 16384 and int(d.h) <= 16384


static func load_state(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		return {}
	return json.data if valid_state(json.data) else {}


# ------------------------------------------------------------------ live window

static func screens() -> Array[Rect2i]:
	var out: Array[Rect2i] = []
	for i in DisplayServer.get_screen_count():
		out.append(DisplayServer.screen_get_usable_rect(i))
	return out


func decoration() -> Vector2i:
	if window == null:
		return Vector2i(0, 32)
	var with_deco := window.get_size_with_decorations()
	var d := with_deco - window.size
	return Vector2i(maxi(d.x, 0), maxi(d.y, 0)) if d.y > 0 else Vector2i(0, 32)


func side_rect(side: String) -> Rect2i:
	var screen := DisplayServer.get_primary_screen() if window == null else window.current_screen
	return side_rect_for(DisplayServer.screen_get_usable_rect(screen), decoration(), side)


func apply_rect(r: Rect2i) -> void:
	if window.mode == Window.MODE_FULLSCREEN:
		window.mode = Window.MODE_WINDOWED
	window.size = r.size
	window.position = r.position


func snapshot() -> Dictionary:
	return encode(Rect2i(window.position, window.size), window.mode == Window.MODE_FULLSCREEN)


func save() -> void:
	if window == null:
		return
	if window.mode != Window.MODE_WINDOWED and window.mode != Window.MODE_FULLSCREEN:
		return   # minimised/maximised sizes are not worth restoring
	var state := snapshot()
	if window.mode == Window.MODE_FULLSCREEN and not _last.is_empty():
		state = _last.duplicate()   # keep the windowed rectangle, remember only the fullscreen flag
		state.fullscreen = true
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(state))
		f.close()
	_dirty = false


func snap(side: String) -> void:
	apply_rect(side_rect(side))


func toggle_fullscreen() -> void:
	if window.mode == Window.MODE_FULLSCREEN:
		window.mode = Window.MODE_WINDOWED
	else:
		_last = snapshot()
		window.mode = Window.MODE_FULLSCREEN


func _process(delta: float) -> void:
	if window == null or window.mode != Window.MODE_WINDOWED:
		return
	var now := snapshot()
	if now != _last:
		_last = now
		_dirty = true
		_since_change = 0.0
	elif _dirty:
		_since_change += delta
		if _since_change >= SAVE_DELAY:
			save()


func _unhandled_key_input(event: InputEvent) -> void:
	if window == null or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_F6:
			snap("left")
		KEY_F7:
			snap("right")
		KEY_F8:
			snap("center")
		KEY_F11:
			toggle_fullscreen()
		_:
			return
	get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		if window != null and is_instance_valid(window):
			save()
