## Measurement overlay of the treadmill gait lab, drawn over the 3D view: ground ruler, hip height, plumb line, the planned
## ankle path, joint markers read back from the real skeleton, the planted contact point of each foot, the gait diagram
## (stance / swing bars with the cycle position) and numbers. Everything here only reads; nothing feeds back.
extends Control

const Model = preload("res://animation/gait_model.gd")
const Visual = preload("res://systems/movement_core/character/character_visual.gd")

const LEFT := Color(0.40, 0.75, 1.0)
const RIGHT := Color(1.0, 0.62, 0.28)
const GUIDE := Color(1, 1, 1, 0.35)
const TEXT := Color(1, 1, 1, 0.95)
const DIM := Color(1, 1, 1, 0.6)
const PLANTED := Color(0.45, 1.0, 0.5)

var scene


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _process(_delta: float) -> void:
	queue_redraw()


func _p(world: Vector3) -> Vector2:
	return scene.cam.unproject_position(world)


func _draw() -> void:
	if scene == null or scene.cam == null or scene.visual == null:
		return
	var gp = scene.gait_params
	var pose: Dictionary = scene.model.pose
	if gp.is_on("view_guides"):
		_guides(gp)
	var active: bool = pose.get("active", false)
	if active:
		if gp.is_on("view_paths"):
			_paths(pose)
		_contacts(pose)
		if gp.is_on("view_joints"):
			_joints()
		if gp.is_on("view_diagram"):
			_diagram(pose)
	_text_block(pose)


func _txt(pos: Vector2, s: String, size := 15, color := TEXT) -> void:
	var font := ThemeDB.fallback_font
	draw_string_outline(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 4, Color(0, 0, 0, 0.85))
	draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


# ------------------------------------------------------------------ guides

func _guides(gp) -> void:
	# ground ruler along the walking direction: a tick every 0.1 m, longer every 0.5 m (the belt stripes are 0.25 m apart)
	draw_line(_p(Vector3(0, 0, -1.4)), _p(Vector3(0, 0, 1.4)), GUIDE, 1.5)
	for i in range(-14, 15):
		var z := float(i) * 0.1
		var big := i % 5 == 0
		var a := _p(Vector3(0, 0, -z))
		draw_line(a, a + Vector2(0, 9.0 if big else 5.0), GUIDE, 1.0)
		if big and i != 0:
			_txt(a + Vector2(-10, 24), "%.1f" % absf(z), 11, DIM)
	_txt(_p(Vector3(0, 0, 1.4)) + Vector2(10, 40), "metres ahead of the hips", 11, DIM)
	# standing hip height, and the plumb line through the hips
	var dm: Dictionary = scene.visual.dims
	var hip_h: float = dm.ankle_h + float(gp.get_value("stand_height")) * (dm.thigh + dm.shin)
	var a1 := _p(Vector3(0, hip_h, -0.9))
	var b1 := _p(Vector3(0, hip_h, 0.9))
	var n := 24
	for i in n:
		if i % 2 == 0:
			draw_line(a1.lerp(b1, float(i) / n), a1.lerp(b1, float(i + 1) / n), Color(1, 0.9, 0.4, 0.5), 1.0)
	_txt(b1 + Vector2(6, 4), "requested contact hip height", 11, Color(1, 0.9, 0.4, 0.8))
	draw_line(_p(Vector3(0, 0, 0)), _p(Vector3(0, 1.85, 0)), Color(1, 1, 1, 0.18), 1.0)


# ------------------------------------------------------------------ foot paths, joints, contacts

func _world(f: float, h: float, x := 0.0) -> Vector3:
	return Vector3(x, h, -f)


func _paths(pose: Dictionary) -> void:
	var pts: PackedVector2Array = scene.model.path_points()
	if pts.size() < 2:
		return
	var screen := PackedVector2Array()
	for q in pts:
		screen.append(_p(_world(q.x, q.y)))
	draw_polyline(screen, Color(1, 1, 1, 0.55), 1.5)
	for side in 2:
		var a: Vector3 = pose.ankle_l if side == 0 else pose.ankle_r
		draw_circle(_p(_world(a.x, a.y)), 4.0, LEFT if side == 0 else RIGHT)


func _joints() -> void:
	var v = scene.visual
	for side in 2:
		var s := "l" if side == 0 else "r"
		var col := LEFT if side == 0 else RIGHT
		var hip: Vector3 = v.to_global(v.joint_position("thigh_" + s))
		var knee: Vector3 = v.to_global(v.joint_position("shin_" + s))
		var ankle: Vector3 = v.to_global(v.joint_position("foot_" + s))
		var foot_pose: Transform3D = v.skeleton.get_bone_global_pose(v.bone_index["foot_" + s])
		var heel: Vector3 = v.to_global(foot_pose * Vector3(0.0, -v.dims.ankle_h, -v.dims.heel.x))
		var toe: Vector3 = v.to_global(foot_pose * Vector3(0.0, -v.dims.ankle_h, -v.dims.toe.x))
		var ph := _p(hip)
		var pk := _p(knee)
		var pa := _p(ankle)
		draw_polyline(PackedVector2Array([ph, pk, pa]), col, 2.0)
		draw_polyline(PackedVector2Array([_p(heel), pa, _p(toe)]), col, 2.0)
		for pt in [ph, pk, pa, _p(heel), _p(toe)]:
			draw_circle(pt, 3.5, col)
		draw_arc(pk, 7.0, 0.0, TAU, 20, col, 1.0)
	_upper_body(v)


## The trunk and head as a stick figure over the meshes: spine (yellow) pelvis -> waist -> chest -> base of the neck, neck and
## head (cyan) up to the crown, hip and shoulder lines (magenta), arms down to the fingertips, and the pelvis centre (teal).
func _upper_body(v) -> void:
	const SPINE := Color(1.0, 0.9, 0.2)
	const HEAD := Color(0.3, 0.95, 1.0)
	const GIRDLE := Color(1.0, 0.35, 0.9)
	const PELVIS := Color(0.2, 0.85, 0.75)
	var j := func(bone: String) -> Vector2: return _p(v.to_global(v.joint_position(bone)))
	var head_pose: Transform3D = v.skeleton.get_bone_global_pose(v.bone_index.head)
	var crown := _p(v.to_global(head_pose * Vector3(0.0, v.dims.head_r * 1.85, -v.dims.head_r * 0.15)))
	var spine := PackedVector2Array([j.call("pelvis"), j.call("spine"), j.call("chest"), j.call("neck")])
	draw_polyline(spine, SPINE, 2.5)
	draw_polyline(PackedVector2Array([j.call("neck"), j.call("head"), crown]), HEAD, 2.5)
	draw_line(j.call("thigh_l"), j.call("thigh_r"), GIRDLE, 2.0)
	draw_line(j.call("upper_arm_l"), j.call("upper_arm_r"), GIRDLE, 2.0)
	for side in 2:
		var s := "l" if side == 0 else "r"
		var col := LEFT if side == 0 else RIGHT
		var hand_len: float = v.dims.forearm * Visual.HAND_LENGTH_RATIO
		var wrist := _p(v.to_global(v.bone_tip("forearm_" + s, v.dims.forearm)))
		var tip := _p(v.to_global(v.bone_tip("forearm_" + s, v.dims.forearm + hand_len * 0.8)))
		var arm := PackedVector2Array([j.call("neck"), j.call("upper_arm_" + s), j.call("forearm_" + s), wrist, tip])
		draw_polyline(arm, col, 2.0)
		for pt in arm.slice(1):
			draw_circle(pt, 3.0, col)
	for pt in spine:
		draw_circle(pt, 3.5, SPINE)
	draw_circle(crown, 3.0, HEAD)
	draw_circle(j.call("head"), 3.5, HEAD)
	draw_arc(spine[0], 9.0, 0.0, TAU, 24, PELVIS, 2.5)


func _contacts(pose: Dictionary) -> void:
	var c: Dictionary = scene.model.cycle
	for side in 2:
		var q: float = pose.phase if side == 0 else fposmod(pose.phase + 0.5, 1.0)
		var contact: bool = pose.contact_l if side == 0 else pose.contact_r
		if not contact or c.is_empty():
			continue
		var f: float = scene.model.contact_point(q, c)
		var g := _p(_world(f, 0.0))
		draw_arc(g, 7.0, 0.0, TAU, 20, PLANTED, 2.0)
		draw_line(g + Vector2(0, -10), g + Vector2(0, 10), PLANTED, 1.0)


# ------------------------------------------------------------------ gait diagram

func _diagram(pose: Dictionary) -> void:
	var w := 440.0
	var h := 18.0
	var x0 := size.x - w - 24.0   # lower right, below the tuning HUD and clear of the walker
	var y0 := size.y - 112.0
	_txt(Vector2(x0, y0 - 8.0), "gait cycle (left heel strike = 0, right = 0.5)", 12, DIM)
	var d: float = pose.duty
	var dsup_col := Color(1, 1, 1, 0.08)
	for side in 2:
		var y := y0 + float(side) * (h + 8.0)
		var col := LEFT if side == 0 else RIGHT
		var off := 0.0 if side == 0 else 0.5
		draw_rect(Rect2(x0, y, w, h), Color(0, 0, 0, 0.35))
		draw_rect(Rect2(x0, y, w, h), DIM, false, 1.0)
		for seg in _segments(off, d):
			draw_rect(Rect2(x0 + seg.x * w, y, (seg.y - seg.x) * w, h), Color(col, 0.75))
		_txt(Vector2(x0 - 16.0, y + 14.0), "L" if side == 0 else "R", 12, col)
	if d > 0.5:   # both feet down
		for seg in _segments(0.5, d):
			var lo: float = maxf(seg.x, 0.0)
			var hi: float = minf(seg.y, d)
			if hi > lo:
				draw_rect(Rect2(x0 + lo * w, y0 - 3.0, (hi - lo) * w, 2.0 * h + 14.0), dsup_col)
	elif d < 0.5:
		for offset in [0.0, 0.5]:
			draw_rect(Rect2(x0 + (offset + d) * w, y0 - 3.0, (0.5 - d) * w, 2.0 * h + 14.0), Color(0.3, 0.9, 1.0, 0.18))
	var cx := x0 + float(pose.phase) * w
	draw_line(Vector2(cx, y0 - 5.0), Vector2(cx, y0 + 2.0 * h + 13.0), Color(1, 1, 1, 0.95), 2.0)
	var support := "cyan = flight (%.0f %%)" % (100.0 * pose.flight_fraction) if d < 0.5 else "light band = both feet down (%.0f %%)" % (100.0 * pose.double_support)
	_txt(Vector2(x0, y0 + 2.0 * h + 30.0), "filled = foot on the ground    " + support, 11, DIM)


## Stance interval [off, off + d) as one or two pieces in 0..1.
static func _segments(off: float, d: float) -> Array[Vector2]:
	var end := off + d
	if end <= 1.0:
		return [Vector2(off, end)]
	return [Vector2(off, 1.0), Vector2(0.0, end - 1.0)]


# ------------------------------------------------------------------ numbers

func _text_block(pose: Dictionary) -> void:
	var y := 26.0
	if not pose.get("active", false):
		_txt(Vector2(18, y), "Gait model OFF - the original simple walk is showing (Toggles bank, strip 1 fader)", 15, Color(1, 0.8, 0.4))
		return
	_txt(Vector2(18, y), "%s %.2f m/s   step %.2f m   cadence %.0f steps/min%s" % [
		"RUN" if pose.running else "walk", pose.speed, pose.step_length, pose.cadence, "   FLIGHT" if pose.flight else ""])
	y += 22.0
	var support := "flight %.0f %%" % (100.0 * pose.flight_fraction) if pose.running else "double support %.0f %%" % (100.0 * pose.double_support)
	_txt(Vector2(18, y), "stride %.2f m / %.2f s   stance %.0f %%   %s   position %.3f" % [
		pose.stride_length, pose.stride_time if is_finite(pose.stride_time) else 0.0, 100.0 * pose.duty, support, pose.phase], 14, DIM)
	y += 20.0
	var assist_mm: float = 1000.0 * pose.reach_assist
	_txt(Vector2(18, y), "hips lowered by %.0f mm so no knee has to lock straight" % assist_mm, 14, DIM if assist_mm < 60.0 else Color(1, 0.8, 0.4))
	y += 20.0
	_txt(Vector2(18, y), "foot slip on the belt, measured on the skeleton: L %.0f  R %.0f mm/s" % [1000.0 * scene.slip_l, 1000.0 * scene.slip_r], 14, DIM)
	y += 20.0
	_txt(Vector2(18, y), "knee flexion: L %.0f  R %.0f deg (0 = straight)   |   P edit ankle path" % [rad_to_deg(pose.knee_l), rad_to_deg(pose.knee_r)], 14, DIM)
	y += 20.0
	if scene.gait_params.is_on("freeze"):
		_txt(Vector2(18, y), "FROZEN at cycle position %.3f  ( , and . step it; Space resumes )" % pose.phase, 14, Color(1, 0.85, 0.4))
