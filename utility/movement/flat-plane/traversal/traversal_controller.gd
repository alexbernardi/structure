## Unified traversal (Movement Lab 5.0): the character body's one physical action. Every traversal move - jump,
## vault, mantle, ledge grab, air jump - is a response to the same intent (Space) chosen from the sensed geometry, the
## body's motion and the character's capabilities, by one fixed set of rules:
##
##   grounded press  vault (inside its interaction region)  >  mantle (a climbable top in reach)  >  jump
##   airborne press  ledge grab (a top within grip reach)    >  air jump (capability)              >  buffer
##   holding Space while airborne into a ledge also grabs it (jump-and-grab)
##   presses while a move is committed are swallowed; in its second half they buffer and chain into the next move
##   on landing (vault / mantle if one is offered, else a jump that keeps the landing momentum)
##
## Nothing here moves the character without a press: approaching an obstacle never starts a move. Sensing (probes),
## planning (vault_planner / mantle_action.evaluate) and execution (vault_action / mantle_action drive the collider
## kinematically with collision response) stay separate; the animation only reads presentation().
## Buffered presses mirror the movement core's jump buffer exactly, so the core's jump timing (and bunny hops) are
## unchanged. Deterministic on the fixed tick; the input frame is the only per-tick input (multiplayer replay).
extends RefCounted

const VaultAction = preload("res://traversal/vault_action.gd")
const MantleAction = preload("res://traversal/mantle_action.gd")
const Capabilities = preload("res://capability/movement_capabilities.gd")
const Resources = preload("res://capability/movement_resources.gd")

const CHAIN_FROM := 0.5          ## share of a committed move after which a press buffers for the next move
const GRAB_WISH := 0.5           ## wished direction . travel needed for a ledge grab

var params                       ## traversal_params (the traversal switch)
var vault := VaultAction.new()
var mantle := MantleAction.new()
var capabilities = Capabilities.new()
var resources = Resources.new()
var intent_left := 0.0           ## s left on a buffered press (0 = none)
var chained := false             ## the buffered press was made during a committed move
var last_choice := ""            ## what the latest press did: jump / vault / late_vault / mantle / grab / air_jump / buffered / swallowed
var last_refusal := ""           ## why the preferred move was not taken on the latest press
var air_jumps_used := 0
var air_jump_time := INF         ## s since the latest air jump (presentation)
var choices := {}                ## choice -> count (telemetry, tests)
var _wish := Vector3.ZERO
var _air_jump_pending := false
var _was_busy := false
var _just_released := false


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
	var held: bool = input.get("jump_held", false)
	input = vault.filter_input(input)   # swallows presses while a vault is armed or active
	if body == null or not enabled():
		return input
	if busy() or vault.armed():
		if pressed and _progress() >= CHAIN_FROM:
			intent_left = maxf(body.core.p.jump_buffer_time, dt)
			chained = true
			_record("buffered")
		elif pressed:
			_record("swallowed")
		return _without_jump(input)
	if pressed:
		intent_left = maxf(body.core.p.jump_buffer_time, dt)
		chained = false
	var on_floor: bool = body.is_on_floor()
	if intent_left > 0.0:
		if on_floor:
			return _ground_press(body, input, pressed)
		if pressed and body.core.coyote_left > 0.0:
			intent_left = 0.0
			_record("jump")
			return input   # coyote jump: the core takes it this tick
		return _air_press(body, input, pressed)
	if held and not on_floor and _try_grab(body):
		return _without_jump(input)
	return input


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
		var refusal := _refusal("vault", offer.get("powered", false), offer)
		if refusal == "" and vault.commit(body):
			_pay("vault", offer)
			_finish_press("late_vault" if vault.active() else "vault")
			return _without_jump(input)
		last_refusal = refusal
	elif vault.reason != "" and vault.reason != "ok" and vault.reason != "ahead":
		last_refusal = "vault: " + vault.reason
	var d := _direction(body)
	if d != Vector3.ZERO and capabilities.can("mantle"):
		var climb: Dictionary = mantle.evaluate(body, d, false)
		if climb.get("ok", false):
			var refusal := _refusal("mantle", climb.powered, climb)
			if refusal == "":
				_start_mantle(body, climb)
				_finish_press("mantle")
				return _without_jump(input)
			last_refusal = refusal
		elif not climb.is_empty() and last_refusal == "":
			last_refusal = "mantle: " + String(climb.reason)
	# Nothing to traverse: the ordinary jump (a buffered press is handed to the core now, exactly when its own buffer
	# would have fired).
	_finish_press("jump")
	if pressed:
		return input
	input = input.duplicate()
	input.jump_pressed = true
	return input


## A press while airborne (no coyote): grab a ledge, else air jump, else keep it buffered for the landing.
func _air_press(body, input: Dictionary, pressed: bool) -> Dictionary:
	if _try_grab(body):
		_finish_press("grab")
		return _without_jump(input)
	if pressed and capabilities.can("air_jump") and air_jumps_used < int(capabilities.get_value("air_jumps")):
		var cost := {"mana": capabilities.get_value("mana_cost_air_jump")}
		var refusal: String = resources.refusal(cost)
		if refusal == "":
			resources.spend(cost)
			air_jumps_used += 1
			_air_jump_pending = true
			air_jump_time = 0.0
			_finish_press("air_jump")
			return _without_jump(input)
		last_refusal = "air_jump: " + refusal
	if pressed:
		_record("buffered")
	return _without_jump(input)   # the controller owns the buffered press until the feet are down


func _try_grab(body) -> bool:
	if not capabilities.can("mantle"):
		return false
	var d := _direction(body)
	if d == Vector3.ZERO or _wish.length_squared() < 0.01 or _wish.normalized().dot(d) < GRAB_WISH:
		return false
	var climb: Dictionary = mantle.evaluate(body, d, true)
	if not climb.get("ok", false):
		return false
	if _refusal("mantle", climb.powered, climb) != "":
		return false
	_start_mantle(body, climb)
	if last_choice != "grab":
		_record("grab")
	return true


func _start_mantle(body, climb: Dictionary) -> void:
	_pay("mantle", climb)
	mantle.start(body, climb)
	vault.cancel()


func _finish_press(choice: String) -> void:
	intent_left = 0.0
	chained = false
	_record(choice)


func _cost(move: String, powered: bool) -> Dictionary:
	var cost := {"stamina": capabilities.get_value("stamina_cost_" + move)}
	if powered:
		cost["energy"] = capabilities.get_value("energy_cost_assist")
		cost["heat"] = capabilities.get_value("heat_per_assist")
	return cost


## "" when `move` may be done now; otherwise why not (capability, or a resource).
func _refusal(move: String, powered: bool, candidate: Dictionary) -> String:
	if not capabilities.can(move):
		return move + ": not_capable"
	if powered and not capabilities.can("powered_traversal"):
		return move + ": needs_upgrade"
	var why: String = resources.refusal(_cost(move, powered))
	candidate["cost"] = _cost(move, powered)
	return "" if why == "" else move + ": " + why


func _pay(move: String, candidate: Dictionary) -> void:
	resources.spend(candidate.get("cost", _cost(move, false)))


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
	air_jump_time += dt
	_tick(dt, grounded)


## Time passes on every tick, including ticks consumed by a move.
func _tick(dt: float, grounded: bool) -> void:
	if intent_left > 0.0 and not (busy() or vault.armed()):
		intent_left = maxf(0.0, intent_left - dt)
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
