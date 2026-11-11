## Unified traversal (Movement Lab 5.0, refined in 5.1): the character body's one physical action. Every traversal
## move - jump, vault, mantle, climb-over, catch, air jump - answers the same intent (a NEW press of Space), chosen from
## the sensed geometry, the body's motion and the character's capabilities by one fixed set of rules:
##
##   grounded press  vault (only inside its interaction region)
##                   > missed window (a vaultable obstacle closer than the region): ordinary jump, never a climb
##                   > mantle onto / climb over a top that is not a vault (too deep, too high, a platform)
##                   > jump
##   airborne press  catch a ledge within reach (then mantle onto it, or climb over a narrow top) > air jump
##                   (capability) > wait up to CATCH_BUFFER for a ledge to come within reach / the landing buffer
##   presses while a move is committed are swallowed; in its second half they buffer and chain into the next move
##   airborne contact with a high edge (no press needed): catch it and hang; one press then pulls up and over (5.2);
##                   crouch, or pulling the stick away from the wall, lets go
##   crouched press  (crouch held on the ground, or sliding) a front flip (5.3): a physics jump that keeps the
##                   momentum; presses while upside down buffer for the landing
##
## Authorization is central: every move start goes through _authorize(), which requires a press no older than
## MAX_PRESS_AGE, the capability and the resources, and returns the grant that vault_action.commit() and
## mantle_action.start() demand. Contact, held Space, and the body's own state can never start a move. Buffered
## presses mirror the movement core's jump buffer exactly, so jump timing (and bunny hops) are unchanged.
## Deterministic on the fixed tick; the input frame is the only per-tick input (multiplayer replay).
extends RefCounted

const VaultAction = preload("res://systems/movement_core/traversal/vault_action.gd")
const MantleAction = preload("res://systems/movement_core/traversal/mantle_action.gd")
const FlipClip = preload("res://systems/movement_core/traversal/flip_clip.gd")
const Capabilities = preload("res://systems/movement_core/capability/movement_capabilities.gd")
const Resources = preload("res://systems/movement_core/capability/movement_resources.gd")

const CHAIN_FROM := 0.5          ## share of a committed move after which a press buffers for the next move
const CATCH_WISH := 0.5          ## wished direction . travel needed for a catch
const CATCH_BUFFER := 0.2        ## s an airborne press keeps looking for a ledge to come within reach
const MAX_PRESS_AGE := 0.3       ## s: no press older than this authorizes anything, buffered or chained

var params                       ## traversal_params (the traversal switch)
var vault := VaultAction.new()
var mantle := MantleAction.new()
var capabilities = Capabilities.new()
var resources = Resources.new()
var intent_left := 0.0           ## s left on a buffered press (0 = none), the movement core's jump-buffer arithmetic
var chained := false             ## the buffered press was made during a committed move
var press_age := INF             ## s since the latest new press of Space
var catch_left := 0.0            ## s left on an airborne press looking for a ledge
var last_choice := ""            ## what the latest press did: jump / vault / late_vault / mantle / over / catch / catch_over / air_jump / buffered / swallowed
var last_refusal := ""           ## why the preferred move was not taken on the latest press
var catch_preview := {}          ## airborne: the catch a press would make now (diagnostics only; computed with the overlay on)
var air_jumps_used := 0
var air_jump_time := INF         ## s since the latest air jump (presentation)
var choices := {}                ## choice -> count (telemetry, tests)
var _wish := Vector3.ZERO
var _air_jump_pending := false
var _crouch_prev := false
var sliding := false             ## a crouch slide is under way (Movement Lab 5.2)
var slide_time := 0.0            ## s since the slide started
var slide_exit := -1.0           ## s since the slide ended standing up (presentation; -1 = none)
var slides := 0
var slide_velocity := Vector3.ZERO   ## the slide's own horizontal velocity (carried between ticks)
var _slide_crouch := false
var _slide_pending := false      ## crouch pressed in the air: slide on touching down at speed
var _was_on_floor := false
var flipping := false            ## airborne in a crouch flip (Movement Lab 5.3)
var flip_phase := 0.0            ## clip time of JogToFlip shown now (FlipClip.START .. LAND while airborne)
var flip_land := -1.0            ## s since the flip landed (presentation of its landing; -1 = none)
var flip_time := 0.0             ## s since the flip took off
var flips := 0
var flip_direction := Vector3.ZERO
var flip_rates: Array[float] = []    ## clip seconds per second used each airborne tick (tests: the turn tracks the airtime)
var _flip_prev_phase := 0.0
var _flip_height := 0.0          ## m from the body to the ground under it (presentation: the drawn feet never go below it)
var _flip_prev_height := 0.0
var _flip_pending := false
var _flip_velocity := Vector3.ZERO
var _yaw := 0.0
var _shimmy_right := Vector3.ZERO    ## the ledge direction the stick was first pushed along (latched until released)


func setup(traversal_params, vault_profile, movement_params, exclude: Array[RID] = []) -> void:
	params = traversal_params
	vault.setup(traversal_params, vault_profile, exclude)
	mantle.exclude = exclude
	capabilities.setup(movement_params, traversal_params)
	vault.capabilities = capabilities
	mantle.capabilities = capabilities
	resources.setup(capabilities)


func enabled() -> bool:
	return params != null and params.is_on("traversal")


func busy() -> bool:
	return vault.active() or mantle.active() or mantle.hanging()


func wish_direction() -> Vector3:
	return _wish


## Before the movement core: interprets Space. Returns the input the core will see.
func filter_input(input: Dictionary, body = null, dt := 1.0 / 120.0) -> Dictionary:
	var move: Vector2 = input.get("move", Vector2.ZERO)
	_yaw = float(input.get("yaw", 0.0))
	_wish = Basis(Vector3.UP, _yaw) * Vector3(move.x, 0.0, -move.y)
	var pressed: bool = input.get("jump_pressed", false)
	var crouch: bool = input.get("crouch", false)
	var crouch_edge := crouch and not _crouch_prev
	_crouch_prev = crouch
	input = vault.filter_input(input)   # swallows presses while a vault is armed or active
	if body == null or not enabled():
		return input
	if mantle.hanging():
		return _hang_input(body, input, pressed, crouch_edge)
	_slide_crouch = crouch
	# A slide starts on a crouch press at speed, or when crouch is held through a landing at speed.
	var landed: bool = body.is_on_floor() and not _was_on_floor
	_was_on_floor = body.is_on_floor()
	if crouch and (crouch_edge or landed or _slide_pending) and not sliding and not busy():
		_slide_pending = not _try_slide(body) and not body.is_on_floor()
	if busy() or vault.armed():
		if pressed and _progress() >= CHAIN_FROM:
			intent_left = maxf(body.core.p.jump_buffer_time, dt)
			chained = true
			press_age = 0.0
			_record("buffered")
		elif pressed:
			_record("swallowed")
		return _without_jump(input)
	if pressed:
		intent_left = maxf(body.core.p.jump_buffer_time, dt)
		chained = false
		press_age = 0.0
		catch_left = CATCH_BUFFER
	if body.is_on_floor():
		catch_left = 0.0
		if intent_left > 0.0 and press_age <= MAX_PRESS_AGE:
			if crouch or sliding:
				var flip := _try_flip(body, input, pressed)
				if not flip.is_empty():
					return flip
			return _ground_press(body, input, pressed)
		intent_left = 0.0
		return input
	if flipping and flip_phase < FlipClip.UPRIGHT:
		if pressed:
			_record("buffered")      # upside down: no catch, no air jump; the press waits for the landing buffer
		return _without_jump(input)
	if pressed and body.core.coyote_left > 0.0:
		intent_left = 0.0
		catch_left = 0.0
		_record("jump")
		return input   # coyote jump: the core takes it this tick
	if (pressed or catch_left > 0.0) and press_age <= MAX_PRESS_AGE:
		_air_press(body, pressed)
	elif not mantle.active() and _touching_wall(body):
		_try_hang(body)
	return _without_jump(input)   # in the air the controller owns every press until the feet are down


## Crouch at speed on the ground: a slide that runs on its own momentum (see adjust()). Any other crouch is the ordinary
## crouch of the movement core.
func _try_slide(body) -> bool:
	var flat := Vector3(body.velocity.x, 0.0, body.velocity.z)
	if not body.is_on_floor() or flat.length() < capabilities.get_value("slide_min_speed"):
		return false
	var grant := _authorize("slide", {}, false, false)
	if grant.has("refusal"):
		last_refusal = grant.refusal
		return false
	resources.spend(grant.cost)
	var boost: float = capabilities.get_value("slide_boost")
	slide_velocity = flat.normalized() * minf(flat.length() + boost, capabilities.get_value("slide_max_speed"))
	sliding = true
	slide_time = 0.0
	slide_exit = -1.0
	slides += 1
	vault.cancel()
	_record("slide")
	return true


## Crouched press on the ground: a front flip. A physics jump (flip_impulse) that keeps every bit of horizontal
## momentum, a slide's included, and leaves with at least flip_forward along the facing; gravity, air control and
## collisions stay the movement core's. Returns the input for the core, or {} when the flip is not available (no
## capability, no stamina: the press is then the ordinary jump or slide jump). Without standing room above (under a
## bar) the press is refused and nothing jumps.
func _try_flip(body, input: Dictionary, pressed: bool) -> Dictionary:
	var grant := _authorize("flip", {})
	if grant.has("refusal"):
		last_refusal = grant.refusal
		return {}
	if not body.can_rise_to(body.params.get_value("stand_height")):
		last_refusal = "flip: no_headroom"
		_finish_press("flip_refused")
		return _without_jump(input)
	resources.spend(grant.cost)
	var flat: Vector3 = slide_velocity if sliding else Vector3(body.velocity.x, 0.0, body.velocity.z)
	var dir: Vector3
	if flat.length() > 0.5:
		dir = flat.normalized()
	elif _wish.length_squared() > 0.01:
		dir = _wish.normalized()
	else:
		dir = Basis(Vector3.UP, _yaw) * Vector3.FORWARD
	var along := flat.dot(dir)
	var least: float = capabilities.get_value("flip_forward")
	if along < least:
		flat += dir * (least - along)
	_flip_velocity = flat
	flip_direction = dir
	if sliding:
		_end_slide(body, false)
	vault.cancel()
	_flip_pending = true
	_finish_press("flip")
	if pressed:
		return input
	input = input.duplicate()
	input.jump_pressed = true
	return input


## The flip's clock, after the body moved: the airborne turn is spread over the real airtime, predicted each tick from
## the ground below (a flip off a ledge turns slower, onto a box faster), so it lands upright wherever it lands.
func _flip_observe(body, dt: float) -> void:
	if flip_land >= 0.0:
		flip_land += dt
		if flip_land > FlipClip.END - FlipClip.LAND:
			flip_land = -1.0
	if not flipping:
		return
	flip_time += dt
	_flip_prev_phase = flip_phase
	_flip_prev_height = _flip_height
	if flip_time > 0.05 and body.is_on_floor():
		flipping = false
		flip_land = 0.0
		return
	var remaining := _time_to_ground(body)
	var rate := 1.0 if not is_finite(remaining) else (FlipClip.LAND - flip_phase) / maxf(remaining, dt)
	rate = clampf(rate, 0.6, 3.0)
	flip_rates.append(rate)
	flip_phase = minf(flip_phase + rate * dt, FlipClip.LAND)
	if flip_phase >= FlipClip.LAND:
		flipping = false             # turned and still falling (a long drop): the ordinary fall and landing take over
		flip_land = -1.0


## Seconds until the body's ballistic path meets the ground under it (INF without ground within 30 m).
func _time_to_ground(body) -> float:
	var space: PhysicsDirectSpaceState3D = body.get_world_3d().direct_space_state
	var from: Vector3 = body.global_position + Vector3.UP * 0.05
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 30.0, body.collision_mask, [body.get_rid()])
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		_flip_height = 30.0
		return INF
	var h: float = maxf(0.0, body.global_position.y - (hit.position as Vector3).y)
	_flip_height = h
	var vy: float = body.core.velocity.y
	var g: float = maxf(0.1, float(body.core.p.gravity))
	return (vy + sqrt(vy * vy + 2.0 * g * h)) / g


## One tick of slide momentum, after the movement core (whose crouch walk it replaces while sliding): proportional and
## constant slowing, gravity along the slope, and steering limited to slide_steer. Ends below slide_end_speed or when
## crouch is released - standing only where there is headroom; under something low it keeps scooting.
func _slide_tick(body, dt: float) -> void:
	var core = body.core
	if core.just_jumped:
		_end_slide(body, false)          # a slide jump keeps the slide's speed (the core already carried it)
		return
	if not body.is_on_floor() and not core.grounded:
		return                           # airborne off an edge: momentum is the core's until the feet are down
	slide_time += dt
	var v := slide_velocity
	var speed := v.length()
	var n: Vector3 = body.get_floor_normal() if body.is_on_floor() else Vector3.UP
	var gravity := Vector3.DOWN * float(core.p.gravity)
	var along := gravity - n * gravity.dot(n)
	v += Vector3(along.x, 0.0, along.z) * capabilities.get_value("slide_slope_gain") * dt
	speed = v.length()
	if speed > 0.0001:
		var slowed := maxf(0.0, speed - (capabilities.get_value("slide_friction") * speed + capabilities.get_value("slide_drag")) * dt)
		v *= slowed / speed
		speed = slowed
	if _wish.length_squared() > 0.01 and speed > 0.1:
		var heading := v / speed
		var wanted := _wish.normalized()
		var angle := heading.signed_angle_to(wanted, Vector3.UP)
		if absf(angle) < 2.0:            # a stick pulled back brakes (friction), it does not spin the slide around
			var limit: float = capabilities.get_value("slide_steer") * dt
			v = heading.rotated(Vector3.UP, clampf(angle, -limit, limit)) * speed
	speed = minf(v.length(), capabilities.get_value("slide_max_speed"))
	v = v.normalized() * speed if speed > 0.0001 else Vector3.ZERO
	var low_room: bool = not body.can_rise_to(body.params.get_value("crouch_height"))
	if (speed < capabilities.get_value("slide_end_speed") or not _slide_crouch) and not low_room:
		_end_slide(body, true)
		return
	if low_room and speed < 1.0:
		v = (v.normalized() if speed > 0.01 else Vector3(core.velocity.x, 0.0, core.velocity.z).normalized()) * 1.0   # scoot out
	slide_velocity = v
	var full := Vector3(v.x, 0.0, v.z)
	full -= n * full.dot(n)
	if full.length() > 0.0001:
		full = full.normalized() * v.length()
	core.velocity = full + Vector3.UP * minf(core.velocity.y, 0.0)
	body.height_override = capabilities.get_value("slide_height")


func _end_slide(body, standing: bool) -> void:
	sliding = false
	body.height_override = 0.0
	slide_exit = 0.0 if standing and not _slide_crouch else -1.0


## While hanging: a new press pulls up and over (the whole climb, no further input); crouch or pulling the stick away
## from the wall lets go. A press whose climb is not possible (no room on top, blocked) keeps the hang and says why.
func _hang_input(body, input: Dictionary, pressed: bool, crouch_edge: bool) -> Dictionary:
	# The stick is read in the ledge frame it was first pushed in, until it is released: holding "right" keeps going
	# round a corner and on along the next wall, even though the camera-relative stick now points elsewhere.
	if _wish.length_squared() < 0.01:
		_shimmy_right = Vector3.ZERO
	elif _shimmy_right == Vector3.ZERO:
		_shimmy_right = mantle.plan.direction.cross(Vector3.UP)
	var right: Vector3 = _shimmy_right if _shimmy_right != Vector3.ZERO else mantle.plan.direction.cross(Vector3.UP)
	var wall: Vector3 = Vector3.UP.cross(right)            # into the wall in that frame
	var away := _wish.length_squared() > 0.01 and _wish.normalized().dot(wall) < -0.5
	# Along the ledge it shimmies (hand over hand), with a dead zone so a stick held toward the wall does not drift.
	var along: float = _wish.dot(right) if _wish.length_squared() > 0.01 else 0.0
	mantle.shimmy_wish = 0.0 if absf(along) < 0.35 else signf(along) * minf(1.0, absf(along))
	if crouch_edge or away:
		mantle.drop(body)
		_record("let_go")
	elif pressed:
		press_age = 0.0
		last_refusal = ""
		var climb: Dictionary = mantle.evaluate(body, mantle.plan.direction, true, true)
		if not climb.get("ok", false):
			last_refusal = "climb: " + String(climb.get("reason", "no_ledge"))
			_record("hang_refused")
		else:
			var grant := _authorize("mantle", climb, climb.powered)
			if grant.has("refusal"):
				last_refusal = grant.refusal
				_record("hang_refused")
			elif mantle.start(body, climb, grant):
				resources.spend(grant.cost)
				_finish_press("pullup_over" if climb.kind == "over" else "pullup")
	return _without_jump(input)


## The airborne body is pressed against a wall-like surface this tick (its last move slid along one).
func _touching_wall(body) -> bool:
	if not capabilities.can("mantle"):
		return false
	for i in body.get_slide_collision_count():
		var n: Vector3 = body.get_slide_collision(i).get_normal()
		if absf(n.y) < MantleAction.MAX_TILT:
			return true
	return false


## Catch on contact: a reachable edge high enough to hang from, approached (wished) toward, held by the grip.
func _try_hang(body) -> bool:
	var d := _direction(body)
	if d == Vector3.ZERO or _wish.length_squared() < 0.01:
		return false
	var climb: Dictionary = mantle.evaluate(body, d, true)
	if not mantle.can_hang(body, climb) or _wish.normalized().dot(climb.direction) < MantleAction.MIN_TOWARD:
		return false
	var grant := _authorize("hang", climb, false, false)
	if grant.has("refusal"):
		last_refusal = grant.refusal
		return false
	if not mantle.begin_hang(body, climb, grant):
		return false
	vault.cancel()
	catch_left = 0.0
	intent_left = 0.0
	_record("hang")
	return true


## Fraction of the committed move done (vault: clip time to landing; mantle: clip time to release).
func _progress() -> float:
	if vault.active() or vault.armed():
		return clampf(vault.time / VaultAction.Clip.LANDING, 0.0, 1.0) if vault.active() else 0.0
	if mantle.active():
		return clampf((mantle.time - mantle.plan.start) / (MantleAction.Clip.RELEASE - mantle.plan.start), 0.0, 1.0)
	return 0.0


func _without_jump(input: Dictionary) -> Dictionary:
	if input.get("jump_pressed", false) or input.get("jump_held", false):
		input = input.duplicate()
		input.jump_pressed = false
		input.jump_held = false
	return input


func _record(choice: String) -> void:
	last_choice = choice
	choices[choice] = int(choices.get(choice, 0)) + 1


func _direction(body) -> Vector3:
	var flat := Vector3(body.velocity.x, 0.0, body.velocity.z)
	if _wish.length_squared() > 0.01:
		return _wish.normalized()
	if flat.length() > 0.15:
		return flat.normalized()
	return Vector3.ZERO


## The one gate every move start passes. Returns the grant ({move, plan, cost}) the actions require, or {refusal}.
func _authorize(move: String, candidate: Dictionary, powered := false, needs_press := true) -> Dictionary:
	if needs_press and press_age > MAX_PRESS_AGE:
		return {"refusal": move + ": no_recent_press"}
	if not capabilities.can("mantle" if move == "hang" else move):
		return {"refusal": move + ": not_capable"}
	if powered and not capabilities.can("powered_traversal"):
		return {"refusal": move + ": needs_upgrade"}
	var cost := _cost(move, powered)
	var why: String = resources.refusal(cost)
	if why != "":
		return {"refusal": move + ": " + why}
	return {"move": move, "plan": candidate, "cost": cost}


## A press (fresh or buffered) with the feet on the ground.
func _ground_press(body, input: Dictionary, pressed: bool) -> Dictionary:
	last_refusal = ""
	# A buffered press (chained out of a move) or the first tick on the ground after a fall: the vault has not looked
	# ahead from here yet.
	if (not pressed or not body.core.grounded) and vault.opportunity.is_empty() and vault.enabled() and vault.phase == VaultAction.Phase.IDLE:
		var flat := Vector3(body.velocity.x, 0.0, body.velocity.z)
		if flat.length() >= VaultAction.Planner.MIN_ENTRY_SPEED and _wish.length_squared() > 0.01 and _wish.normalized().dot(flat.normalized()) >= VaultAction.MIN_ALIGNMENT:
			vault.evaluate(body, flat.normalized(), flat.length())
	if not vault.opportunity.is_empty():
		var offer: Dictionary = vault.opportunity
		var grant := _authorize("vault", offer, offer.get("powered", false))
		if grant.has("refusal"):
			last_refusal = grant.refusal
		elif vault.commit(body, grant):
			resources.spend(grant.cost)
			_finish_press("late_vault" if vault.active() else "vault")
			return _without_jump(input)
	var d := _direction(body)
	# A vaultable obstacle closer than the interaction region: the window was missed. The consequence is predictable:
	# the ordinary jump (a catch is then possible from the air) - never a climb straight from the ground.
	var near: float = vault.region.get("near", VaultAction.Planner.latest_takeoff(VaultAction.Planner.MIN_TRAVEL)) + 0.05
	if last_refusal == "" and vault.vaultable_ahead(body, d, near):
		var slow: bool = Vector2(body.velocity.x, body.velocity.z).length() < VaultAction.Planner.MIN_ENTRY_SPEED
		if vault.reason in ["blocked", "out_of_reach", "body_clip", "no_hand_contact"]:
			last_refusal = "vault: " + vault.reason
		else:
			last_refusal = "vault: too slow (run at it)" if slow else "vault: missed window (too close)"
		return _jump(input, pressed)
	if d != Vector3.ZERO:
		var climb: Dictionary = mantle.evaluate(body, d, false)
		if climb.get("ok", false):
			var grant := _authorize("mantle", climb, climb.powered)
			if grant.has("refusal"):
				last_refusal = grant.refusal
			elif mantle.start(body, climb, grant):
				resources.spend(grant.cost)
				vault.cancel()
				_finish_press("over" if climb.kind == "over" else "mantle")
				return _without_jump(input)
		elif not climb.is_empty() and last_refusal == "":
			last_refusal = "climb: " + String(climb.reason)
	if last_refusal == "" and vault.reason != "" and vault.reason not in ["ok", "ahead"]:
		last_refusal = "vault: " + vault.reason
	return _jump(input, pressed)


## Nothing to traverse: the ordinary jump (a buffered press is handed to the core now, exactly when its own buffer
## would have fired).
func _jump(input: Dictionary, pressed: bool) -> Dictionary:
	_finish_press("jump")
	if pressed:
		return input
	input = input.duplicate()
	input.jump_pressed = true
	return input


## A press while airborne (no coyote), or one still looking for a ledge: catch, else air jump, else keep looking.
func _air_press(body, pressed: bool) -> void:
	if pressed:
		last_refusal = ""
	if _try_catch(body, pressed):
		return
	if pressed and capabilities.can("air_jump") and air_jumps_used < int(capabilities.get_value("air_jumps")):
		var grant := _authorize("air_jump", {})
		if grant.has("refusal"):
			last_refusal = grant.refusal
		else:
			resources.spend(grant.cost)
			air_jumps_used += 1
			_air_jump_pending = true
			air_jump_time = 0.0
			catch_left = 0.0
			_finish_press("air_jump")
			return
	if pressed:
		_record("buffered")


## Catch a ledge in reach and climb onto / over it. Only ever called for a recent press.
func _try_catch(body, pressed := true) -> bool:
	var d := _direction(body)
	if d == Vector3.ZERO or _wish.length_squared() < 0.01 or _wish.normalized().dot(d) < CATCH_WISH:
		if last_refusal == "":
			last_refusal = "catch: steer toward the ledge"
		return false
	var climb: Dictionary = mantle.evaluate(body, d, true)
	if not climb.get("ok", false):
		if not climb.is_empty() and (pressed or last_refusal == ""):   # a buffered retry keeps the press's own reason
			last_refusal = "catch: " + String(climb.reason)
		return false
	var grant := _authorize("mantle", climb, climb.powered)
	if grant.has("refusal"):
		last_refusal = grant.refusal
		return false
	if not mantle.start(body, climb, grant):
		return false
	resources.spend(grant.cost)
	vault.cancel()
	catch_left = 0.0
	_finish_press("catch_over" if climb.kind == "over" else "catch")
	return true


func _finish_press(choice: String) -> void:
	intent_left = 0.0
	chained = false
	_record(choice)


func _cost(move: String, powered: bool) -> Dictionary:
	if move == "hang":
		return {}
	if move == "slide":
		return {"stamina": capabilities.get_value("stamina_cost_slide")}
	if move == "flip":
		return {"stamina": capabilities.get_value("stamina_cost_flip")}
	if move == "air_jump":
		return {"mana": capabilities.get_value("mana_cost_air_jump")}
	var cost := {"stamina": capabilities.get_value("stamina_cost_" + move)}
	if powered:
		cost["energy"] = capabilities.get_value("energy_cost_assist")
		cost["heat"] = capabilities.get_value("heat_per_assist")
	return cost


func drive(body, dt: float) -> bool:
	var consumed: bool = mantle.drive(body, dt)
	if consumed:
		vault.drive(body, dt)   # keeps the vault's presentation clock and offsets decaying
		return true
	return vault.drive(body, dt)


func adjust(body, dt: float) -> void:
	vault.adjust(body, dt)
	if sliding:
		_slide_tick(body, dt)
	if _air_jump_pending:
		_air_jump_pending = false
		body.core.velocity.y = maxf(body.core.velocity.y, capabilities.get_value("air_jump_impulse"))
	if _flip_pending:
		_flip_pending = false
		if body.core.just_jumped:
			flipping = true
			flip_time = 0.0
			flip_phase = FlipClip.START
			_flip_prev_phase = flip_phase
			_flip_height = 0.0
			_flip_prev_height = 0.0
			flip_land = -1.0
			flips += 1
			flip_rates.clear()
			body.core.velocity = Vector3(_flip_velocity.x, capabilities.get_value("flip_impulse"), _flip_velocity.z)
	if flipping:
		body.core.crouching = true   # the crouch collider stands in for the tucked body (as in every traversal move)


func observe(body, dt: float) -> void:
	var grounded: bool = body.core.grounded
	if body.core.just_jumped:
		resources.spend({"stamina": capabilities.get_value("stamina_cost_jump")})
	vault.observe(body, dt)
	_flip_observe(body, dt)
	if grounded:
		air_jumps_used = 0
	catch_preview = {}
	if not grounded and enabled() and params.is_on("debug_overlay"):
		var d := _direction(body)
		if d != Vector3.ZERO:
			catch_preview = mantle.evaluate(body, d, true)
	air_jump_time += dt
	_tick(dt, grounded)


## Time passes on every tick, including ticks consumed by a move.
func _tick(dt: float, grounded: bool) -> void:
	press_age += dt
	if slide_exit >= 0.0:
		slide_exit += dt
	if intent_left > 0.0 and not (busy() or vault.armed()):
		intent_left = maxf(0.0, intent_left - dt)
	if catch_left > 0.0 and not busy():
		catch_left = maxf(0.0, catch_left - dt)
	capabilities.tick(dt)
	resources.tick(dt, grounded)


## Called by the body on ticks a move consumed (no observe on those).
func consumed_tick(dt: float) -> void:
	air_jump_time += dt
	_tick(dt, false)


func cancel() -> void:
	vault.cancel()
	mantle.cancel()
	intent_left = 0.0
	catch_left = 0.0
	press_age = INF
	chained = false
	_air_jump_pending = false
	air_jumps_used = 0
	sliding = false
	slide_exit = -1.0
	flipping = false
	flip_land = -1.0
	_flip_pending = false


func offset(fraction: float) -> Vector3:
	return vault.offset(fraction) + mantle.offset(fraction)


func follow_offset(fraction: float) -> Vector3:
	return vault.follow_offset(fraction) + mantle.offset(fraction)


## Everything the animation needs this frame.
func presentation(fraction: float) -> Dictionary:
	var result: Dictionary = vault.presentation(fraction)
	var climb := mantle.presentation(fraction)
	if not climb.is_empty():
		result["vault"] = false
		result.erase("approach")
		result["mantle"] = climb
	if air_jump_time < 1.0:
		result["air_jump"] = air_jump_time
	if sliding or (slide_exit >= 0.0 and slide_exit < 0.5):
		result["slide"] = {"time": slide_time, "speed": slide_velocity.length(), "exit": slide_exit}
	if flipping or flip_land >= 0.0:
		var shown := lerpf(_flip_prev_phase, flip_phase, fraction) if flipping else FlipClip.LAND + flip_land
		# drop: while airborne the body's arc is the flip's height, so the clip's own hip rise is taken off the drawn
		# character (never below the ground under it). The animation applies it by the flip pose's blend weight, since a
		# pose still fading out (crouch, slide) has its feet at the root.
		var height := lerpf(_flip_prev_height, _flip_height, fraction) if flipping else 0.0
		var drop := FlipClip.drawn_drop(shown, height) if flipping else 0.0
		result["flip"] = {"time": shown, "airborne": flipping, "heading": atan2(-flip_direction.x, -flip_direction.z), "drop": drop,
			"height": height}
	return result
