## Measurement scenery for the Vitruvian lab: ground plane, metric grid (0.1 m / 1 m), stature ruler, arm-span bar
## and the Vitruvian square and circle (square side = stature; circle centred on the navel, tangent to the ground).
extends Node3D

const SEPIA := Color(0.62, 0.38, 0.18)

var show_grid := true
var show_rulers := true
var show_vitruvian := true

var _grid: MeshInstance3D
var _measure: MeshInstance3D
var _vitruvian: MeshInstance3D
var _labels: Array[Label3D] = []
var _vitruvian_labels: Array[Label3D] = []


func _ready() -> void:
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(12, 12)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.86, 0.84, 0.79)
	gm.roughness = 1.0
	ground.material_override = gm
	ground.position.y = -0.001
	add_child(ground)
	_grid = _line_node(false)
	_measure = _line_node(true)
	_vitruvian = _line_node(true)
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in range(-50, 51):
		var x := i * 0.1
		var c := Color(0.25, 0.25, 0.25, 0.7) if i % 10 == 0 else Color(0.45, 0.45, 0.45, 0.22)
		_seg(im, Vector3(x, 0.0005, -5), Vector3(x, 0.0005, 5), c)
		_seg(im, Vector3(-5, 0.0005, x), Vector3(5, 0.0005, x), c)
	im.surface_end()
	_grid.mesh = im


func _line_node(on_top: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.no_depth_test = on_top
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


static func _seg(im: ImmediateMesh, a: Vector3, b: Vector3, c: Color) -> void:
	im.surface_set_color(c)
	im.surface_add_vertex(a)
	im.surface_set_color(c)
	im.surface_add_vertex(b)


func _label(text: String, at: Vector3, colour := Color(0.1, 0.1, 0.1), size := 26) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.position = at
	l.font_size = size
	l.pixel_size = 0.001
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.modulate = colour
	l.outline_modulate = Color(1, 1, 1, 0.8)
	l.outline_size = 8
	add_child(l)
	return l


## Rebuilds rulers and the Vitruvian figure from a rig definition (rig_builder.build).
func update_from(definition: Dictionary) -> void:
	for l in _labels + _vitruvian_labels:
		l.queue_free()
	_labels.clear()
	_vitruvian_labels.clear()
	var m: Dictionary = definition.measurements
	var lm: Dictionary = definition.landmarks
	var h: float = m.stature
	var span: float = m.arm_span
	var ink := Color(0.1, 0.1, 0.12, 0.95)
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	# Stature ruler beside the character's left (screen right in the front view), ticks every 10 cm.
	var rx: float = maxf(span * 0.5, h * 0.5) + 0.25
	var rz := -0.45   # behind the body, so the ruler also stands clear of it in the side view
	_seg(im, Vector3(rx, 0, rz), Vector3(rx, h, rz), ink)
	var cm := 0
	while cm * 0.1 <= h + 1e-6:
		var w := 0.06 if cm % 5 == 0 else 0.03
		_seg(im, Vector3(rx - w, cm * 0.1, rz), Vector3(rx, cm * 0.1, rz), ink)
		if cm % 5 == 0 and cm > 0:
			_labels.append(_label("%.1f m" % (cm * 0.1), Vector3(rx + 0.12, cm * 0.1, rz), ink, 22))
		cm += 1
	_seg(im, Vector3(rx - 0.15, h, rz), Vector3(rx + 0.05, h, rz), Color(0.8, 0.1, 0.1))
	_seg(im, Vector3(-0.08, h, 0), Vector3(rx - 0.15, h, rz), Color(0.8, 0.1, 0.1, 0.35))
	_labels.append(_label("stature %.3f m" % h, Vector3(rx + 0.05, h + 0.06, rz), Color(0.75, 0.05, 0.05)))
	# Arm span bar above the fingertips.
	var y: float = (lm.fingertip_l as Vector3).y + 0.14
	var fl: Vector3 = lm.fingertip_l
	var fr: Vector3 = lm.fingertip_r
	_seg(im, Vector3(fr.x, y, fr.z), Vector3(fl.x, y, fl.z), ink)
	for p in [fl, fr]:
		_seg(im, Vector3(p.x, y - 0.04, p.z), Vector3(p.x, y + 0.04, p.z), ink)
		_seg(im, Vector3(p.x, y - 0.04, p.z), p, Color(0.1, 0.1, 0.12, 0.3))
	_labels.append(_label("arm span %.3f m  (%.3f x stature)" % [span, span / h], Vector3(0, y + 0.06, 0), ink))
	# Hip-joint and navel levels (where Leonardo puts the half height and the circle's centre).
	_seg(im, Vector3(-rx, m.hip_joint_height, 0), Vector3(-rx + 0.12, m.hip_joint_height, 0), ink)
	_labels.append(_label("hip joints %.3f m" % m.hip_joint_height, Vector3(-rx - 0.05, m.hip_joint_height + 0.05, 0), ink, 20))
	im.surface_end()
	_measure.mesh = im
	# Vitruvian square and circle.
	var vm := ImmediateMesh.new()
	vm.surface_begin(Mesh.PRIMITIVE_LINES)
	var s := h * 0.5
	var corners := [Vector3(-s, 0, 0), Vector3(s, 0, 0), Vector3(s, h, 0), Vector3(-s, h, 0)]
	for i in 4:
		_seg(vm, corners[i], corners[(i + 1) % 4], SEPIA)
	var navel: float = m.navel_height
	var prev := Vector3(0, 0, 0)
	for i in range(1, 129):
		var a := TAU * i / 128.0
		var p := Vector3(sin(a) * navel, navel - cos(a) * navel, 0)
		_seg(vm, prev, p, SEPIA)
		prev = p
	_seg(vm, Vector3(-0.03, navel, 0), Vector3(0.03, navel, 0), SEPIA)
	vm.surface_end()
	_vitruvian.mesh = vm
	_vitruvian_labels.append(_label("square: stature x stature   circle: centre navel (%.3f m)" % navel,
		Vector3(0, -0.07, 0), SEPIA, 20))
	refresh_visibility()


func refresh_visibility() -> void:
	_grid.visible = show_grid
	_measure.visible = show_rulers
	for l in _labels:
		l.visible = show_rulers
	_vitruvian.visible = show_vitruvian
	for l in _vitruvian_labels:
		l.visible = show_vitruvian
