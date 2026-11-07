extends RefCounted

const WS = preload("res://scenes/window_state.gd")

const TMP := "user://test_window_state.json"
const SCREEN := Rect2i(0, 0, 1920, 1040)   # usable area: a 40 px taskbar is excluded
const DECO := Vector2i(16, 31)             # title bar + borders (outer size minus client size)


func after_each() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))


func test_left_half(t) -> void:
	var r := WS.side_rect_for(SCREEN, DECO, "left")
	t.eq(r.position.x, 0, "flush with the left edge")
	t.eq(r.size.x, (1920 - 16) / 2, "half the usable width")
	t.eq(r.position.y, 31, "title bar sits inside the screen, not above it")
	t.ok(r.position.y + r.size.y <= SCREEN.end.y, "bottom stays above the taskbar")


func test_right_half(t) -> void:
	var r := WS.side_rect_for(SCREEN, DECO, "right")
	t.ok(r.position.x >= SCREEN.size.x / 2 - 20, "starts at about the middle: %d" % r.position.x)
	t.ok(r.position.x + r.size.x + DECO.x / 2 <= SCREEN.end.x + 1 and r.position.x + r.size.x + DECO.x / 2 >= SCREEN.end.x - 1, "touches the right edge")


func test_halves_do_not_overlap(t) -> void:
	var l := WS.side_rect_for(SCREEN, DECO, "left")
	var r := WS.side_rect_for(SCREEN, DECO, "right")
	t.ok(l.position.x + l.size.x + DECO.x <= r.position.x + 1 or not l.intersects(r), "left and right halves sit side by side")


func test_center_is_smaller_and_centred(t) -> void:
	var c := WS.side_rect_for(SCREEN, DECO, "center")
	t.ok(c.size.x < SCREEN.size.x and c.size.y < SCREEN.size.y, "smaller than the screen")
	t.near(float(c.position.x + c.size.x / 2), 960.0, 2.0, "centred horizontally")
	var wide := WS.side_rect_for(Rect2i(0, 0, 3440, 1392), DECO, "center")
	t.ok(wide.size.x <= WS.CENTER_MAX.x and wide.size.y <= WS.CENTER_MAX.y, "capped on an ultrawide screen: %s" % str(wide.size))
	t.near(float(wide.position.x + wide.size.x / 2), 1720.0, 2.0, "and still centred")


func test_small_screens_never_go_below_the_minimum_size(t) -> void:
	var r := WS.side_rect_for(Rect2i(0, 0, 800, 600), DECO, "left")
	t.ok(r.size.x >= WS.MIN_SIZE.x and r.size.y >= WS.MIN_SIZE.y, "min size respected")


func test_second_monitor_with_negative_coordinates(t) -> void:
	var left_monitor := Rect2i(-1920, 0, 1920, 1040)
	var r := WS.side_rect_for(left_monitor, DECO, "left")
	t.eq(r.position.x, -1920, "left half of a monitor positioned left of the primary")
	var fitted := WS.fit_to_screens(Rect2i(-1500, 100, 900, 700), [left_monitor, SCREEN] as Array[Rect2i])
	t.eq(fitted, Rect2i(-1500, 100, 900, 700), "a window that is fully on a screen is left alone")


func test_saved_position_on_a_missing_monitor_is_recovered(t) -> void:
	var fitted := WS.fit_to_screens(Rect2i(3000, 200, 900, 700), [SCREEN] as Array[Rect2i])
	t.ok(SCREEN.encloses(Rect2i(fitted.position, Vector2i(100, 100))), "moved back onto the remaining screen: %s" % str(fitted))
	t.eq(fitted.size, Vector2i(900, 700), "size kept")


func test_oversized_saved_window_is_shrunk(t) -> void:
	var fitted := WS.fit_to_screens(Rect2i(0, 0, 5000, 3000), [SCREEN] as Array[Rect2i])
	t.ok(fitted.size.x <= SCREEN.size.x and fitted.size.y <= SCREEN.size.y, "fits the screen: %s" % str(fitted.size))


func test_title_bar_stays_reachable(t) -> void:
	var fitted := WS.fit_to_screens(Rect2i(500, -300, 900, 700), [SCREEN] as Array[Rect2i])
	t.ok(fitted.position.y >= 0, "title bar not above the screen: y = %d" % fitted.position.y)
	var far_left := WS.fit_to_screens(Rect2i(-880, 100, 900, 700), [SCREEN] as Array[Rect2i])
	t.ok(far_left.end.x >= 120, "some of the window remains to grab: x = %d..%d" % [far_left.position.x, far_left.end.x])


func test_state_validation(t) -> void:
	t.ok(WS.valid_state(WS.encode(Rect2i(10, 20, 800, 600), false)), "encoded state is valid")
	t.ok(not WS.valid_state({"x": 0, "y": 0, "w": 100, "h": 100}), "too small is rejected")
	t.ok(not WS.valid_state({"x": 0, "y": 0, "w": "wide", "h": 600}), "wrong types are rejected")
	t.ok(not WS.valid_state({"x": 0}), "missing keys are rejected")
	t.ok(not WS.valid_state([1, 2, 3]), "not an object")
	t.ok(not WS.valid_state({"x": 0, "y": 0, "w": 99999, "h": 600}), "absurd sizes are rejected")


func test_load_state_tolerates_garbage(t) -> void:
	t.eq(WS.load_state("user://no_such_window_state.json"), {}, "missing file")
	var f := FileAccess.open(TMP, FileAccess.WRITE)
	f.store_string("{ not json")
	f.close()
	t.eq(WS.load_state(TMP), {}, "corrupt file falls back to the default placement")


func test_save_and_reload_roundtrip(t) -> void:
	var w := Window.new()
	w.size = Vector2i(1111, 777)
	w.position = Vector2i(42, 84)
	var ws = WS.new()
	ws.window = w
	ws.save_path = TMP
	ws.save()
	var d := WS.load_state(TMP)
	t.eq([int(d.x), int(d.y), int(d.w), int(d.h)], [42, 84, 1111, 777], "position and size persisted")
	t.eq(d.fullscreen, false, "windowed")
	ws.window = null
	ws.free()
	w.free()
