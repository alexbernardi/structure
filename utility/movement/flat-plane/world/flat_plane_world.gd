## Builds the flat-plane test world from Godot primitives only: a large plane with a measurement grid, lighting,
## procedural sky, ramps at fixed angles, stair flights, obstacles of known heights, a low tunnel, a ledge and a
## respawn pad. Static geometry lives on physics layer 1. Units are metres.
extends Node3D

const GRID_SHADER := preload("res://world/grid.gdshader")

const PLANE_SIZE := 400.0
const RAMP_ANGLES := [10.0, 20.0, 30.0, 40.0, 50.0]
const OBSTACLE_HEIGHTS := [0.25, 0.5, 0.75, 1.0, 1.5, 2.0]

var spawn_transform := Transform3D(Basis.IDENTITY, Vector3(0.0, 0.05, 0.0))
var material: ShaderMaterial
var landmarks: Dictionary = {}   # name -> Vector3, for tests and teleport shortcuts


func build() -> void:
	material = ShaderMaterial.new()
	material.shader = GRID_SHADER
	_environment()
	_plane()
	_ramps()
	_stairs()
	_obstacles()
	_tunnel_and_ledge()
	_spawn_pad()
	_axis_labels()


func _environment() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-52.0, -35.0, 0.0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 80.0
	add_child(sun)
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.30, 0.50, 0.85)
	sky_mat.sky_horizon_color = Color(0.70, 0.80, 0.92)
	sky_mat.ground_horizon_color = Color(0.70, 0.80, 0.92)
	sky_mat.ground_bottom_color = Color(0.45, 0.50, 0.58)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	add_child(we)


## Static box. `rot_deg` rotates about the node origin; `size` is the full extent.
func _box(pos: Vector3, size: Vector3, rot_deg := Vector3.ZERO, mat: Material = null, node_name := "Box") -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = pos
	body.rotation_degrees = rot_deg
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mesh.mesh = bm
	mesh.material_override = mat if mat else material
	body.add_child(mesh)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	add_child(body)
	return body


func _tint(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.8
	return m


func _plane() -> void:
	_box(Vector3(0, -0.5, 0), Vector3(PLANE_SIZE, 1.0, PLANE_SIZE), Vector3.ZERO, null, "Plane")


## Ramps rise toward -Z, 4 m wide, 6 m of horizontal run, at 10-50 degrees (46 is the default walkable limit).
func _ramps() -> void:
	var run := 6.0
	for i in RAMP_ANGLES.size():
		var a: float = RAMP_ANGLES[i]
		var x := -12.0 + i * 6.0
		var slope_len := run / cos(deg_to_rad(a))
		var body := _box(Vector3(x, 0, -14.0), Vector3(4.0, 0.4, slope_len), Vector3(a, 0, 0), null, "Ramp%d" % int(a))
		# the box is centred on its origin; shift it so its top surface starts at the ground line and rises along -Z
		for c in body.get_children():
			c.position = Vector3(0, -0.2, -slope_len / 2.0)
		var label := Label3D.new()
		label.text = "%d deg" % int(a)
		label.pixel_size = 0.006
		label.font_size = 64
		label.position = Vector3(x, 0.6, -13.0)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		add_child(label)
		landmarks["ramp_%d" % int(a)] = Vector3(x, 0.0, -11.0)


## Three flights toward +X: 0.18 m risers (easy), 0.30 m (inside the default step height), 0.50 m (blocks: needs a jump).
func _stairs() -> void:
	var rises := [0.18, 0.30, 0.50]
	for f in rises.size():
		var z := 8.0 + f * 5.0
		var rise: float = rises[f]
		var count := 8
		for s in count:
			var h := rise * (s + 1)
			_box(Vector3(8.0 + s * 0.32 + 0.16, h / 2.0, z), Vector3(0.32, h, 3.0), Vector3.ZERO, null, "Stair%d_%d" % [f, s])
		landmarks["stairs_%.2f" % rise] = Vector3(7.0, 0.0, z)


func _obstacles() -> void:
	for i in OBSTACLE_HEIGHTS.size():
		var h: float = OBSTACLE_HEIGHTS[i]
		_box(Vector3(-10.0 + i * 3.0, h / 2.0, 12.0), Vector3(1.5, h, 1.5), Vector3.ZERO, _tint(Color(0.85, 0.55, 0.25)), "Block%d" % int(round(h * 100.0)))
		var label := Label3D.new()
		label.text = "%.2f m" % h
		label.pixel_size = 0.006
		label.font_size = 64
		label.position = Vector3(-10.0 + i * 3.0, h + 0.4, 12.0)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		add_child(label)
	landmarks["blocks"] = Vector3(-10.0, 0.0, 9.5)
	# pillars (cylinders) and a boulder (sphere) to slide around
	for i in 3:
		var pillar := StaticBody3D.new()
		pillar.name = "Pillar%d" % i
		pillar.position = Vector3(-10.0 + i * 4.0, 1.5, 22.0)
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.6
		cm.bottom_radius = 0.6
		cm.height = 3.0
		mi.mesh = cm
		mi.material_override = _tint(Color(0.55, 0.60, 0.70))
		pillar.add_child(mi)
		var col := CollisionShape3D.new()
		var cs := CylinderShape3D.new()
		cs.radius = 0.6
		cs.height = 3.0
		col.shape = cs
		pillar.add_child(col)
		add_child(pillar)
	var boulder := StaticBody3D.new()
	boulder.name = "Boulder"
	boulder.position = Vector3(6.0, 1.2, -6.0)
	var sm := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 1.2
	sph.height = 2.4
	sm.mesh = sph
	sm.material_override = _tint(Color(0.50, 0.65, 0.50))
	boulder.add_child(sm)
	var scol := CollisionShape3D.new()
	var ss := SphereShape3D.new()
	ss.radius = 1.2
	scol.shape = ss
	boulder.add_child(scol)
	add_child(boulder)
	# a long wall to run along and bump into
	_box(Vector3(0, 1.5, -40.0), Vector3(60.0, 3.0, 0.6), Vector3.ZERO, null, "Wall")


## A 1.3 m-high lintel (crouch to pass) and a 1 m ledge you can walk off (coyote time).
func _tunnel_and_ledge() -> void:
	var tint := _tint(Color(0.55, 0.45, 0.65))
	_box(Vector3(-4.0, 0.9, 26.0), Vector3(0.4, 1.8, 3.0), Vector3.ZERO, tint, "TunnelL")
	_box(Vector3(-8.0, 0.9, 26.0), Vector3(0.4, 1.8, 3.0), Vector3.ZERO, tint, "TunnelR")
	# columns at x = -4.0 and -8.0 hold the lintel: clear width 3.6 m, clear height 1.3 m
	_box(Vector3(-6.0, 1.55, 26.0), Vector3(4.4, 0.5, 3.0), Vector3.ZERO, tint, "Lintel")
	landmarks["tunnel"] = Vector3(-6.0, 0.0, 22.5)
	_box(Vector3(16.0, 0.5, -10.0), Vector3(6.0, 1.0, 12.0), Vector3.ZERO, _tint(Color(0.45, 0.65, 0.75)), "Ledge")
	landmarks["ledge"] = Vector3(16.0, 1.05, -10.0)


func _spawn_pad() -> void:
	var pad := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.0
	cm.bottom_radius = 1.0
	cm.height = 0.04
	pad.mesh = cm
	pad.material_override = _tint(Color(0.95, 0.80, 0.2))
	pad.position = Vector3(0, 0.02, 0)
	pad.name = "SpawnPad"
	add_child(pad)
	var arrow := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.25, 0.05, 0.7)
	arrow.mesh = bm
	arrow.material_override = _tint(Color(0.1, 0.1, 0.1))
	arrow.position = Vector3(0, 0.05, -0.5)
	add_child(arrow)
	landmarks["spawn"] = spawn_transform.origin


func _axis_labels() -> void:
	for i in range(1, 7):
		var d := i * 10.0
		for axis in [Vector3.RIGHT, Vector3.FORWARD]:
			var label := Label3D.new()
			label.text = "%d m" % int(d)
			label.pixel_size = 0.01
			label.font_size = 64
			label.position = axis * d + Vector3(0, 0.05, 0)
			label.rotation_degrees = Vector3(-90, 0, 0)
			label.modulate = Color(0.85, 0.2, 0.2) if axis == Vector3.RIGHT else Color(0.2, 0.35, 0.9)
			add_child(label)
