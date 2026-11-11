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
	_vault_course()
	_traversal_course()
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


## Vault course: three 3 m-wide lanes run toward +X, an obstacle every 9 m (landmarks vault_a/b/c face down the lanes).
##   A (z -25): walls 0.35 m deep at 0.80, 0.95, 1.10, 1.25 m (vaultable) and 1.60 m (rejected: too high)
##   B (z -30): 1.0 m walls turned 20 deg (vaultable) and 40 deg (rejected), 0.6 m deep (vaultable), 1.4 m deep (rejected)
##   C (z -35): 1.0 m wall onto a +0.25 m landing, then up a 0.2 m step and over a 1.0 m wall down 0.45 m to the ground
func _vault_course() -> void:
	var tint := _tint(Color(0.80, 0.42, 0.36))
	var heights := [0.80, 0.95, 1.10, 1.25, 1.60]
	for i in heights.size():
		var h: float = heights[i]
		_course_wall(Vector3(-18.0 + i * 9.0, 0.0, -25.0), h, 0.35, 0.0, tint, "VaultA%d" % int(round(h * 100.0)), "%.2f m" % h)
	_course_wall(Vector3(-18.0, 0.0, -30.0), 1.0, 0.35, 20.0, tint, "VaultB20", "20 deg")
	_course_wall(Vector3(-9.0, 0.0, -30.0), 1.0, 0.35, 40.0, tint, "VaultB40", "40 deg")
	_course_wall(Vector3(0.0, 0.0, -30.0), 1.0, 0.6, 0.0, tint, "VaultB60", "0.6 m deep")
	_course_wall(Vector3(9.0, 0.0, -30.0), 1.0, 1.4, 0.0, tint, "VaultB140", "1.4 m deep")
	var deck := _tint(Color(0.62, 0.62, 0.58))
	_course_wall(Vector3(-18.0, 0.0, -35.0), 1.0, 0.35, 0.0, tint, "VaultC1", "+0.25 m landing")
	_box(Vector3(-14.4125, 0.125, -35.0), Vector3(6.825, 0.25, 3.0), Vector3.ZERO, deck, "VaultDeckLow")
	_box(Vector3(-6.4125, 0.225, -35.0), Vector3(9.175, 0.45, 3.0), Vector3.ZERO, deck, "VaultDeckHigh")
	_course_wall(Vector3(-1.65, 0.0, -35.0), 1.45, 0.35, 0.0, tint, "VaultC2", "-0.45 m landing")
	for lane in [["a", -25.0], ["b", -30.0], ["c", -35.0]]:
		landmarks["vault_" + String(lane[0])] = Vector3(-27.0, 0.0, lane[1])


## Movement Lab 5.0 traversal course: four more 3 m-wide lanes toward +X, east of the vault course (landmarks lane_d ..
## lane_g at x 33, facing down the lane). Every obstacle is a plain box: the traversal system reads geometry only.
##   D (z -25) rhythm   - five 1.0 m walls 6 m apart, then a pair 3.6 m apart (a vault lands inside the next one's
##                        region: chain with a press during the descent), then a 0.8 m wall
##   E (z -31) climb    - 1.0 m block 2.5 m deep (too deep to vault: mantle onto it, run off), 1.4 m platform (mantle),
##                        1.9 m ledge (too high to mantle from the ground: jump and grab), 3.0 m ledge (beyond a
##                        human's grab: cybernetic jump or zephyr double jump), then 1.6 m wall (cybernetic vault)
##   F (z -37) invalid  - the test bar: a 1.0 m wall with a bar 1.2 m beyond it at 1.68-1.83 m. The bar blocks every
##                        vault arc (refused: blocked). Human solution: jump at the wall, press again to catch its top and
##                        climb over into the gap, then crouch under the bar or jump and catch the bar to climb over it.
##                        A 2 m deck ending in a 1.0 m wall over a 2 m
##                        drop (lane_f_drop; human landing refused, cybernetic accepts), a 0.4 m-wide post (narrow), a 1.0 m wall at 30 degrees, and a
##                        1.3 m block under an overhang (no headroom to mantle)
##   G (z -43) heights  - 1.2 m platform with a 1.0 m vault wall on it, a 5 m gap (sprint to clear it, or air jump)
##                        to a second 1.2 m platform, and a drop back to the ground over a 1.0 m wall
func _traversal_course() -> void:
	var wall := _tint(Color(0.80, 0.42, 0.36))
	var block := _tint(Color(0.36, 0.55, 0.80))
	var gate := _tint(Color(0.75, 0.35, 0.80))
	var bad := _tint(Color(0.35, 0.35, 0.35))
	var x0 := 40.0
	# D: rhythm
	for i in 5:
		_course_wall(Vector3(x0 + i * 6.0, 0.0, -25.0), 1.0, 0.35, 0.0, wall, "LaneD%d" % i, "1.0 m")
	_course_wall(Vector3(x0 + 30.0, 0.0, -25.0), 1.0, 0.35, 0.0, wall, "LaneDPairA", "pair")
	_course_wall(Vector3(x0 + 33.6, 0.0, -25.0), 1.0, 0.35, 0.0, wall, "LaneDPairB", "3.6 m")
	_course_wall(Vector3(x0 + 40.0, 0.0, -25.0), 0.8, 0.35, 0.0, wall, "LaneD80", "0.8 m")
	# E: climb
	_course_wall(Vector3(x0 + 1.25, 0.0, -31.0), 1.0, 2.5, 0.0, block, "LaneEBlock", "1.0 m x 2.5 m deep")
	_course_wall(Vector3(x0 + 10.0, 0.0, -31.0), 1.4, 3.0, 0.0, block, "LaneEPlatform", "1.4 m platform")
	_course_wall(Vector3(x0 + 20.0, 0.0, -31.0), 1.9, 3.0, 0.0, block, "LaneELedge19", "1.9 m: jump + grab")
	_course_wall(Vector3(x0 + 30.0, 0.0, -31.0), 3.6, 3.0, 0.0, gate, "LaneELedge36", "3.6 m: upgrades only")
	_course_wall(Vector3(x0 + 40.0, 0.0, -31.0), 1.6, 0.35, 0.0, gate, "LaneEWall160", "1.6 m: cybernetic vault")
	# F: invalid and awkward
	_course_wall(Vector3(x0, 0.0, -37.0), 1.0, 0.35, 0.0, wall, "LaneFBarred", "test bar: catch + climb")
	_box(Vector3(x0 + 1.2, 1.75, -37.0), Vector3(0.3, 0.15, 3.0), Vector3.ZERO, bad, "LaneFBar")
	_box(Vector3(x0 + 6.0, 1.0, -37.0), Vector3(6.0, 2.0, 3.0), Vector3.ZERO, block, "LaneFDeck")
	_course_wall(Vector3(x0 + 8.825, 2.0, -37.0), 1.0, 0.35, 0.0, wall, "LaneFDropWall", "2 m drop")
	_course_wall(Vector3(x0 + 18.0, 0.0, -37.0), 1.0, 0.4, 0.0, wall, "LaneFPost", "narrow post")
	_course_wall(Vector3(x0 + 26.0, 0.0, -37.0), 1.0, 0.35, 30.0, wall, "LaneF30", "30 deg")
	_course_wall(Vector3(x0 + 34.0, 0.0, -37.0), 1.3, 2.0, 0.0, block, "LaneFCovered", "overhang")
	_box(Vector3(x0 + 34.0, 2.0, -37.0), Vector3(3.0, 0.2, 3.0), Vector3.ZERO, bad, "LaneFOverhang")
	# G: mixed elevation
	_box(Vector3(x0 + 6.0, 0.6, -43.0), Vector3(12.0, 1.2, 3.0), Vector3.ZERO, block, "LaneGPlatformA")
	_course_wall(Vector3(x0 + 7.0, 1.2, -43.0), 1.0, 0.35, 0.0, wall, "LaneGTopWall", "wall on platform")
	_box(Vector3(x0 + 23.0, 0.6, -43.0), Vector3(12.0, 1.2, 3.0), Vector3.ZERO, block, "LaneGPlatformB")
	_course_wall(Vector3(x0 + 31.0, 0.0, -43.0), 1.0, 0.35, 0.0, wall, "LaneGDropWall", "1.0 m after drop")
	_label(Vector3(x0 + 14.5, 1.8, -43.0), "5 m gap")
	for lane in [["d", -25.0], ["e", -31.0], ["f", -37.0], ["g", -43.0]]:
		landmarks["lane_" + String(lane[0])] = Vector3(x0 - 7.0, 0.0, lane[1])
	landmarks["lane_d_pair"] = Vector3(x0 + 25.0, 0.0, -25.0)
	landmarks["lane_e_ledge"] = Vector3(x0 + 15.0, 0.0, -31.0)
	landmarks["lane_e_gate"] = Vector3(x0 + 24.0, 0.0, -31.0)
	landmarks["lane_g_top"] = Vector3(x0 + 1.0, 1.2, -43.0)
	landmarks["lane_f_drop"] = Vector3(x0 + 3.3, 2.0, -37.0)
	landmarks["lane_f_bar"] = Vector3(x0 - 4.0, 0.0, -37.0)
	_irregular_lane(x0)


## Movement Lab 5.1 lane H (z -49, landmark lane_h): irregular tops and the vault-variation sequence.
##   seven 0.4 m crates 1.18-1.32 m across the lane (uneven top: mantle), a block whose top slopes up 10 degrees,
##   a 1.3 m ledge turned 30 degrees (diagonal mantle), then vault walls turned +25 and -25 degrees, a 1.1 m and a
##   0.7 m wall (one vault each: hand side, body turn, lift and lean follow the angle, height, speed and stride)
func _irregular_lane(x0: float) -> void:
	var block := _tint(Color(0.36, 0.55, 0.80))
	var crate := _tint(Color(0.62, 0.50, 0.34))
	var wall := _tint(Color(0.80, 0.42, 0.36))
	var z := -49.0
	var crates := [1.18, 1.26, 1.20, 1.32, 1.26, 1.20, 1.24]
	for i in crates.size():
		var h: float = crates[i]
		_box(Vector3(x0 + 0.8, h / 2.0, z + (i - 3) * 0.4), Vector3(1.6, h, 0.4), Vector3.ZERO, crate, "LaneHCrate%d" % i)
	_label(Vector3(x0 + 0.8, 1.8, z), "uneven crates")
	_box(Vector3(x0 + 10.0, 0.5, z), Vector3(2.0, 1.2, 3.0), Vector3(0.0, 0.0, 10.0), block, "LaneHSlope")
	_label(Vector3(x0 + 10.0, 1.8, z), "sloped top")
	_course_wall(Vector3(x0 + 18.0, 0.0, z), 1.3, 2.0, 30.0, block, "LaneHDiagonal", "1.3 m at 30 deg")
	_course_wall(Vector3(x0 + 27.0, 0.0, z), 1.0, 0.35, 25.0, wall, "LaneHWallP25", "+25 deg")
	_course_wall(Vector3(x0 + 33.0, 0.0, z), 1.0, 0.35, -25.0, wall, "LaneHWallM25", "-25 deg")
	_course_wall(Vector3(x0 + 39.0, 0.0, z), 1.1, 0.35, 0.0, wall, "LaneHWall110", "1.1 m")
	_course_wall(Vector3(x0 + 45.0, 0.0, z), 0.7, 0.35, 0.0, wall, "LaneHWall70", "0.7 m")
	landmarks["lane_h"] = Vector3(x0 - 7.0, 0.0, z)
	landmarks["lane_h_walls"] = Vector3(x0 + 21.5, 0.0, z)
	_lanes_52(x0)


## Movement Lab 5.2 lanes (landmarks lane_i .. lane_l, facing +X):
##   I (z -55) fences  - 1.1 m fences 0.08 m thick turned 30, 45, 60 and 75 degrees: vault (up to 35 degrees),
##                       otherwise climb over square to the fence keeping the sideways momentum, from the ground or a catch
##   J (z -61) high    - 2.2 and 2.6 m walls (2 m deep): jump, catch on contact and hang, one press pulls up and over;
##                       a 2.4 m wall 0.3 m thick (pull up and over the far side); a 2.6 m wall with a slab just above its
##                       top (no room: the hang holds, the press is refused); a 3.0 m wall (a human's jump and reach,
##                       5.4) and a 3.6 m wall (cybernetic reach)
##   K (z -67) slide   - 30 m of flat run-out with two bars leaving 1.0 m of clearance (slide under, too low to crouch
##                       under), then a 12 degree ramp up, a plateau and a 12 degree ramp down
##   L (z -73) combo   - vault a 1.0 m wall, mantle a 1.2 m block, drop off, catch and pull up a 2.4 m wall, run off it,
##                       slide under a 1.0 m bar
##   M (z -79) flip    - (5.3) open ground for standing and slide flips, a 1.0 m deck to flip off (a longer fall),
##                       a 0.5 m box to flip onto (a shorter one), a bar with 1.0 m clearance (no room: refused)
##   N (z -85) hang    - (5.4) a 3.0 m wall 8 m long to catch and shimmy along (it ends: the shimmy stops), then a
##                       0.6 m gap and a 3.0 m wall 4 m long, and a 2.6 m wall 6 m long (hangs closer to the ground)
func _lanes_52(x0: float) -> void:
	var fence := _tint(Color(0.55, 0.45, 0.30))
	var block := _tint(Color(0.36, 0.55, 0.80))
	var wall := _tint(Color(0.80, 0.42, 0.36))
	var gate := _tint(Color(0.75, 0.35, 0.80))
	var bar := _tint(Color(0.30, 0.30, 0.30))
	var deck := _tint(Color(0.62, 0.62, 0.58))
	# I: fences at sharp angles
	var zi := -55.0
	for i in 4:
		var angle: float = [30.0, 45.0, 60.0, 75.0][i]
		_course_wall(Vector3(x0 + i * 9.0, 0.0, zi), 1.1, 0.08, angle, fence, "LaneIFence%d" % int(angle), "fence %d deg" % int(angle), 7.0)
	landmarks["lane_i"] = Vector3(x0 - 7.0, 0.0, zi)
	# J: high walls
	var zj := -61.0
	_course_wall(Vector3(x0 + 1.0, 0.0, zj), 2.2, 2.0, 0.0, block, "LaneJWall22", "2.2 m: jump, catch, Space")
	_course_wall(Vector3(x0 + 11.0, 0.0, zj), 2.6, 2.0, 0.0, block, "LaneJWall26", "2.6 m")
	_course_wall(Vector3(x0 + 20.0, 0.0, zj), 2.4, 0.3, 0.0, wall, "LaneJThin24", "2.4 m thin: over")
	_course_wall(Vector3(x0 + 29.0, 0.0, zj), 2.6, 2.0, 0.0, block, "LaneJCovered", "2.6 m, no room")
	_box(Vector3(x0 + 29.0, 3.15, zj), Vector3(2.0, 0.3, 3.0), Vector3.ZERO, bar, "LaneJSlab")
	_course_wall(Vector3(x0 + 39.0, 0.0, zj), 3.0, 2.0, 0.0, block, "LaneJWall30", "3.0 m: human reach")
	_course_wall(Vector3(x0 + 48.0, 0.0, zj), 3.6, 2.0, 0.0, gate, "LaneJWall36", "3.6 m: cybernetic")
	landmarks["lane_j"] = Vector3(x0 - 7.0, 0.0, zj)
	landmarks["lane_j_26"] = Vector3(x0 + 5.5, 2.2, zj)
	landmarks["lane_j_thin"] = Vector3(x0 + 15.0, 0.0, zj)
	landmarks["lane_j_covered"] = Vector3(x0 + 24.5, 0.0, zj)
	# K: slide
	var zk := -67.0
	for i in 2:
		var bx := x0 + 10.0 + i * 8.0
		_box(Vector3(bx, 1.0 + 0.15, zk), Vector3(0.3, 0.3, 3.0), Vector3.ZERO, bar, "LaneKBar%d" % i)
		_box(Vector3(bx, 0.5, zk - 1.6), Vector3(0.3, 1.0, 0.2), Vector3.ZERO, bar, "LaneKPostL%d" % i)
		_box(Vector3(bx, 0.5, zk + 1.6), Vector3(0.3, 1.0, 0.2), Vector3.ZERO, bar, "LaneKPostR%d" % i)
	_label(Vector3(x0 + 10.0, 1.8, zk), "1.0 m clearance: slide")
	var slope := deg_to_rad(12.0)
	var run := 10.0
	var up_x := x0 + 30.0
	var rise := run * tan(slope)
	var length := run / cos(slope)
	_box(Vector3(up_x + run * 0.5 + 0.2 * sin(slope), rise * 0.5 - 0.2 * cos(slope), zk), Vector3(length, 0.4, 3.0), Vector3(0.0, 0.0, 12.0), deck, "LaneKRampUp")
	_box(Vector3(up_x + run + 3.0, rise * 0.5, zk), Vector3(6.0, rise, 3.0), Vector3.ZERO, deck, "LaneKPlateau")
	var down_x := up_x + run + 6.0
	_box(Vector3(down_x + run * 0.5 - 0.2 * sin(slope), rise * 0.5 - 0.2 * cos(slope), zk), Vector3(length, 0.4, 3.0), Vector3(0.0, 0.0, -12.0), deck, "LaneKRampDown")
	_label(Vector3(up_x + 2.0, 1.2, zk), "12 deg up / down")
	landmarks["lane_k"] = Vector3(x0 - 7.0, 0.0, zk)
	landmarks["lane_k_plateau"] = Vector3(up_x + run + 0.5, rise, zk)
	# L: combo
	var zl := -73.0
	_course_wall(Vector3(x0, 0.0, zl), 1.0, 0.35, 0.0, wall, "LaneLWall", "vault")
	_course_wall(Vector3(x0 + 8.0, 0.0, zl), 1.2, 2.5, 0.0, block, "LaneLBlock", "mantle")
	_course_wall(Vector3(x0 + 18.0, 0.0, zl), 2.4, 2.0, 0.0, block, "LaneLHigh", "catch + pull up")
	_box(Vector3(x0 + 26.0, 1.15, zl), Vector3(0.3, 0.3, 3.0), Vector3.ZERO, bar, "LaneLBar")
	_label(Vector3(x0 + 26.0, 1.8, zl), "slide")
	landmarks["lane_l"] = Vector3(x0 - 7.0, 0.0, zl)
	# M: crouch flip
	var zm := -79.0
	_label(Vector3(x0 + 2.0, 1.4, zm), "Ctrl + Space: flip")
	_box(Vector3(x0 + 16.0, 0.5, zm), Vector3(6.0, 1.0, 3.0), Vector3.ZERO, deck, "LaneMDeck")
	_label(Vector3(x0 + 18.5, 1.9, zm), "flip off: 1.0 m")
	_box(Vector3(x0 + 26.0, 0.25, zm), Vector3(3.0, 0.5, 3.0), Vector3.ZERO, block, "LaneMBox")
	_label(Vector3(x0 + 26.0, 1.3, zm), "flip onto: 0.5 m")
	_box(Vector3(x0 + 34.0, 1.15, zm), Vector3(0.3, 0.3, 3.0), Vector3.ZERO, bar, "LaneMBar")
	_label(Vector3(x0 + 34.0, 1.8, zm), "no room to flip")
	landmarks["lane_m"] = Vector3(x0 - 7.0, 0.0, zm)
	landmarks["lane_m_deck"] = Vector3(x0 + 14.0, 1.0, zm)
	# N: hang and shimmy (walls 2 m deep along +X, long along Z)
	var zn := -85.0
	_course_wall(Vector3(x0 + 4.0, 0.0, zn), 3.0, 2.0, 0.0, block, "LaneNLong", "3.0 m: catch, stick left / right", 8.0)
	_course_wall(Vector3(x0 + 4.0, 0.0, zn - 6.6), 3.0, 2.0, 0.0, block, "LaneNShort", "gap 0.6 m", 4.0)
	_course_wall(Vector3(x0 + 16.0, 0.0, zn), 2.6, 2.0, 0.0, wall, "LaneNLow", "2.6 m", 6.0)
	landmarks["lane_n"] = Vector3(x0 - 4.0, 0.0, zn)


func _label(position: Vector3, caption: String) -> void:
	var label := Label3D.new()
	label.text = caption
	label.pixel_size = 0.006
	label.font_size = 56
	label.position = position
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)


## A course wall standing on the ground at `base` (its centre), `depth` along +X, turned `yaw_deg` about Y.
func _course_wall(base: Vector3, height: float, depth: float, yaw_deg: float, mat: Material, node_name: String, caption: String, width := 3.0) -> void:
	_box(base + Vector3(0.0, height / 2.0, 0.0), Vector3(depth, height, width), Vector3(0.0, yaw_deg, 0.0), mat, node_name)
	var label := Label3D.new()
	label.text = caption
	label.pixel_size = 0.006
	label.font_size = 56
	label.position = base + Vector3(0.0, height + 0.45, 0.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)


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
