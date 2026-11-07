## Drag-and-drop editing of the humanoid's proportions in the treadmill lab. While `gait.edit_rig` is on, every joint and limb
## shows a handle; dragging one changes the matching rig parameter (animation/rig_params.gd) live:
##   orange  = a bone's length (drag the joint along the bone), also the foot length and the ankle height;
##   purple  = a joint's distance from the centre line (hips, shoulders) and the torso width: drag sideways, front/back/3-4 views;
##   green   = a limb's thickness (drag the edge of the limb), the head's size and the torso depth.
## Nothing is hard-wired to a handle's meaning: each handle names the parameter it drives, and the same parameters are on the
## controller (banks Proportions 1 and 2), in presets and in the HUD. Reads the posed skeleton, writes only rig parameters.
extends Control

const ORANGE := Color(1.0, 0.62, 0.2)
const PURPLE := Color(0.75, 0.5, 1.0)
const GREEN := Color(0.4, 0.95, 0.5)
const GRAB_PX := 15.0

var scene
var hovered := -1
var dragging := -1

var _handles: Array[Dictionary] = []
var _accumulated := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func active() -> bool:
	return scene != null and scene.gait_params.is_on("edit_rig") and not (scene.tuning != null and scene.tuning.editor != null and scene.tuning.editor.visible)


func _process(_delta: float) -> void:
	if active():
		_handles = build_handles()
	elif not _handles.is_empty():
		_handles.clear()
		hovered = -1
		dragging = -1
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	queue_redraw()


# ------------------------------------------------------------------ the handles

func _joint(bone: String) -> Vector3:
	var v = scene.visual
	return v.to_global(v.joint_position(bone))


func _axis(bone: String, local: Vector3) -> Vector3:
	var v = scene.visual
	return (v.global_transform.basis * v.skeleton.get_bone_global_pose(v.bone_index[bone]).basis * local).normalized()


func _point(bone: String, local: Vector3) -> Vector3:
	var v = scene.visual
	return v.to_global(v.skeleton.get_bone_global_pose(v.bone_index[bone]) * local)


func _h(label: String, param: String, pos: Vector3, dir: Vector3, kind: String, gain: float, hint: String) -> Dictionary:
	return {"label": label, "param": param, "pos": pos, "dir": dir, "kind": kind, "gain": gain, "hint": hint}


## Every handle with its world position, the world direction that increases its parameter and the parameter change per metre
## of drag along that direction. Positions come from the posed skeleton, so the handles stay on the joints at any pose.
func build_handles() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var d: Dictionary = scene.visual.dims
	var k: float = d.scale
	var cam: Camera3D = scene.cam
	var cam_right := cam.global_transform.basis.x
	var cam_fwd := -cam.global_transform.basis.z
	var pelvis := _joint("pelvis")
	var hip := _joint("thigh_l")
	var knee := _joint("shin_l")
	var ankle := _joint("foot_l")
	var chest := _joint("chest")
	var neck := _joint("neck")
	var head := _joint("head")
	var shoulder := _joint("upper_arm_l")
	var elbow := _joint("forearm_l")
	var wrist := _point("forearm_l", Vector3(0.0, -d.forearm, 0.0))
	out.append(_h("Thigh length", "thigh_length", knee, (knee - hip).normalized(), "bone", 1.0 / k, "drag along the thigh"))
	out.append(_h("Shin length", "shin_length", ankle, (ankle - knee).normalized(), "bone", 1.0 / k, "drag along the shin"))
	out.append(_h("Foot length", "foot_length", _point("foot_l", Vector3(0.0, -d.ankle_h, -d.toe.x)), _axis("foot_l", Vector3(0, 0, -1)), "bone", 1.0 / (k * 0.74), "drag the toe forward or back"))
	out.append(_h("Ankle height", "ankle_height", _point("foot_l", Vector3(0.0, -d.ankle_h, 0.0)), _axis("foot_l", Vector3(0, -1, 0)), "bone", 1.0 / k, "drag the sole down to raise the ankle"))
	out.append(_h("Lower torso length", "torso_length", chest, (chest - pelvis).normalized(), "bone", 1.0 / k, "drag the chest joint along the spine"))
	out.append(_h("Chest length", "chest_length", neck, (neck - chest).normalized(), "bone", 1.0 / k, "drag the base of the neck"))
	out.append(_h("Neck length", "neck_length", head, (head - neck).normalized(), "bone", 1.0 / k, "drag the head up or down"))
	out.append(_h("Upper arm length", "upper_arm_length", elbow, (elbow - shoulder).normalized(), "bone", 1.0 / k, "drag the elbow along the upper arm"))
	out.append(_h("Forearm length", "forearm_length", wrist, (wrist - elbow).normalized(), "bone", 1.0 / k, "drag the wrist along the forearm"))
	for side in ["l", "r"]:
		var sx := -1.0 if side == "l" else 1.0
		var out_dir := Vector3(sx, 0.0, 0.0)
		out.append(_h("Hip joint offset", "hip_width", _joint("thigh_" + side), out_dir, "width", 1.0 / k, "drag sideways (front, back or 3/4 view)"))
		out.append(_h("Shoulder joint offset", "shoulder_width", _joint("upper_arm_" + side), out_dir, "width", 1.0 / k, "drag sideways (front, back or 3/4 view)"))
	var chest_c := chest + Vector3(0.0, d.chest * (0.12 / 0.26), 0.0)
	var half_w: float = maxf(2.0 * d.shoulder_x - 0.10 * k, 0.1 * k) * 0.5
	out.append(_h("Torso width", "torso_width", chest_c + Vector3(half_w * d.torso_w, 0.0, 0.0), Vector3(1, 0, 0), "width", 1.0 / half_w, "drag the side of the chest sideways"))
	out.append(_h("Torso width", "torso_width", chest_c - Vector3(half_w * d.torso_w, 0.0, 0.0), Vector3(-1, 0, 0), "width", 1.0 / half_w, "drag the side of the chest sideways"))
	var half_d: float = 0.21 * k * 0.5
	var fwd := _axis("chest", Vector3(0, 0, -1))
	out.append(_h("Torso depth", "torso_depth", chest_c + fwd * half_d * d.torso_d, fwd, "radius", 1.0 / half_d, "drag the front of the chest"))
	# thickness: the edge of each limb, perpendicular to it as seen by the camera
	var limbs := [["Thigh thickness", "thigh_radius", hip, knee, d.thigh_r], ["Shin thickness", "shin_radius", knee, ankle, d.shin_r],
		["Upper arm thickness", "upper_arm_radius", shoulder, elbow, d.upper_arm_r], ["Forearm thickness", "forearm_radius", elbow, wrist, d.forearm_r]]
	for l in limbs:
		var a: Vector3 = l[2]
		var b: Vector3 = l[3]
		var perp := cam_fwd.cross((b - a).normalized()).normalized()
		out.append(_h(l[0], l[1], (a + b) * 0.5 + perp * float(l[4]), perp, "radius", 1.0 / k, "drag the edge of the limb"))
	var head_c := head + Vector3(0.0, d.head_r * (6.0 / 7.0), 0.0)
	out.append(_h("Head size", "head_radius", head_c + cam_right * d.head_r, cam_right, "radius", 1.0 / k, "drag the edge of the head"))
	return out


func _visible(h: Dictionary) -> bool:
	if h.kind == "width" and scene.view == "side" or h.kind == "width" and scene.view == "side-left":
		return false   # sideways offsets cannot be dragged in a pure side view
	return not scene.cam.is_position_behind(h.pos)


func _screen(h: Dictionary) -> Vector2:
	return scene.cam.unproject_position(h.pos)


func nearest(mouse: Vector2) -> int:
	var best := -1
	var best_d := GRAB_PX
	for i in _handles.size():
		if not _visible(_handles[i]):
			continue
		var dist := _screen(_handles[i]).distance_to(mouse)
		if dist < best_d:
			best_d = dist
			best = i
	return best


## World metres per screen pixel at a world point.
func _metres_per_pixel(world: Vector3) -> float:
	var cam: Camera3D = scene.cam
	var h_px := maxf(float(scene.get_viewport().get_visible_rect().size.y), 1.0)
	if cam.projection == Camera3D.PROJECTION_ORTHOGONAL:
		return cam.size / h_px
	var depth := absf((world - cam.global_position).dot(-cam.global_transform.basis.z))
	return 2.0 * depth * tan(deg_to_rad(cam.fov) * 0.5) / h_px


# ------------------------------------------------------------------ input

## Returns true when the event was used (the scene then ignores it).
func handle_input(event: InputEvent) -> bool:
	if not active():
		return false
	if event is InputEventMouseMotion:
		if dragging >= 0:
			_drag(event.relative)
			return true
		hovered = nearest(event.position)
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if hovered >= 0 else Input.CURSOR_ARROW)
		return false
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var i := nearest(event.position)
			if i >= 0:
				dragging = i
				hovered = i
				_accumulated = float(scene.rig_params.get_value(_handles[i].param))
				return true
		elif dragging >= 0:
			dragging = -1
			return true
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_BACKSPACE:
		scene.rig_params.reset_all()
		if scene.tuning != null:
			scene.tuning.toast.emit("Proportions reset to the original rig", "info")
		return true
	return false


func _drag(relative: Vector2) -> void:
	var h: Dictionary = _handles[dragging]
	var cam: Camera3D = scene.cam
	var mpp := _metres_per_pixel(h.pos)
	var world := cam.global_transform.basis.x * relative.x * mpp - cam.global_transform.basis.y * relative.y * mpp
	var along: float = world.dot(h.dir)
	_accumulated += along * float(h.gain)
	scene.rig_params.set_value(h.param, _accumulated)   # clamped and snapped by the parameter set
	var stored: float = scene.rig_params.get_value(h.param)
	if absf(_accumulated - stored) > 0.05 * maxf(absf(stored), 0.1):
		_accumulated = stored   # dragged past a limit: come back from the limit, not from where the mouse went


# ------------------------------------------------------------------ drawing

func _draw() -> void:
	if not active() or scene == null:
		return
	var font := ThemeDB.fallback_font
	var vis := 0
	for i in _handles.size():
		var h: Dictionary = _handles[i]
		if not _visible(h):
			continue
		vis += 1
		var col: Color = ORANGE if h.kind == "bone" else (PURPLE if h.kind == "width" else GREEN)
		var p := _screen(h)
		var live := i == hovered or i == dragging
		draw_circle(p, 8.0 if live else 5.5, Color(col, 0.9))
		draw_arc(p, 9.5 if live else 7.0, 0.0, TAU, 24, Color(1, 1, 1, 0.9 if live else 0.5), 2.0 if live else 1.0)
		if live:
			var dir_end := _screen({"pos": h.pos + h.dir * 0.12})
			draw_line(p, dir_end, Color(col, 0.9), 2.0)
			var value: float = scene.rig_params.get_value(h.param)
			var def: Dictionary = scene.rig_params.def(h.param)
			var text := "%s: %s   (%s)" % [h.label, ("%.3f %s" % [value, def.unit]).strip_edges(), h.hint]
			draw_string_outline(font, p + Vector2(14, -12), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, 4, Color(0, 0, 0, 0.9))
			draw_string(font, p + Vector2(14, -12), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 1, 1))
	var banner := "EDIT PROPORTIONS: drag handles (orange = bone length, purple = width, green = thickness)  |  Backspace resets  |  E leaves"
	if scene.view == "side" or scene.view == "side-left":
		banner += "  |  width handles: views 3, 4, 5"
	draw_string_outline(font, Vector2(18, size.y - 20), banner, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 4, Color(0, 0, 0, 0.9))
	draw_string(font, Vector2(18, size.y - 20), banner, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 0.9, 0.5))
