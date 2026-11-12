## The vault as a physical action of the character body (Movement Lab 4.0, made intentional in 5.0). While running it
## watches the way ahead and keeps an `opportunity`: a planned, collision-checked vault that a press of Space would
## commit to now. It never commits on its own (traversal_controller.gd decides, on the player's press). The
## interaction region along the approach runs from `vault_window` seconds before the takeoff point to
## `vault_late_window` metres inside it:
##   early (before the takeoff point) - commit arms: jump presses are swallowed and the approach eases to the vault's
##                                      ground speed, reaching it exactly at the planned takeoff distance;
##   late  (inside it)                - commit takes off at once with a shorter, faster stride (Planner.timing_at).
## Then the collider is driven kinematically along the planned hump with full collision response every tick, and
## control returns to the movement core on landing. Deterministic and independent of presentation: the animation reads the clip time,
## body offset and hand contact from here, never the other way round.
extends RefCounted

const Clip = preload("res://systems/movement_core/traversal/vault_clip.gd")
const Planner = preload("res://systems/movement_core/traversal/vault_planner.gd")
const Probe = preload("res://systems/movement_core/traversal/obstacle_probe.gd")

enum Phase {IDLE, ARMED, ACTIVE}

const MIN_ALIGNMENT := 0.7       ## wished direction . travel direction needed to arm and to stay armed
const ABORT_HORIZONTAL := 0.15   ## m of tracking error (something blocked the collider) that ends the vault
const ABORT_VERTICAL := 0.25
const RECOVER_TIME := 0.12       ## s over which the landing speed returns to the planned exit speed
const OFFSET_EASE := 14.0        ## 1/s decay of a presentation offset left over after an abort
const BODY_RADIUS := 0.35        ## the character collider (character_body.gd RADIUS)
const SIDE_SLOPE := 0.14         ## tan 8 degrees: a more angled face fixes the support hand to its near side
const TURN_SHARE := 0.6          ## share of the angle between travel and the face normal the body turns while on the hand
const PREVIEW_TIME := 2.5        ## s of look-ahead reported to the presentation for phase steering: enough running for a
                                 ## bounded cadence change to bring the gait to any phase by the takeoff

var params
var profile
var planner := Planner.new()
var probe := Probe.new()
var phase := Phase.IDLE
var plan := {}
var obstacle := {}
var reason := ""               ## latest classification of the way ahead: "ok", a rejection, or "" (nothing there)
var origin := Vector3.ZERO     ## takeoff point (collider bottom centre on the takeoff ground)
var direction := Vector3.FORWARD
var time := 0.0                ## clip time of the current or last vault
var presenting := false        ## the clip is still showing (until its end, past the physical landing)
var entry_speed := 0.0         ## horizontal speed when the vault armed
var takeoff := 0.0             ## armed: takeoff distance at the vault speed
var travel_speed := 0.0        ## armed: vault ground speed the approach eases to
var face_distance := INF       ## armed: distance from the feet to the face
var approach_speed := 0.0      ## horizontal speed at the latest observation
var vaults := 0
var aborts := 0
var plan_usec := 0             ## cost of the latest plan
var capabilities               ## MovementCapabilities: the character's vault limits and timing windows (null = 4.0 constants)
var opportunity := {}          ## the vault a press would commit to now ({} = none); see evaluate()
var region := {}               ## interaction region along the current approach (debug overlay): near, far, takeoff, feet, direction
var late_vaults := 0
var opportunity_side := 0      ## armed: the support side the armed plan chose (presentation steers toward its entry foot)
var sides := {-1: 0, 0: 0, 1: 0}   ## vaults per planned support side (telemetry, tests)
var _wish := Vector3.ZERO
var _recover_left := 0.0
var _rejected_key := ""
var _rejected_reason := ""
var _time_prev := 0.0
var _offset := Vector3.ZERO
var _offset_prev := Vector3.ZERO
var _follow := Vector3.ZERO      ## like _offset but along the ground under the vault (see follow_offset)
var _follow_prev := Vector3.ZERO
var _preview := {}             ## idle: approach to a vaultable-looking obstacle beyond the anticipation window (presentation hint only)
var _ease_span := 0.0          ## armed: m from the arming point to the takeoff, over which the approach speed eases


func setup(traversal_params, vault_profile, exclude: Array[RID] = []) -> void:
	params = traversal_params
	profile = vault_profile
	probe.exclude = exclude


func enabled() -> bool:
	return params != null and params.is_on("traversal") and profile != null and profile.valid


func active() -> bool:
	return phase == Phase.ACTIVE


func armed() -> bool:
	return phase == Phase.ARMED


func _attribute(id: String, fallback: float) -> float:
	return capabilities.get_value(id) if capabilities != null else fallback


func limits() -> Dictionary:
	return Planner.limits_from(capabilities)


## Before the movement core: remembers the wished direction and swallows jump presses while the vault is committed.
func filter_input(input: Dictionary, _body = null, _dt := 0.0) -> Dictionary:
	var move: Vector2 = input.get("move", Vector2.ZERO)
	_wish = Basis(Vector3.UP, float(input.get("yaw", 0.0))) * Vector3(move.x, 0.0, -move.y)
	if phase != Phase.IDLE and (input.get("jump_pressed", false) or input.get("jump_held", false)):
		input = input.duplicate()
		input.jump_pressed = false
		input.jump_held = false
	return input


## Start of every tick. Runs the active vault (returns true: it consumed the tick) and keeps the presentation timeline.
func drive(body, dt: float) -> bool:
	_time_prev = time
	_offset_prev = _offset
	_follow_prev = _follow
	if phase != Phase.ACTIVE:
		if presenting:
			time = minf(time + plan.rate * dt, Clip.LENGTH)
			presenting = time < Clip.LENGTH
		_offset *= exp(-OFFSET_EASE * dt)
		_follow *= exp(-OFFSET_EASE * dt)
		return false
	time += plan.rate * dt
	var target := _collider_point(minf(time, Clip.LANDING))
	if time > Clip.LANDING:
		target += direction * plan.travel_speed * (time - Clip.LANDING) / plan.rate
	body.drive_to(target, dt)
	var error: Vector3 = target - body.global_position
	if Vector2(error.x, error.z).length() > ABORT_HORIZONTAL or absf(error.y) > ABORT_VERTICAL:
		aborts += 1
		reason = "blocked"
		_set_offsets(body.global_position)
		phase = Phase.IDLE
		presenting = false
		body.release(body.velocity, false)
		return true
	_set_offsets(body.global_position)
	if time >= Clip.LANDING:
		phase = Phase.IDLE
		_recover_left = _attribute("recovery_time", RECOVER_TIME)
		body.release(direction * plan.travel_speed, true)
	return true


## After the movement core, before the move: eases an armed approach to the vault speed (reached exactly at takeoff),
## and after landing returns the speed to the planned exit speed without fighting faster core motion. The approach
## speed follows a line in the remaining distance (from the arming speed to the vault speed); the core's own
## acceleration toward a faster speed is held back to it each tick rather than fought gradually.
func adjust(body, dt: float) -> void:
	var core = body.core
	var flat := Vector3(core.velocity.x, 0.0, core.velocity.z)
	var speed := flat.length()
	if phase == Phase.ARMED and speed > 0.01:
		var remaining := maxf(face_distance - takeoff - speed * dt, 0.0)
		var along := clampf(remaining / maxf(_ease_span, 0.001), 0.0, 1.0)
		var goal := lerpf(travel_speed, entry_speed, along)
		if (entry_speed >= travel_speed and speed > goal) or (entry_speed < travel_speed and speed < goal):
			core.velocity = flat * (goal / speed) + Vector3.UP * core.velocity.y
	elif _recover_left > 0.0:
		_recover_left = maxf(0.0, _recover_left - dt)
		if not core.grounded or _wish.length_squared() < 0.01 or _wish.normalized().dot(direction) < MIN_ALIGNMENT:
			_recover_left = 0.0
			return
		var along := flat.dot(direction)
		var goal := lerpf(plan.exit_speed, plan.travel_speed, _recover_left / maxf(_attribute("recovery_time", RECOVER_TIME), 0.001))
		if along < goal:
			core.velocity += direction * (goal - along)


## After the move: perceives the way ahead, arms, and triggers at the takeoff distance.
func observe(body, dt: float) -> void:
	_preview = {}
	if phase == Phase.ACTIVE:
		return
	if not enabled():
		_disarm("off" if profile == null or profile.valid else "no_clip")
		return
	var flat := Vector3(body.velocity.x, 0.0, body.velocity.z)
	var speed := flat.length()
	approach_speed = speed
	if not body.core.grounded or body.core.crouching or speed < 0.15 or (armed() and speed < Planner.MIN_ENTRY_SPEED):
		_disarm("")
		return
	var d := flat / speed
	if _wish.length_squared() < 0.01 or _wish.normalized().dot(d) < MIN_ALIGNMENT:
		_disarm("")
		return
	if phase == Phase.ARMED:
		var space_armed: PhysicsDirectSpaceState3D = body.get_world_3d().direct_space_state
		var feet_armed: Vector3 = body.global_position
		var armed_hit := probe.face(space_armed, feet_armed, d, maxf(face_distance, takeoff) + speed * dt + 0.05)
		if armed_hit.is_empty() or armed_hit.collider != obstacle.get("collider", 0):
			_disarm("changed")
			return
		face_distance = armed_hit.distance
		if armed_hit.distance <= takeoff:
			_trigger(body, space_armed, feet_armed, d, armed_hit)
		return
	evaluate(body, d, speed)


## The vault a press would commit to now, for travel direction `d` at horizontal `speed` (sets `opportunity`,
## `region` and `reason`). Also keeps the read-only approach preview for the presentation's phase steering.
func evaluate(body, d: Vector3, speed: float) -> void:
	opportunity = {}
	region = {}
	var timed := Planner.timing(speed)
	var preview_speed: float = maxf(speed, body.core.wish_speed)
	var preview_timing := Planner.timing(preview_speed)
	var window: float = _attribute("vault_window", params.get_value("anticipation"))
	var latest: float = maxf(Planner.latest_takeoff(speed), timed.takeoff - _attribute("vault_late_window", 0.0))
	var space: PhysicsDirectSpaceState3D = body.get_world_3d().direct_space_state
	var feet: Vector3 = body.global_position
	var far: float = timed.takeoff + speed * window
	var reach: float = maxf(far, preview_timing.takeoff + preview_speed * PREVIEW_TIME)
	var hit := probe.face(space, feet, d, reach + 0.05)
	if hit.is_empty():
		reason = ""
		return
	var lim := limits()
	if speed >= Planner.MIN_ENTRY_SPEED:
		region = {"near": latest, "far": far, "takeoff": timed.takeoff, "feet": feet, "direction": d, "face": hit.distance}
	if hit.distance < latest:
		reason = "too_close"
		return
	if speed < Planner.MIN_ENTRY_SPEED or hit.distance > far:
		reason = ""
		var seen := probe.measure(space, feet, d, hit, preview_timing.takeoff, Clip.travel(Clip.LANDING, preview_timing.stretch), lim.get("max_depth", Planner.MAX_DEPTH), lim.get("landing_drop", 0.6))
		if seen.ok and Planner.screen(seen, lim) == "":
			_preview = {"distance": hit.distance - preview_timing.takeoff, "speed": speed,
				"target_speed": preview_speed, "acceleration": body.core.p.get("ground_accel", body.params.get_value("ground_accel")),
				"travel_speed": preview_timing.travel_speed, "ease": window * preview_speed}
			reason = "ahead"
		return
	var late: bool = hit.distance < timed.takeoff
	var fitted: Dictionary = Planner.timing_at(speed, hit.distance) if late else timed
	if fitted.is_empty():
		reason = "too_close"
		return
	var measured := probe.measure(space, feet, d, hit, fitted.takeoff, Clip.travel(Clip.LANDING, fitted.stretch), lim.get("max_depth", Planner.MAX_DEPTH), lim.get("landing_drop", 0.6))
	measured["travel"] = d
	if not measured.ok:
		reason = measured.reason
		return
	var key := "%d|%.2f|%.2f|%.0f|%.2f|%.1f|%s|%s|%.2f" % [hit.collider, measured.height, measured.depth, rad_to_deg(measured.angle), measured.landing, speed, late, lim, fitted.stretch]
	if key == _rejected_key:
		reason = _rejected_reason
		return
	var trial := measured.duplicate()
	trial.distance = fitted.takeoff
	var result := _plan(trial, speed, {} if not late else fitted)
	var start: Vector3 = feet + d * (hit.distance - fitted.takeoff)
	if result.ok and not probe.path_clear(space, result, start, d, BODY_RADIUS, body.params.get_value("crouch_height")):
		result = Planner.reject("blocked")
	measured["collider"] = hit.collider
	measured["face"] = hit.point
	if not result.ok:
		_rejected_key = key
		_rejected_reason = result.reason
		reason = result.reason
		return
	var powered := false
	if capabilities != null:
		powered = measured.height > capabilities.base_value("vault_max_height") + 1e-4 or result.warp > capabilities.base_value("vault_lift") + 1e-4 \
			or measured.depth > capabilities.base_value("vault_max_depth") + 1e-4 or measured.landing < -capabilities.base_value("landing_tolerance") - 1e-4
	opportunity = {"late": late, "hit": hit, "measured": measured, "timing": fitted, "plan": result, "speed": speed,
		"feet": feet, "direction": d, "height": measured.height, "powered": powered}
	reason = "ok"


## True when an obstacle ahead along `d`, within `within` metres, has vaultable geometry for this character (its
## size, angle and landing pass the planner's screen), whatever the timing. The controller uses it to tell a missed
## vault window (press too close: an ordinary jump) from an obstacle that is not a vault at all (mantle / climb).
func vaultable_ahead(body, d: Vector3, within: float) -> bool:
	if not enabled() or d == Vector3.ZERO:
		return false
	var space: PhysicsDirectSpaceState3D = body.get_world_3d().direct_space_state
	var feet: Vector3 = body.global_position
	var hit := probe.face(space, feet, d, within)
	if hit.is_empty():
		return false
	var timed := Planner.timing(Planner.MIN_TRAVEL)
	var lim := limits()
	var seen := probe.measure(space, feet, d, hit, minf(timed.takeoff, hit.distance), Clip.travel(Clip.LANDING, timed.stretch),
		lim.get("max_depth", Planner.MAX_DEPTH), lim.get("landing_drop", 0.6))
	return seen.ok and Planner.screen(seen, lim) == ""


## Commits to the current opportunity (the player pressed Space). Early: arms the eased approach. Late: takes off now.
## `grant` must come from traversal_controller._authorize for this exact opportunity: no other path can start a vault.
## False when there is nothing to commit to or the commit is not authorized.
func commit(body, grant := {}) -> bool:
	if opportunity.is_empty() or phase != Phase.IDLE or not enabled():
		return false
	if grant.get("move", "") != "vault" or grant.get("plan", null) != opportunity:
		push_warning("Vault commit refused: not authorized by the traversal controller")
		return false
	var o := opportunity
	opportunity = {}
	obstacle = o.measured
	entry_speed = o.speed
	if o.late:
		plan = o.plan
		origin = o.feet
		direction = o.direction
		time = 0.0
		_time_prev = 0.0
		presenting = true
		phase = Phase.ACTIVE
		vaults += 1
		sides[int(plan.get("side", 0))] += 1
		late_vaults += 1
		_set_offsets(o.feet)
		_offset_prev = _offset
		_follow_prev = _follow
		return true
	phase = Phase.ARMED
	opportunity_side = int(o.plan.get("side", 0))
	takeoff = o.timing.takeoff
	travel_speed = o.timing.travel_speed
	face_distance = o.hit.distance
	_ease_span = o.hit.distance - o.timing.takeoff
	reason = "ok"
	return true


func _trigger(body, space: PhysicsDirectSpaceState3D, feet: Vector3, d: Vector3, hit: Dictionary) -> void:
	var stretch: float = Planner.timing(entry_speed).stretch
	var lim := limits()
	var measured := probe.measure(space, feet, d, hit, takeoff, Clip.travel(Clip.LANDING, stretch), lim.get("max_depth", Planner.MAX_DEPTH), lim.get("landing_drop", 0.6))
	measured["travel"] = d
	if not measured.ok:
		_disarm(measured.reason)
		return
	var overshoot: float = takeoff - hit.distance
	measured.distance = takeoff
	var result := _plan(measured, entry_speed)
	var start := feet - d * overshoot
	if result.ok and not probe.path_clear(space, result, start, d, BODY_RADIUS, body.params.get_value("crouch_height")):
		result = Planner.reject("blocked")
	if not result.ok:
		_disarm(result.reason)
		return
	measured["collider"] = hit.collider
	measured["face"] = hit.point
	obstacle = measured
	plan = result
	origin = start
	direction = d
	time = overshoot / (Clip.ROOT_SPEED * plan.stretch)
	_time_prev = time
	presenting = true
	phase = Phase.ACTIVE
	vaults += 1
	sides[int(plan.get("side", 0))] += 1
	_set_offsets(feet)
	_offset_prev = _offset
	_follow_prev = _follow


## Plans the vault with a support side. An angled face (|slope| > SIDE_SLOPE) fixes the hand to the side where the face
## comes first (+1 right hand, the authored clip; -1 left hand, its mirror); a square face leaves it to the stride
## (0, chosen by the presentation at takeoff; the collider path is the same either way). A left-hand plan is the
## authored plan for the mirrored obstacle: the planner and its clearance maths are unchanged. If the preferred hand
## cannot reach, the other is tried.
func _plan(measured: Dictionary, speed: float, timed := {}) -> Dictionary:
	var started := Time.get_ticks_usec()
	var slope: float = measured.get("slope", 0.0)
	var mirrored_ok: bool = profile != null and profile.has_mirror
	var preferred := 0 if absf(slope) < SIDE_SLOPE or not mirrored_ok else (1 if slope > 0.0 else -1)
	var result := _plan_side(measured, speed, timed, preferred)
	if not result.ok and preferred != 0 and result.reason in ["out_of_reach", "no_hand_contact"]:
		var other := _plan_side(measured, speed, timed, -preferred)
		if other.ok:
			result = other
	plan_usec = Time.get_ticks_usec() - started
	return result


func _plan_side(measured: Dictionary, speed: float, timed: Dictionary, side: int) -> Dictionary:
	var obstacle := measured
	if side < 0:
		obstacle = measured.duplicate()
		obstacle.slope = -float(measured.slope)
		obstacle.angle = -float(measured.angle)
	var result := planner.plan(profile, obstacle, speed, _attribute("momentum_conservation", params.get_value("momentum_continuity")), limits(), timed)
	result["side"] = side
	if measured.has("normal") and measured.has("travel"):
		result["turn"] = clampf((measured.travel as Vector3).signed_angle_to(-(measured.normal as Vector3), Vector3.UP), -0.6, 0.6) * TURN_SHARE
	return result


func _disarm(why: String) -> void:
	if phase == Phase.ARMED:
		phase = Phase.IDLE
	opportunity = {}
	region = {}
	reason = why


## Teleport / respawn: drops any vault without a handback (the body is placed elsewhere and its motion cleared).
func cancel() -> void:
	phase = Phase.IDLE
	opportunity = {}
	region = {}
	presenting = false
	reason = ""
	_recover_left = 0.0
	_offset = Vector3.ZERO
	_offset_prev = Vector3.ZERO
	_follow = Vector3.ZERO
	_follow_prev = Vector3.ZERO


## World point of a plan-frame point (x = the character's left, y up from the takeoff ground, z along travel).
func to_world(point: Vector3) -> Vector3:
	return origin + direction * point.z - direction.cross(Vector3.UP) * point.x + Vector3.UP * point.y


func _collider_point(t: float) -> Vector3:
	return origin + direction * Planner.travel(plan, t) + Vector3.UP * Planner.collider_height(plan, t)


func _visual_point(t: float) -> Vector3:
	return origin + direction * Planner.travel(plan, t) + Vector3.UP * Planner.visual_height(plan, t)


## The visual root without the pose fitting (the warp and dip that bring the authored hand onto this obstacle): the
## travel plus the change of ground from takeoff to landing.
func _follow_point(t: float) -> Vector3:
	return origin + direction * Planner.travel(plan, t) + Vector3.UP * plan.landing * Clip.landing_weight(t)


func _set_offsets(body_position: Vector3) -> void:
	_offset = _visual_point(time) - body_position
	_follow = _follow_point(time) - body_position


## Visual root minus the body, interpolated like the body between physics ticks.
func offset(fraction: float) -> Vector3:
	return _offset_prev.lerp(_offset, fraction)


## What cameras follow, relative to the body: the visual root's path over the obstacle without the pose fitting, so
## the view neither rides the collider's hump nor ducks with the dip while the hand is planted.
func follow_offset(fraction: float) -> Vector3:
	return _follow_prev.lerp(_follow, fraction)


## Everything the animation needs this frame (`fraction`: physics interpolation fraction).
func presentation(fraction: float) -> Dictionary:
	var t := lerpf(_time_prev, time, fraction)
	var result := {"vault": presenting, "armed": phase == Phase.ARMED, "time": t}
	if presenting:
		result["rate"] = plan.rate
		result["heading"] = atan2(-direction.x, -direction.z)
		result["hand_weight"] = Planner.hand_weight(plan, t)
		# The plan's hand point is the authored right hand in the planned frame; its mirror is the left hand.
		var point: Vector3 = plan.hand_point
		result["hand"] = to_world(point)
		result["hand_left"] = to_world(Vector3(-point.x, point.y, point.z))
		result["lean"] = plan.lean * Planner.support_weight(plan, t)
		result["side"] = plan.get("side", 0)
		result["turn"] = plan.get("turn", 0.0)
		result["speed"] = entry_speed
		result["support"] = Planner.support_weight(plan, t)
		result["entry_phase"] = profile.entry_phase
		result["mirror_entry_phase"] = profile.mirror_entry_phase
	elif phase == Phase.ARMED and entry_speed > 0.0:
		var remaining := maxf(face_distance - takeoff, 0.0)
		result["approach"] = {"distance": remaining, "speed": approach_speed, "travel_speed": travel_speed, "ease": remaining}
		result["entry_phase"] = profile.entry_phase
		result["mirror_entry_phase"] = profile.mirror_entry_phase
		result["side"] = opportunity_side
	elif not _preview.is_empty():
		result["approach"] = _preview
		result["entry_phase"] = profile.entry_phase
		result["mirror_entry_phase"] = profile.mirror_entry_phase
		result["side"] = 0
	return result
