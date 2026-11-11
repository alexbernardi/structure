## Environment perception for the vault: physics ray and shape queries only. Measures the obstacle ahead of the feet
## along a travel direction in the planner's frame (see vault_planner.gd) and validates the collider's planned path.
## Decides only geometric validity; feasibility of the authored motion is the planner's job.
extends RefCounted

const Clip = preload("res://systems/movement_core/traversal/vault_clip.gd")
const Planner = preload("res://systems/movement_core/traversal/vault_planner.gd")

const FACE_HEIGHT := 0.45          ## m above the feet: below the lowest vaultable top, above step-height clutter
const MAX_FACE_TILT := 0.25        ## |normal.y| of a vaultable face
const TOP_INSET := 0.06            ## m past the face (along travel) where the top is measured
const TOP_FLAT := 0.9              ## normal.y of a vaultable top
const SCAN_ABOVE := 1.85           ## m above the feet the top scan starts; a taller obstacle has no top in reach
const LATERAL := 0.3               ## m either side of the centre line where the face and top must agree
const AGREE := 0.04                ## m
const BACK_PARALLEL := 0.98        ## dot of the back face normal with the reversed front normal
const WALKABLE := 0.7              ## normal.y of landing ground (about 45 degrees)
const PATH_SAMPLES := 14           ## collider placements checked along the planned hump
const SKIN := 0.03                 ## m the path check keeps the collider off the surfaces it is planned to touch

var mask := 1
var exclude: Array[RID] = []
var _ray := PhysicsRayQueryParameters3D.new()
var _shape := PhysicsShapeQueryParameters3D.new()
var _cylinder := CylinderShape3D.new()


func _init() -> void:
	_shape.shape = _cylinder


func _cast(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> Dictionary:
	_ray.from = from
	_ray.to = to
	_ray.collision_mask = mask
	_ray.exclude = exclude
	return space.intersect_ray(_ray)


## Distance from `feet` along horizontal `direction` to the first face within `reach`, with its point, normal and
## collider; empty when nothing is there.
func face(space: PhysicsDirectSpaceState3D, feet: Vector3, direction: Vector3, reach: float) -> Dictionary:
	var from := feet + Vector3.UP * FACE_HEIGHT
	var hit := _cast(space, from, from + direction * reach)
	if hit.is_empty():
		return {}
	return {"distance": from.distance_to(hit.position), "point": hit.position, "normal": hit.normal, "collider": hit.collider_id}


## Full measurement of the obstacle whose face `hit` (from face()) lies ahead. `landing_travel` is how far past the
## takeoff point the landing foot comes down, and `takeoff` the takeoff distance (both from the planner's timing).
## Returns {ok, reason} plus, when the geometry was readable: distance, height, depth, slope, angle, landing,
## top (world), back (world), landing_point (world), normal.
func measure(space: PhysicsDirectSpaceState3D, feet: Vector3, direction: Vector3, hit: Dictionary, takeoff: float, landing_travel: float, max_depth := Planner.MAX_DEPTH, drop := 1.0) -> Dictionary:
	var normal: Vector3 = hit.normal
	if absf(normal.y) > MAX_FACE_TILT:
		return {"ok": false, "reason": "not_a_wall"}
	var flat := Vector3(normal.x, 0.0, normal.z).normalized()
	var right := direction.cross(Vector3.UP)
	var facing := -flat.dot(direction)
	if facing <= 0.05:
		return {"ok": false, "reason": "too_angled"}
	var distance: float = hit.distance
	var slope := flat.dot(right) / flat.dot(direction)
	var result := {"ok": false, "reason": "", "distance": distance, "slope": slope, "normal": flat,
		"angle": signf(flat.cross(-direction).y) * acos(clampf(facing, -1.0, 1.0))}
	# Top: on the centre line and either side; it must be flat and level across the path.
	var heights: Array[float] = []
	for side in [0.0, -LATERAL, LATERAL]:
		var base: Vector3 = feet - right * side    # clip x = -side along `right`
		var near: float = distance + side * slope
		if side != 0.0:
			var lateral := _cast(space, base + Vector3.UP * FACE_HEIGHT, base + Vector3.UP * FACE_HEIGHT + direction * (near + AGREE * 2.0))
			if lateral.is_empty():
				result.reason = "narrow"
				return result
			var expected := near
			var got := (lateral.position as Vector3 - (base + Vector3.UP * FACE_HEIGHT)).dot(direction)
			if absf(got - expected) > AGREE:
				result.reason = "irregular_face"
				return result
		var column := base + direction * (near + TOP_INSET)
		var top := _cast(space, column + Vector3.UP * SCAN_ABOVE, column + Vector3.UP * FACE_HEIGHT)
		if top.is_empty():
			result.reason = "too_high"
			return result
		if (top.normal as Vector3).y < TOP_FLAT:
			result.reason = "uneven_top"
			return result
		heights.append((top.position as Vector3).y - feet.y)
		if side == 0.0:
			result["top"] = top.position
	var height: float = heights[0]
	if absf(heights[1] - height) > AGREE or absf(heights[2] - height) > AGREE:
		result.reason = "uneven_top"
		return result
	result["height"] = height
	if height < Planner.MIN_HEIGHT:
		result.reason = "too_low"
		return result
	# Depth along travel on the centre line: a ray back toward the face from beyond the deepest vaultable obstacle.
	var span := max_depth + 0.6
	var behind := feet + direction * (distance + span) + Vector3.UP * (height - 0.08)
	var back := _cast(space, behind, behind - direction * (span + 0.05))
	if back.is_empty():
		result.reason = "too_deep"
		return result
	if (back.normal as Vector3).dot(-flat) < BACK_PARALLEL:
		result.reason = "irregular_back"
		return result
	result["back"] = back.position
	result["depth"] = (back.position as Vector3 - (feet + Vector3.UP * (height - 0.08))).dot(direction) - distance
	# Landing ground where the leading foot comes down, relative to the takeoff ground.
	var landing_point := feet + direction * (distance - takeoff + landing_travel)
	var ground := _cast(space, landing_point + Vector3.UP * (height + 0.5), landing_point + Vector3.DOWN * maxf(drop, 1.0))
	if ground.is_empty() or (ground.normal as Vector3).y < WALKABLE:
		result.reason = "bad_landing"
		return result
	result["landing_point"] = ground.position
	result["landing"] = (ground.position as Vector3).y - feet.y
	result.ok = true
	result.reason = "ok"
	return result


## True when the collider (a cylinder of `radius` and `height`) can follow `plan` from `origin` along `direction`
## without touching anything: the hump is checked at evenly spaced clip times, lifted by SKIN so the takeoff and
## landing ground it rests on do not count.
func path_clear(space: PhysicsDirectSpaceState3D, plan: Dictionary, origin: Vector3, direction: Vector3, radius: float, height: float) -> bool:
	_cylinder.radius = radius - SKIN
	_cylinder.height = height - SKIN
	_shape.collision_mask = mask
	_shape.exclude = exclude
	for i in PATH_SAMPLES + 1:
		var time := Clip.LANDING * float(i) / float(PATH_SAMPLES)
		var bottom := origin + direction * Planner.travel(plan, time) + Vector3.UP * (Planner.collider_height(plan, time) + SKIN)
		_shape.transform = Transform3D(Basis.IDENTITY, bottom + Vector3.UP * (_cylinder.height * 0.5))
		if not space.intersect_shape(_shape, 1).is_empty():
			return false
	return true
