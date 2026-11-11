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
##
## Authorization is central: every move start goes through _authorize(), which requires a press no older than
## MAX_PRESS_AGE, the capability and the resources, and returns the grant that vault_action.commit() and
## mantle_action.start() demand. Contact, held Space, and the body's own state can never start a move. Buffered
## presses mirror the movement core's jump buffer exactly, so jump timing (and bunny hops) are unchanged.
## Deterministic on the fixed tick; the input frame is the only per-tick input (multiplayer replay).
extends RefCounted

const VaultAction = preload("res://traversal/vault_action.gd")
const MantleAction = preload("res://traversal/mantle_action.gd")
const Capabilities = preload("res://capability/movement_capabilities.gd")
const Resources = preload("res://capability/movement_resources.gd")

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
	return vault.active() or mantle.active()


func wish_direction() -> Vector3:
	return _wish


## Before the movement core: interprets Space. Returns the input the core will see.
func filter_input(input: Dictionary, body = null, dt := 1.0 / 120.0) -> Dictionary:
	var move: Vector2 = input.get("move", Vector2.ZERO)
	_wish = Basis(Vector3.UP, float(input.get("yaw", 0.0))) * Vector3(move.x, 0.0, -move.y)
	var pressed: bool = input.get("jump_pressed", false)
	input = vault.filter_input(input)   # swallows presses while a vault is armed or active
	if body == null or not enabled():
		return input
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
			return _ground_press(body, input, pressed)
		intent_left = 0.0
		return input
	if pressed and body.core.coyote_left > 0.0:
		intent_left = 0.0
		catch_left = 0.0
		_record("jump")
		return input   # coyote jump: the core takes it this tick
	if (pressed or catch_left > 0.0) and press_age <= MAX_PRESS_AGE:
		_air_press(body, pressed)
	return _without_jump(input)   # in the air the controller owns every press until the feet are down


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
func _authorize(move: String, candidate: Dictionary, powered := false) -> Dictionary:
	if press_age > MAX_PRESS_AGE:
		return {"refusal": move + ": no_recent_press"}
	if not capabilities.can(move):
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
	if _try_catch(body):
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
func _try_catch(body) -> bool:
	var d := _direction(body)
	if d == Vector3.ZERO or _wish.length_squared() < 0.01 or _wish.normalized().dot(d) < CATCH_WISH:
		if last_refusal == "":
			last_refusal = "catch: steer toward the ledge"
		return false
	var climb: Dictionary = mantle.evaluate(body, d, true)
	if not climb.get("ok", false):
		if not climb.is_empty():
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
	if _air_jump_pending:
		_air_jump_pending = false
		body.core.velocity.y = maxf(body.core.velocity.y, capabilities.get_value("air_jump_impulse"))


func observe(body, dt: float) -> void:
	var grounded: bool = body.core.grounded
	if body.core.just_jumped:
		resources.spend({"stamina": capabilities.get_value("stamina_cost_jump")})
	vault.observe(body, dt)
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
	return result
