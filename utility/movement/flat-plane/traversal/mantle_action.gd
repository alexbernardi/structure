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
const Pullup = preload("res://traversal/pullup_clip.gd")

const RADIUS := 0.35            ## character collider radius (character_body.gd)
const SKIN := 0.03              ## m kept between the collider and the face / top while climbing
const CREST := 0.04             ## m the collider bottom clears the top edge by
const GROUND_FACE_RAYS := [0.45, 1.25]  ## m above the feet: face probes from the ground
const AIR_FACE_STEP := 0.25     ## m between face probes from the air (from AIR_FACE_LOW up to the grip reach)
const AIR_FACE_LOW := 0.1
const MAX_TILT := 0.25          ## |normal.y| of a climbable face
const MIN_TOWARD := 0.2         ## wished direction . face direction (about 78 degrees): sharper approaches still climb
const FAN := [0.0, -0.45, 0.45, -0.9, 0.9, -1.3, 1.3]   ## rad: probe directions around the intent (sharp approaches, fences)
const REACH_RATIO := 1.306       ## hand reach above the soles per metre of standing height: the 1.8 m mannequin's wrist
                                 ## reaches 2.19 m with the arm straight up, + 0.08 m of fingers over the lip + 0.08 m of
                                 ## shoulder stretch = 2.35 m (tools/audit_hand_reach.gd; checked by test_traversal_hang)
const PULLUP_MIN := 1.5         ## m of top above the feet from which a catch is a two-handed pull-up (ClimbUp_2m)
const HANG_CONTACT := 0.2       ## m from the body's surface to the face for a ledge to be caught on contact
const HANG_SETTLE := 0.15       ## s to settle from the contact position into the hang
const DANGLE_SLACK := 0.12      ## m short of the full reach the soles hang at (arms straight but not locked)
const GROUND_CLEAR := 0.05      ## m kept between the hanging soles and the ground (else the body hangs higher, legs braced)
const HAND_SPAN := 0.24         ## m from the hang point to each hand along the ledge (the authored grip is shoulder-wide)
const SHIMMY_ACCEL := 5.0       ## m/s^2 the shimmy speeds up and slows down
const SHIMMY_LEAD := 0.08       ## m beyond the leading hand the ledge must continue
const CORNER_MIN := deg_to_rad(25.0)    ## a smaller change of wall direction is not a corner (the ledge just bends)
const CORNER_MAX := deg_to_rad(135.0)   ## a sharper one cannot be hung around
const CORNER_SAMPLES := 8               ## collider checks along the arc around a corner
const CORNER_MIN_TIME := 0.35           ## s for the shortest corner
const TOP_INSET := 0.04          ## m past the face the top is probed (a fence is 0.08 m thick)
const TOP_FLAT := 0.75          ## normal.y of a top that can be climbed onto (about 41 degrees: irregular rubble, slopes)
const LATERAL := 0.25           ## m either side the top must also be there (no climbing onto a pole)
const AGREE := 0.2              ## m the top may vary across the hands (irregular tops); the climb clears the highest
const GROUND_MIN := 0.55        ## m: lower tops are stepped / jumped onto
const AIR_MIN := 0.2            ## m below the top the feet must still be for a catch to be worth a climb
const MAX_OVER_DEPTH := 0.9     ## m: the deepest top climbed over rather than onto
const HANG_DROP := 1.9          ## m a climb-over may drop beyond landing_tolerance (the body hangs at arm's length first)
const RISE_SHARE := 0.55        ## share of the physical climb spent rising (the rest goes over the top)
const PATH_SAMPLES := 16
const DROP_SAMPLES := 4
const ABORT_HORIZONTAL := 0.15
const ABORT_VERTICAL := 0.25
const OFFSET_EASE := 14.0
const MIN_RATE := 0.6
const MAX_RATE := 2.0

enum Phase {IDLE, ACTIVE, HANG}

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
var hangs := 0
var _hang_from := Vector3.ZERO
var _hang_to := Vector3.ZERO
var _hang_time := 0.0
var shimmy_wish := 0.0          ## -1..1: the stick along the ledge (+ = the character's right), set each tick while hanging
var shimmy_velocity := 0.0      ## m/s along the ledge (+ = right)
var shimmy_block := ""          ## why the shimmy stopped: "end" (no ledge / wall beyond the leading hand), "blocked"
var shimmy_distance := 0.0      ## m shimmied in all (telemetry, tests)
var _top_y := 0.0
var _catch_velocity := Vector3.ZERO
var corners := 0                ## corners hung around (telemetry, tests)
var corner := {}                ## the corner the hands are working around: {at, d_old, d_new, side, kind, x}
var _turn := {}                 ## the arc in progress around `corner`
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


func hanging() -> bool:
	return phase == Phase.HANG


func _cast(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> Dictionary:
	_ray.from = from
	_ray.to = to
	_ray.collision_mask = mask
	_ray.exclude = exclude
	return space.intersect_ray(_ray)


func _attr(id: String, fallback: float) -> float:
	return capabilities.get_value(id) if capabilities != null else fallback


## Highest top above the soles the hands can catch: the body's own overhead reach (its height) plus any extra reach.
## Evaluated from where the body is, so the jump (impulse, gravity) decides how high a ledge can be caught.
func hand_reach(body) -> float:
	return float(body.params.get_value("stand_height")) * REACH_RATIO + _attr("grip_reach", 0.0)


## The same for the unaugmented body (base attributes): beyond it a catch is powered.
func base_hand_reach(body) -> float:
	var extra: float = capabilities.base_value("grip_reach") if capabilities != null else 0.0
	return float(body.params.get_value("stand_height")) * REACH_RATIO + extra


## Horizontal reach from the collider surface to a face this move can use.
func reach(airborne: bool) -> float:
	return _attr("catch_distance", 0.45) if airborne else _attr("mantle_reach", 0.8)


## The climb available along horizontal `direction` from where the body is now: a plan ({ok: true, kind: "mantle" |
## "over", ...}), {ok: false, reason}, or {} when no face is in reach. Pure query: changes nothing.
func evaluate(body, direction: Vector3, airborne: bool, from_hang := false) -> Dictionary:
	var space: PhysicsDirectSpaceState3D = body.get_world_3d().direct_space_state
	var feet: Vector3 = body.global_position
	var max_top := hand_reach(body) if airborne else _attr("mantle_max_height", 1.45)
	var min_top := AIR_MIN if airborne else GROUND_MIN
	var limit := RADIUS + reach(airborne)
	var heights: Array = GROUND_FACE_RAYS
	if airborne:
		heights = []
		var h := AIR_FACE_LOW
		while h < max_top:
			heights.append(h)
			h += AIR_FACE_STEP
	# A fan of probes around the intent finds faces approached at sharp angles (a fence run along diagonally); the climb
	# then goes square to the face it found, from the perpendicular distance.
	var intent := direction
	var faces := {}     # one candidate per face: the nearest point of it found by any probe
	for offset in FAN:
		var ray: Vector3 = intent.rotated(Vector3.UP, offset)
		var length := (limit + 0.05) / maxf(cos(offset), 0.3)
		for height in heights:
			var from: Vector3 = feet + Vector3.UP * height
			var found := _cast(space, from, from + ray * length)
			if found.is_empty():
				continue
			var n: Vector3 = found.normal
			var square := -Vector3(n.x, 0.0, n.z).normalized()
			if absf(n.y) > MAX_TILT or square.dot(intent) < MIN_TOWARD:
				continue
			var across := (found.position as Vector3 - from).dot(square)
			if across > limit + 0.05:
				continue
			var key := "%d|%.2f|%.2f" % [found.collider_id, square.x, square.z]
			if not faces.has(key) or across < faces[key].distance - 0.01:
				found["distance"] = across
				found["square"] = square
				faces[key] = found
	if faces.is_empty():
		return {}
	# Nearest face first; if it cannot be climbed (a fence's narrow end, say), the next faces are tried.
	var ordered: Array = faces.values()
	ordered.sort_custom(func(x, y) -> bool: return x.distance < y.distance)
	var first := {}
	for k in mini(ordered.size(), 3):
		var outcome := _evaluate_face(body, space, feet, ordered[k], intent, airborne, from_hang, max_top, min_top, limit)
		if outcome.get("ok", false):
			return outcome
		if first.is_empty():
			first = outcome
	last_seen = first
	return first


## The climb onto or over one face found by evaluate()'s probes, square to it.
func _evaluate_face(body, space: PhysicsDirectSpaceState3D, feet: Vector3, hit: Dictionary, intent: Vector3, airborne: bool,
		from_hang: bool, max_top: float, min_top: float, limit: float) -> Dictionary:
	var direction: Vector3 = hit.square
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
	var distance: float = hit.distance
	var right := direction.cross(Vector3.UP)
	var tops: Array[float] = []
	var top_point := Vector3.ZERO
	var slope := flat.dot(right) / flat.dot(direction)   # face offset along travel per metre sideways (angled faces)
	for side in [0.0, -LATERAL, LATERAL]:
		var column: Vector3 = feet - right * side + direction * (distance + side * slope + TOP_INSET)
		# Search down from below whatever is above the top (a slab or ceiling), not from inside it.
		var from_y: float = feet.y + max_top + 0.35
		var above := _cast(space, Vector3(column.x, (hit.position as Vector3).y + 0.02, column.z), Vector3(column.x, from_y, column.z))
		if not above.is_empty():
			from_y = (above.position as Vector3).y - 0.01
		var top := _cast(space, Vector3(column.x, from_y, column.z), Vector3(column.x, (hit.position as Vector3).y - 0.01, column.z))
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
	var built := _stand(space, body, feet, direction, distance, height, highest, top_point, crouch, airborne, from_hang)
	if built.is_empty():
		built = _over(space, feet, direction, distance, height, highest, top_point, crouch, airborne, from_hang)
	if not built.get("ok", true):
		result.reason = built.reason
		return result
	if not _path_clear(space, built, crouch):
		result.reason = "blocked"
		return result
	built.merge(result, false)
	built.ok = true
	built.reason = "ok"
	var unaided: float = base_hand_reach(body) if airborne else (capabilities.base_value("mantle_max_height") if capabilities != null else INF)
	# Reaching beyond the unaugmented body is powered; pulling up from a hang already held is not (the catch was the reach).
	built["powered"] = capabilities != null and not from_hang and highest > unaided + 1e-4
	# Sideways momentum along the wall survives the climb (a fence taken at a sharp angle).
	var flat_velocity := Vector3(body.velocity.x, 0.0, body.velocity.z)
	built["tangent"] = (flat_velocity - direction * flat_velocity.dot(direction)) * _attr("momentum_conservation", 0.6)
	built["intent"] = intent
	last_seen = built
	return built


## A standing spot on the top for the whole footprint, at the authored inset or as much less as still fits.
func _stand(space: PhysicsDirectSpaceState3D, _body, feet: Vector3, direction: Vector3, distance: float, height: float,
		highest: float, top_point: Vector3, crouch: float, airborne: bool, from_hang := false) -> Dictionary:
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
			var built := _build(feet, direction, distance, height, highest, candidate, airborne, "mantle", from_hang)
			built["settle"] = level - feet.y
			built["crest"] = maxf(built.crest, built.settle + CREST)   # a top rising away from the edge (a slope)
			return built
	return {}


## Over a narrow top: its back edge, then a landing beyond within a hang-drop, with room for the drop.
func _over(space: PhysicsDirectSpaceState3D, feet: Vector3, direction: Vector3, distance: float, height: float,
		highest: float, top_point: Vector3, crouch: float, airborne: bool, from_hang := false) -> Dictionary:
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
	var built := _build(feet, direction, distance, height, highest, past, airborne, "over", from_hang)
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


## Timing and warp of one climb. A catch of a top at least PULLUP_MIN above the feet is the two-handed pull-up
## (ClimbUp_2m from its grip: from the hang, or joined just before the hands arrive); lower tops use the quick running
## climb (ClimbUp_1m). Both share the physical path; only the authored clip and its warp differ.
func _build(feet: Vector3, direction: Vector3, distance: float, height: float, highest: float, inset: float, airborne: bool,
		kind: String, from_hang := false) -> Dictionary:
	var pullup := airborne and height >= PULLUP_MIN
	var clip = Pullup if pullup else Clip
	var strength := _attr("mantle_strength", 1.0)
	var start := 0.0
	var contact := Clip.CONTACT
	var rate := clampf(strength / sqrt(clampf(height / Clip.RISE, 0.6, 2.5)), MIN_RATE, MAX_RATE)
	if pullup:
		start = Pullup.GRIP if from_hang else Pullup.REACH - 0.03
		# From a hang at arm's length (deeper than the authored grip) the arms first pull the body up to the grip: the
		# warp onto the edge is spread over a longer start.
		contact = start + 0.1 + (0.6 * maxf(0.0, height - Pullup.hang_drop()) if from_hang else 0.0)
		rate = clampf(strength / sqrt(clampf(height / Pullup.EDGE, 0.75, 1.6)), MIN_RATE, MAX_RATE)
	elif airborne and height < Clip.RISE:
		start = minf(Clip.LENGTH * (1.0 - height / Clip.RISE), 0.4)   # join the clip where the climb left matches
		contact = maxf(Clip.CONTACT, start + 0.1)
	var release: float = clip.RELEASE
	var plan_dict := {"origin": feet, "direction": direction, "distance": distance, "height": height, "crest": highest + CREST,
		"inset": inset, "kind": kind, "settle": height, "start": start, "rate": rate, "contact": contact, "release": release,
		"clip": "pullup" if pullup else "climb", "length": clip.LENGTH, "wait": maxf(distance - RADIUS - SKIN, 0.0),
		"delta": Vector2(distance - (clip.FACE - clip.forward(start)), height - (clip.EDGE - clip.rise(start))),
		"airborne": airborne, "duration": (release - start) / rate}
	var at_contact: float = clip.forward(contact) - clip.forward(start) + plan_dict.delta.x
	var remaining: float = clip.forward(clip.LENGTH) - clip.forward(contact)
	plan_dict["compress"] = (distance + inset - at_contact) / remaining if remaining > 0.001 else 1.0
	return plan_dict


## Collider bottom relative to the start, as (along travel, up), at clip time `t`.
static func collider_point(p: Dictionary, t: float) -> Vector2:
	var u := clampf((t - p.start) / (p.release - p.start), 0.0, 1.0)
	var crest: float = p.crest
	if u < RISE_SHARE:
		return Vector2(p.wait * smoothstep(0.0, RISE_SHARE, u), crest * smoothstep(0.0, RISE_SHARE * 0.85, u))
	var over := smoothstep(RISE_SHARE, 1.0, u)
	var y := crest if p.kind == "over" else lerpf(crest, p.settle + 0.005, smoothstep(0.75, 1.0, u))
	return Vector2(lerpf(p.wait, p.distance + p.inset, over), y)


## Visual (animation) root relative to the start at clip time `t`: the authored path, warped onto the ledge.
static func visual_point(p: Dictionary, t: float) -> Vector2:
	var clip = Pullup if p.get("clip", "climb") == "pullup" else Clip
	var weight := smoothstep(p.start, p.contact, t)
	var y: float = clip.rise(t) - clip.rise(p.start) + p.delta.y * weight
	var z: float = clip.forward(t) - clip.forward(p.start) + p.delta.x * weight
	if t > p.contact:
		var at_contact: float = clip.forward(p.contact) - clip.forward(p.start) + p.delta.x
		z = at_contact + (clip.forward(t) - clip.forward(p.contact)) * p.compress
	return Vector2(z, y)


func _world(p: Dictionary, point: Vector2) -> Vector3:
	return p.origin + p.direction * point.x + Vector3.UP * point.y


func _path_clear(space: PhysicsDirectSpaceState3D, p: Dictionary, crouch: float) -> bool:
	for i in PATH_SAMPLES + 1:
		var t: float = lerpf(p.start, p.release, float(i) / PATH_SAMPLES)
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
	_offset_prev = _offset
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
	if phase == Phase.HANG:
		_hang_time += dt
		if _hang_time > HANG_SETTLE:
			_shimmy(body, dt)
		var hold: Vector3 = _hang_from.lerp(_hang_to, smoothstep(0.0, HANG_SETTLE, _hang_time))
		body.drive_to(hold, dt)
		# The drawn body eases from where the catch happened onto the authored grip as the collider settles.
		_offset = (_world(plan, visual_point(plan, time)) - body.global_position) * smoothstep(0.0, HANG_SETTLE, _hang_time)
		if body.global_position.distance_to(hold) > ABORT_HORIZONTAL + 0.1:
			drop(body)                     # something pushed the body off the wall
		return true
	if phase != Phase.ACTIVE:
		if presenting:
			time = minf(time + plan.rate * dt, plan.length)
			presenting = time < plan.length
		_offset *= exp(-OFFSET_EASE * dt)
		return false
	time += plan.rate * dt
	var target := _world(plan, collider_point(plan, minf(time, plan.release)))
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
	if time >= plan.release:
		phase = Phase.IDLE
		var wish: Vector3 = body.action.wish_direction() if body.action != null and body.action.has_method("wish_direction") else Vector3.ZERO
		var exit := Vector3.ZERO
		if wish.length_squared() > 0.01 and wish.normalized().dot(plan.direction) > 0.2:
			exit = plan.direction * _attr("mantle_exit_speed", 2.5) + plan.get("tangent", Vector3.ZERO)
		if plan.kind == "over":
			presenting = false          # the fall and landing take over the presentation
			body.release(exit, false)
		else:
			body.release(exit, true)
	return true


## Hand over hand along the ledge: moves the hang point sideways while the top and the face continue under the leading
## hand (and a little beyond) at the same height, and the body has room; otherwise stops there (shimmy_block says why).
func _shimmy(body, dt: float) -> void:
	if not _turn.is_empty():
		_advance_turn(dt)
		return
	shimmy_velocity = move_toward(shimmy_velocity, shimmy_wish * _attr("shimmy_speed", 0.9), SHIMMY_ACCEL * dt)
	if absf(shimmy_velocity) < 1e-4:
		return
	var right: Vector3 = plan.direction.cross(Vector3.UP)
	var step: Vector3 = right * shimmy_velocity * dt
	var space: PhysicsDirectSpaceState3D = body.get_world_3d().direct_space_state
	var lead: Vector3 = right * signf(shimmy_velocity) * (HAND_SPAN + SHIMMY_LEAD)
	var top := ledge_top(space, _hang_to + step + lead)
	var centre := ledge_top(space, _hang_to + step)
	var blocked: bool = body.test_move(Transform3D(Basis.IDENTITY, _hang_to), step)
	if is_nan(top) or is_nan(centre) or blocked:
		# The ledge does not go on straight: around a corner if the geometry allows it, otherwise stop here.
		var why := _try_corner(body, space, signf(shimmy_velocity))
		if why == "":
			return
		shimmy_velocity = 0.0
		shimmy_block = why if why != "no_corner" else ("blocked" if blocked else "end")
		return
	shimmy_block = ""
	_forget_corner_behind()
	var depth: float = _top_y - _hang_to.y
	_top_y = centre
	_hang_to += step
	_hang_to.y = _top_y - depth
	_hang_from += step
	plan["origin"] = _hang_to
	shimmy_distance += step.length()


## Around a corner while hanging: an inside corner (a wall across the path, facing back along it) or an outside corner
## (the face ends and its end face looks along the path). The new face must be a wall turned 25-135 degrees, its top
## must go on at the hang's height past the leading hand, and the collider must fit all along the arc the hang point
## takes around the corner. Returns "" when the turn has started, else why not ("no_corner", "corner_angle",
## "corner_ledge", "corner_blocked").
func _try_corner(body, space: PhysicsDirectSpaceState3D, s: float) -> String:
	var d: Vector3 = plan.direction
	var along: Vector3 = d.cross(Vector3.UP) * s
	var face: Vector3 = _hang_to + d * (RADIUS + SKIN)
	var f := Vector3(face.x, _top_y - 0.3, face.z)
	var found := {}
	var ahead := _cast(space, f - d * 0.05, f - d * 0.05 + along * (HAND_SPAN + SHIMMY_LEAD + RADIUS + 0.3))
	if not ahead.is_empty() and absf((ahead.normal as Vector3).y) < MAX_TILT and (ahead.normal as Vector3).dot(along) < -0.3:
		found = {"kind": "inside", "hit": ahead.position, "n": ahead.normal}
	else:
		var beyond: Vector3 = f + along * (HAND_SPAN + SHIMMY_LEAD + 0.25) + d * 0.06   # within even a thin wall's end face
		var back := _cast(space, beyond, beyond - along * (HAND_SPAN + SHIMMY_LEAD + 0.35))
		if not back.is_empty() and absf((back.normal as Vector3).y) < MAX_TILT and (back.normal as Vector3).dot(along) > 0.3:
			found = {"kind": "outside", "hit": back.position, "n": back.normal}
	if found.is_empty():
		return "no_corner"
	var n := Vector3((found.n as Vector3).x, 0.0, (found.n as Vector3).z).normalized()
	var d_new := -n
	var turn := d.signed_angle_to(d_new, Vector3.UP)
	if absf(turn) < CORNER_MIN or absf(turn) > CORNER_MAX:
		return "corner_angle"
	# The corner on the lip: where the old face's line meets the new face's plane.
	var t: float = ((found.hit as Vector3) - f).dot(n) / along.dot(n)
	var at := f + along * t
	at.y = _top_y
	var along_new: Vector3 = d_new.cross(Vector3.UP) * s
	var e0: float = maxf(t, 0.0)
	var e1: float = e0 if found.kind == "outside" else maxf(e0, RADIUS + SKIN + 0.02)
	var start := _hang_to
	var finish: Vector3 = at - d_new * (RADIUS + SKIN) + along_new * e1
	finish.y = _hang_to.y
	if is_nan(ledge_top(space, finish, d_new)) or is_nan(ledge_top(space, finish + along_new * (HAND_SPAN + SHIMMY_LEAD), d_new)):
		return "corner_ledge"
	var pivot := Vector3(at.x, _hang_to.y, at.z)
	var r0 := Vector2(start.x - pivot.x, start.z - pivot.z)
	var r1 := Vector2(finish.x - pivot.x, finish.z - pivot.z)
	var sweep := wrapf(r1.angle() - r0.angle(), -PI, PI)
	var crouch: float = body.params.get_value("crouch_height")
	for k in range(1, CORNER_SAMPLES + 1):
		var p := _arc(pivot, r0, r1, sweep, float(k) / CORNER_SAMPLES)
		if not _fits(space, p, crouch):
			return "corner_blocked"
	var length: float = absf(sweep) * (r0.length() + r1.length()) * 0.5
	_turn = {"pivot": pivot, "r0": r0, "r1": r1, "sweep": sweep, "d0": d, "d1": d_new, "u": 0.0,
		"time": maxf(CORNER_MIN_TIME, length / maxf(_attr("shimmy_speed", 0.9), 0.3)), "e0": e0, "e1": e1}
	corner = {"at": at, "d_old": d, "d_new": d_new, "side": s, "kind": found.kind, "x": -s * e0}
	shimmy_block = ""
	return ""


static func _arc(pivot: Vector3, r0: Vector2, r1: Vector2, sweep: float, u: float) -> Vector3:
	var radius := lerpf(r0.length(), r1.length(), u)
	var v := r0.normalized().rotated(sweep * u) * radius
	return Vector3(pivot.x + v.x, pivot.y, pivot.z + v.y)


## One tick around a corner: the hang point travels its arc while the body turns to the new wall (committed once started).
func _advance_turn(dt: float) -> void:
	_turn.u = minf(1.0, float(_turn.u) + dt / float(_turn.time))
	var u: float = _turn.u
	var previous := _hang_to
	_hang_to = _arc(_turn.pivot, _turn.r0, _turn.r1, _turn.sweep, u)
	_hang_from += _hang_to - previous
	shimmy_distance += previous.distance_to(_hang_to)
	var w := smoothstep(0.0, 1.0, u)
	var d0: Vector3 = _turn.d0
	plan["direction"] = d0.rotated(Vector3.UP, d0.signed_angle_to(_turn.d1, Vector3.UP) * w).normalized()
	plan["origin"] = _hang_to
	corner.x = lerpf(-float(corner.side) * float(_turn.e0), float(corner.side) * float(_turn.e1), w)
	shimmy_velocity = float(corner.side) * _attr("shimmy_speed", 0.9) * 0.5
	if u >= 1.0:
		plan["direction"] = _turn.d1
		_turn = {}
		corners += 1


## Once both hands are well past the corner (or back on the old wall), the hands no longer need the two-faced path.
func _forget_corner_behind() -> void:
	if corner.is_empty():
		return
	var face: Vector3 = _hang_to + plan.direction * (RADIUS + SKIN)
	var r: Vector3 = plan.direction.cross(Vector3.UP)
	var x: float = (face - (corner.at as Vector3)).dot(r)
	corner.x = x
	if absf(x) > HAND_SPAN + 0.2:
		corner = {}


## The top of the ledge in front of a hanging body at `hang_point` (its collider bottom), or NAN where the top or the
## wall-like face under it does not continue at the hang's height (the end of the wall, a gap, a step).
func ledge_top(space: PhysicsDirectSpaceState3D, hang_point: Vector3, toward := Vector3.ZERO) -> float:
	var d: Vector3 = plan.direction if toward == Vector3.ZERO else toward
	var face: Vector3 = hang_point + d * (RADIUS + SKIN)
	var column: Vector3 = face + d * TOP_INSET
	var top := _cast(space, Vector3(column.x, _top_y + 0.3, column.z), Vector3(column.x, _top_y - 0.3, column.z))
	if top.is_empty() or (top.normal as Vector3).y < TOP_FLAT or absf((top.position as Vector3).y - _top_y) > AGREE * 0.5:
		return NAN
	var from: Vector3 = Vector3(hang_point.x, _top_y - 0.3, hang_point.z)
	var wall := _cast(space, from, from + d * (RADIUS + SKIN + 0.15))
	if wall.is_empty() or absf((wall.normal as Vector3).y) > MAX_TILT:
		return NAN
	return (top.position as Vector3).y


## Catches the ledge on contact and hangs from it until a press climbs (evaluate from the hang + start) or the player
## lets go (drop). The body hangs at arm's length (its reach less DANGLE_SLACK below the top) where there is room below,
## else as low as the ground allows with the legs braced (never higher than the authored grip). `p` is an airborne plan
## whose top is high enough to hang.
func begin_hang(body, p: Dictionary, grant := {}) -> bool:
	if grant.get("move", "") != "hang" or grant.get("plan", null) != p:
		push_warning("Hang refused: not authorized by the traversal controller")
		return false
	var feet: Vector3 = body.global_position
	var top_y: float = feet.y + p.height
	_hang_from = feet
	_hang_to = feet + p.direction * p.wait
	var space: PhysicsDirectSpaceState3D = body.get_world_3d().direct_space_state
	var below := _cast(space, Vector3(_hang_to.x, top_y - 0.5, _hang_to.z), Vector3(_hang_to.x, top_y - 6.0, _hang_to.z))
	var room: float = top_y - (below.position as Vector3).y - GROUND_CLEAR if not below.is_empty() else INF
	var depth: float = clampf(room, Pullup.hang_drop(), maxf(Pullup.hang_drop(), hand_reach(body) - DANGLE_SLACK))
	_hang_to.y = top_y - depth
	_top_y = top_y
	_catch_velocity = body.velocity
	shimmy_velocity = 0.0
	shimmy_wish = 0.0
	shimmy_block = ""
	corner = {}
	_turn = {}
	plan = p.duplicate()
	plan["clip"] = "pullup"
	plan["start"] = Pullup.GRIP
	plan["length"] = Pullup.LENGTH
	plan["release"] = Pullup.RELEASE
	plan["origin"] = _hang_to
	plan["distance"] = RADIUS + SKIN          # the edge relative to the hanging body
	plan["height"] = depth
	plan["delta"] = Vector2(RADIUS + SKIN - (Pullup.FACE - Pullup.forward(Pullup.GRIP)), depth - Pullup.hang_drop())
	plan["contact"] = Pullup.GRIP + 0.1 + 0.6 * (depth - Pullup.hang_drop())
	_hang_time = 0.0
	time = Pullup.GRIP
	_time_prev = time
	phase = Phase.HANG
	presenting = true
	hangs += 1
	reason = "hang"
	_offset = Vector3.ZERO
	_offset_prev = _offset
	return true


## True when a hang at this plan's ledge is possible: the top is high enough that the hanging body (feet
## Pullup.hang_drop() below the top) is off the ground, and the body is touching the face.
func can_hang(body, p: Dictionary) -> bool:
	if not p.get("ok", false) or not p.get("airborne", false) or p.height < PULLUP_MIN:
		return false
	if p.distance - RADIUS > HANG_CONTACT:
		return false
	var feet: Vector3 = body.global_position
	var hang_feet: float = feet.y + p.height - Pullup.hang_drop()
	var space: PhysicsDirectSpaceState3D = body.get_world_3d().direct_space_state
	var below := _cast(space, feet + Vector3.UP * 0.1, feet + Vector3.DOWN * 3.0)
	return below.is_empty() or (below.position as Vector3).y < hang_feet - 0.02


## Lets go of the ledge: falls from the hang with a small push off the wall.
func drop(body) -> void:
	if phase != Phase.HANG:
		return
	phase = Phase.IDLE
	presenting = false
	reason = "let_go"
	body.release(-plan.direction * 0.6, false)


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
	var top_y: float = plan.origin.y + plan.height
	var edge: Vector3 = plan.origin + plan.direction * plan.distance
	return {"mantle": true, "time": lerpf(_time_prev, time, fraction), "rate": plan.rate, "clip": plan.get("clip", "climb"),
		"hang": phase == Phase.HANG, "length": plan.get("length", Clip.LENGTH),
		"right": plan.direction.cross(Vector3.UP), "lip_y": top_y, "shimmy": shimmy_velocity, "hang_time": _hang_time,
		"catch_velocity": _catch_velocity, "corner": corner.duplicate() if phase == Phase.HANG else {},
		"turning": float(_turn.get("u", -1.0)),
		"heading": atan2(-plan.direction.x, -plan.direction.z),
		"edge": Vector3(edge.x, top_y, edge.z), "direction": plan.direction}
