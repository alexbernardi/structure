## Mantle and climb-over: get onto, or over, a top that is not vaulted - from the ground, or from the air after a
## catch. One action; the authored ClimbUp_1m is motion-warped onto the measured ledge. Nothing here is obstacle
## specific: every candidate is read from physics queries (face, top, headroom, standing room, back edge, landing).
##
##   mantle  - the whole collider footprint fits on the top: climb onto it and stand
##   over    - the top is too narrow to stand on (a thin wall, a bar): climb up, pass over it and drop on the far side,
##             if there is a landing within reach of a hang-drop
##
## Physical path (collider bottom, kinematic with full collision response every tick, like the vault):
##   rise   - up to the top plus a crest while closing on the face, never nearer than the collider radius plus skin
##   over   - forward across the top at the crest; a mantle then settles on the top, a climb-over releases into a fall
## Visual root: the authored linear root path, offset so the planted hand and foot meet the actual face and top by
## the contact time (motion warping); after contact the forward travel is compressed to end where the collider ends.
## Deterministic and independent of presentation. Never starts itself: traversal_controller.gd authorizes every start.
extends RefCounted

const Clip = preload("res://traversal/mantle_clip.gd")

const RADIUS := 0.35            ## character collider radius (character_body.gd)
const SKIN := 0.03              ## m kept between the collider and the face / top while climbing
const CREST := 0.04             ## m the collider bottom clears the top edge by
const GROUND_FACE_RAYS := [0.45, 1.25]  ## m above the feet: face probes from the ground
const AIR_FACE_STEP := 0.25     ## m between face probes from the air (from AIR_FACE_LOW up to the grip reach)
const AIR_FACE_LOW := 0.1
const MAX_TILT := 0.25          ## |normal.y| of a climbable face
const MIN_FACING := 0.64        ## cos 50 degrees: steepest approach that still climbs
const TOP_INSET := 0.08
const TOP_FLAT := 0.75          ## normal.y of a top that can be climbed onto (about 41 degrees: irregular rubble, slopes)
const LATERAL := 0.25           ## m either side the top must also be there (no climbing onto a pole)
const AGREE := 0.2              ## m the top may vary across the hands (irregular tops); the climb clears the highest
const GROUND_MIN := 0.55        ## m: lower tops are stepped / jumped onto
const AIR_MIN := 0.2            ## m below the top the feet must still be for a catch to be worth a climb
const MAX_OVER_DEPTH := 0.9     ## m: the deepest top climbed over rather than onto
const HANG_DROP := 1.5          ## m a climb-over may drop beyond landing_tolerance (the body hangs before it lets go)
const RISE_SHARE := 0.55        ## share of the physical climb spent rising (the rest goes over the top)
const PATH_SAMPLES := 16
const DROP_SAMPLES := 4
const ABORT_HORIZONTAL := 0.15
const ABORT_VERTICAL := 0.25
const OFFSET_EASE := 14.0
const MIN_RATE := 0.6
const MAX_RATE := 2.0

enum Phase {IDLE, ACTIVE}

var capabilities                ## MovementCapabilities (effective attributes)
var exclude: Array[RID] = []
var mask := 1
var phase := Phase.IDLE
var plan := {}
var time := 0.0                 ## clip time
var presenting := false
var reason := ""                ## latest evaluation: "ok", a rejection, or "" (nothing ahead)
var mantles := 0
var overs := 0                  ## climbs over a top too narrow to stand on
var aborts := 0
var last_seen := {}             ## latest evaluated ledge geometry, for the debug overlay
var _time_prev := 0.0
var _offset := Vector3.ZERO
var _offset_prev := Vector3.ZERO
var _ray := PhysicsRayQueryParameters3D.new()
var _shape := PhysicsShapeQueryParameters3D.new()
var _cylinder := CylinderShape3D.new()


func _init() -> void:
	_shape.shape = _cylinder


func active() -> bool:
	return phase == Phase.ACTIVE


func _cast(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> Dictionary:
	_ray.from = from
	_ray.to = to
	_ray.collision_mask = mask
	_ray.exclude = exclude
	return space.intersect_ray(_ray)


func _attr(id: String, fallback: float) -> float:
	return capabilities.get_value(id) if capabilities != null else fallback


## Horizontal reach from the collider surface to a face this move can use.
func reach(airborne: bool) -> float:
	return _attr("catch_distance", 0.45) if airborne else _attr("mantle_reach", 0.8)


## The climb available along horizontal `direction` from where the body is now: a plan ({ok: true, kind: "mantle" |
## "over", ...}), {ok: false, reason}, or {} when no face is in reach. Pure query: changes nothing.
func evaluate(body, direction: Vector3, airborne: bool) -> Dictionary:
	var space: PhysicsDirectSpaceState3D = body.get_world_3d().direct_space_state
	var feet: Vector3 = body.global_position
	var max_top := _attr("grip_reach", 2.1) if airborne else _attr("mantle_max_height", 1.45)
	var min_top := AIR_MIN if airborne else GROUND_MIN
	var limit := RADIUS + reach(airborne)
	var heights: Array = GROUND_FACE_RAYS
	if airborne:
		heights = []
		var h := AIR_FACE_LOW
		while h < max_top:
			heights.append(h)
			h += AIR_FACE_STEP
	var hit := {}
	for height in heights:
		var from: Vector3 = feet + Vector3.UP * height
		var found := _cast(space, from, from + direction * (limit + 0.05))
		if not found.is_empty():
			var along := (found.position as Vector3 - from).dot(direction)
			if hit.is_empty() or along < hit.distance - 0.01:
				found["distance"] = along
				hit = found
	if hit.is_empty():
		return {}
	var result := {"ok": false, "reason": "", "airborne": airborne, "face": hit.position, "reach": limit}
	last_seen = result
	if airborne and -float(body.velocity.y) > _attr("grip_strength", 7.0):
		result.reason = "too_fast"     # falling faster than the grip can stop
		return result
	var normal: Vector3 = hit.normal
	if absf(normal.y) > MAX_TILT:
		result.reason = "not_a_wall"
		return result
	var flat := Vector3(normal.x, 0.0, normal.z).normalized()
	if -flat.dot(direction) < MIN_FACING:
		result.reason = "too_angled"
		return result
	var distance: float = hit.distance
	var right := direction.cross(Vector3.UP)
	var tops: Array[float] = []
	var top_point := Vector3.ZERO
	var slope := flat.dot(right) / flat.dot(direction)   # face offset along travel per metre sideways (angled faces)
	for side in [0.0, -LATERAL, LATERAL]:
		var column: Vector3 = feet - right * side + direction * (distance + side * slope + TOP_INSET)
		var top := _cast(space, column + Vector3.UP * (max_top + 0.35), Vector3(column.x, (hit.position as Vector3).y - 0.01, column.z))
		if top.is_empty():
			result.reason = "too_high" if side == 0.0 else "narrow"
			return result
		if (top.normal as Vector3).y < TOP_FLAT:
			result.reason = "uneven_top"
			return result
		tops.append((top.position as Vector3).y - feet.y)
		if side == 0.0:
			top_point = top.position
	var height: float = tops[0]
	var highest: float = tops.max()
	result["height"] = height
	result["top"] = top_point
	if highest > max_top:
		result.reason = "too_high"
		return result
	if height < min_top:
		result.reason = "too_low"
		return result
	if absf(tops[1] - height) > AGREE or absf(tops[2] - height) > AGREE:
		result.reason = "irregular_top"
		return result
	var crouch: float = body.params.get_value("crouch_height")
	if not _cast(space, top_point + Vector3.UP * 0.02, top_point + Vector3.UP * crouch).is_empty():
		result.reason = "no_headroom"
		return result
	var built := _stand(space, body, feet, direction, distance, height, highest, top_point, crouch, airborne)
	if built.is_empty():
		built = _over(space, feet, direction, distance, height, highest, top_point, crouch, airborne)
	if not built.get("ok", true):
		result.reason = built.reason
		return result
	if not _path_clear(space, built, crouch):
		result.reason = "blocked"
		return result
	built.merge(result, false)
	built.ok = true
	built.reason = "ok"
	built["powered"] = capabilities != null and highest > capabilities.base_value("grip_reach" if airborne else "mantle_max_height") + 1e-4
	last_seen = built
	return built


## A standing spot on the top for the whole footprint, at the authored inset or as much less as still fits.
func _stand(space: PhysicsDirectSpaceState3D, _body, feet: Vector3, direction: Vector3, distance: float, height: float,
		highest: float, top_point: Vector3, crouch: float, airborne: bool) -> Dictionary:
	for candidate in [Clip.exit_inset(), 0.85, 0.65, RADIUS + 0.12]:
		var point: Vector3 = feet + direction * (distance + candidate)
		var level := INF
		var supported := true
		for along in [0.0, RADIUS - 0.05]:   # the centre, and the far edge of the footprint
			var probe: Vector3 = point + direction * along
			var ground := _cast(space, Vector3(probe.x, top_point.y + 0.5, probe.z), Vector3(probe.x, top_point.y - AGREE, probe.z))
			if ground.is_empty() or (ground.normal as Vector3).y < TOP_FLAT:
				supported = false
				break
			if along == 0.0:
				level = (ground.position as Vector3).y
				# A flat-bottomed cylinder on a sloped top rests on its uphill edge.
				level += (RADIUS - SKIN) * tan(acos(clampf((ground.normal as Vector3).y, 0.0, 1.0)))
		if supported and _fits(space, Vector3(point.x, level, point.z), crouch):
			var built := _build(feet, direction, distance, height, highest, candidate, airborne, "mantle")
			built["settle"] = level - feet.y
			built["crest"] = maxf(built.crest, built.settle + CREST)   # a top rising away from the edge (a slope)
			return built
	return {}


## Over a narrow top: its back edge, then a landing beyond within a hang-drop, with room for the drop.
func _over(space: PhysicsDirectSpaceState3D, feet: Vector3, direction: Vector3, distance: float, height: float,
		highest: float, top_point: Vector3, crouch: float, airborne: bool) -> Dictionary:
	var behind: Vector3 = feet + direction * (distance + MAX_OVER_DEPTH + 0.3) + Vector3.UP * (height - 0.06)
	var back := _cast(space, behind, behind - direction * (MAX_OVER_DEPTH + 0.35))
	if back.is_empty() or (back.normal as Vector3).dot(direction) < 0.7:
		return {"ok": false, "reason": "no_room"}
	var depth: float = (back.position as Vector3 - feet).dot(direction) - distance
	var past := depth + RADIUS + SKIN
	var drop_from: Vector3 = feet + direction * (distance + past)
	var probe: Vector3 = drop_from + direction * 0.2
	var deepest := HANG_DROP + _attr("landing_tolerance", 0.6)
	var ground := _cast(space, Vector3(probe.x, top_point.y + 0.2, probe.z), Vector3(probe.x, top_point.y - deepest, probe.z))
	if ground.is_empty() or (ground.normal as Vector3).y < 0.7:
		return {"ok": false, "reason": "bad_landing"}
	var built := _build(feet, direction, distance, height, highest, past, airborne, "over")
	built["depth"] = depth
	built["landing"] = (ground.position as Vector3).y - feet.y
	# The fall from the release point must be clear down to the landing.
	var crest: float = highest + CREST
	for i in DROP_SAMPLES + 1:
		var y: float = lerpf(crest, built.landing + 0.02, float(i) / DROP_SAMPLES)
		if not _fits(space, Vector3(drop_from.x, feet.y + y, drop_from.z) + direction * 0.05, crouch):
			return {"ok": false, "reason": "blocked"}
	return built


func _fits(space: PhysicsDirectSpaceState3D, bottom: Vector3, height: float) -> bool:
	_cylinder.radius = RADIUS - SKIN
	_cylinder.height = height - SKIN
	_shape.collision_mask = mask
	_shape.exclude = exclude
	_shape.transform = Transform3D(Basis.IDENTITY, bottom + Vector3.UP * (SKIN + _cylinder.height * 0.5))
	return space.intersect_shape(_shape, 1).is_empty()


func _build(feet: Vector3, direction: Vector3, distance: float, height: float, highest: float, inset: float, airborne: bool, kind: String) -> Dictionary:
	var start := 0.0
	if airborne and height < Clip.RISE:
		start = minf(Clip.LENGTH * (1.0 - height / Clip.RISE), 0.4)   # join the clip where the climb left matches
	var strength := _attr("mantle_strength", 1.0)
	var rate := clampf(strength / sqrt(clampf(height / Clip.RISE, 0.6, 2.5)), MIN_RATE, MAX_RATE)
	var contact := maxf(Clip.CONTACT, start + 0.1)
	var plan_dict := {"origin": feet, "direction": direction, "distance": distance, "height": height, "crest": highest + CREST,
		"inset": inset, "kind": kind, "settle": height, "start": start, "rate": rate, "contact": contact,
		"wait": maxf(distance - RADIUS - SKIN, 0.0),
		"delta": Vector2(distance - (Clip.FACE - Clip.forward(start)), height - (Clip.RISE - Clip.rise(start))),
		"airborne": airborne, "duration": (Clip.RELEASE - start) / rate}
	var at_contact: float = Clip.forward(contact) - Clip.forward(start) + plan_dict.delta.x
	var remaining := Clip.forward(Clip.LENGTH) - Clip.forward(contact)
	plan_dict["compress"] = (distance + inset - at_contact) / remaining if remaining > 0.001 else 1.0
	return plan_dict


## Collider bottom relative to the start, as (along travel, up), at clip time `t`.
static func collider_point(p: Dictionary, t: float) -> Vector2:
	var u := clampf((t - p.start) / (Clip.RELEASE - p.start), 0.0, 1.0)
	var crest: float = p.crest
	if u < RISE_SHARE:
		return Vector2(p.wait * smoothstep(0.0, RISE_SHARE, u), crest * smoothstep(0.0, RISE_SHARE * 0.85, u))
	var over := smoothstep(RISE_SHARE, 1.0, u)
	var y := crest if p.kind == "over" else lerpf(crest, p.settle + 0.005, smoothstep(0.75, 1.0, u))
	return Vector2(lerpf(p.wait, p.distance + p.inset, over), y)


## Visual (animation) root relative to the start at clip time `t`: the authored path, warped onto the ledge.
static func visual_point(p: Dictionary, t: float) -> Vector2:
	var weight := smoothstep(p.start, p.contact, t)
	var y: float = Clip.rise(t) - Clip.rise(p.start) + p.delta.y * weight
	var z: float = Clip.forward(t) - Clip.forward(p.start) + p.delta.x * weight
	if t > p.contact:
		var at_contact: float = Clip.forward(p.contact) - Clip.forward(p.start) + p.delta.x
		z = at_contact + (Clip.forward(t) - Clip.forward(p.contact)) * p.compress
	return Vector2(z, y)


func _world(p: Dictionary, point: Vector2) -> Vector3:
	return p.origin + p.direction * point.x + Vector3.UP * point.y


func _path_clear(space: PhysicsDirectSpaceState3D, p: Dictionary, crouch: float) -> bool:
	for i in PATH_SAMPLES + 1:
		var t: float = lerpf(p.start, Clip.RELEASE, float(i) / PATH_SAMPLES)
		if not _fits(space, _world(p, collider_point(p, t)), crouch):
			return false
	return true


## Starts an authorized climb (traversal_controller._authorize made `grant` for this plan); false otherwise.
func start(body, p: Dictionary, grant := {}) -> bool:
	if grant.get("move", "") != "mantle" or grant.get("plan", null) != p:
		push_warning("Mantle start refused: not authorized by the traversal controller")
		return false
	plan = p
	time = p.start
	_time_prev = time
	phase = Phase.ACTIVE
	presenting = true
	if p.kind == "over":
		overs += 1
	else:
		mantles += 1
	reason = "ok"
	_set_offset(body.global_position)
	_offset_prev = _offset
	return true


## Start of a tick: runs the active climb (true = the tick is consumed) and keeps the presentation clock.
func drive(body, dt: float) -> bool:
	_time_prev = time
	_offset_prev = _offset
	if phase != Phase.ACTIVE:
		if presenting:
			time = minf(time + plan.rate * dt, Clip.LENGTH)
			presenting = time < Clip.LENGTH
		_offset *= exp(-OFFSET_EASE * dt)
		return false
	time += plan.rate * dt
	var target := _world(plan, collider_point(plan, minf(time, Clip.RELEASE)))
	body.drive_to(target, dt)
	var error: Vector3 = target - body.global_position
	_set_offset(body.global_position)
	if Vector2(error.x, error.z).length() > ABORT_HORIZONTAL or absf(error.y) > ABORT_VERTICAL:
		aborts += 1
		reason = "blocked"
		phase = Phase.IDLE
		presenting = false
		body.release(Vector3.ZERO, false)
		return true
	if time >= Clip.RELEASE:
		phase = Phase.IDLE
		var wish: Vector3 = body.action.wish_direction() if body.action != null and body.action.has_method("wish_direction") else Vector3.ZERO
		var exit := 0.0
		if wish.length_squared() > 0.01 and wish.normalized().dot(plan.direction) > 0.5:
			exit = _attr("mantle_exit_speed", 2.5)
		if plan.kind == "over":
			presenting = false          # the fall and landing take over the presentation
			body.release(plan.direction * exit, false)
		else:
			body.release(plan.direction * exit, true)
	return true


func _set_offset(body_position: Vector3) -> void:
	_offset = _world(plan, visual_point(plan, time)) - body_position


func offset(fraction: float) -> Vector3:
	return _offset_prev.lerp(_offset, fraction)


func cancel() -> void:
	phase = Phase.IDLE
	presenting = false
	_offset = Vector3.ZERO
	_offset_prev = Vector3.ZERO


func presentation(fraction: float) -> Dictionary:
	if not presenting:
		return {}
	return {"mantle": true, "time": lerpf(_time_prev, time, fraction), "rate": plan.rate,
		"heading": atan2(-plan.direction.x, -plan.direction.z)}
