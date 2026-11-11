## Movement Core - the public entry point (contract: SYSTEM-ROOMS/movement_core/CONTRACT.md).
##
## One node that assembles an approved movement character: the collision body and movement core, the traversal
## controller (vault, mantle, catch-and-hang, shimmy, corners, slide, flip, air jump), the capability layer
## (attributes, modifiers, resources) and the authored presentation (Quaternius mannequin, AnimationTree, hand / foot IK).
##
##   var character = preload("res://systems/movement_core/movement_character.gd").new()
##   add_child(character)                      # builds itself in _ready (or call build() first)
##   character.spawn(Transform3D(Basis.IDENTITY, Vector3(0, 0.05, 0)))
##   # every physics tick (120 Hz):             character.simulate(frame, dt)
##   # every rendered frame:                    character.present(delta)
##   # or let it drive itself from the keyboard: character.drive_self = true; character.input_yaw = camera_yaw
##
## Other systems read state through the getters and signals below and change movement only through modifiers
## (MovementModifier), the traversal switch, teleport / spawn and apply_impulse(). Everything else is private.
extends Node3D

const VERSION := "1.0.0"
const TICK_RATE := 120   ## Hz the movement and traversal are tuned and tested at (pass dt = 1.0 / TICK_RATE)

const Body = preload("res://systems/movement_core/character/character_body.gd")
const Params = preload("res://systems/movement_core/movement/movement_params.gd")
const Actions = preload("res://systems/movement_core/movement/input_actions.gd")
const InputSource = preload("res://systems/movement_core/movement/input_source.gd")
const AuthoredVisual = preload("res://systems/movement_core/character/authored_mannequin.gd")
const AuthoredAnimation = preload("res://systems/movement_core/animation/authored_animation.gd")
const LocomotionParams = preload("res://systems/movement_core/animation/locomotion_params.gd")
const TraversalParams = preload("res://systems/movement_core/traversal/traversal_params.gd")
const VaultProfile = preload("res://systems/movement_core/traversal/vault_profile.gd")
const TraversalController = preload("res://systems/movement_core/traversal/traversal_controller.gd")
const TraversalDebug = preload("res://systems/movement_core/traversal/vault_debug.gd")
const SkeletonOverlay = preload("res://systems/movement_core/animation/skeleton_overlay.gd")
const Modifier = preload("res://systems/movement_core/capability/movement_modifier.gd")
const Profiles = preload("res://systems/movement_core/capability/movement_profiles.gd")

## Emitted when the body lands (impact: downward speed in m/s just before touching down).
signal landed(impact_speed: float)
## Emitted after respawn() (falling below the kill height respawns too).
signal respawned
## The movement state changed (see STATES).
signal state_changed(previous: String, current: String)
## A traversal move began / ended (one of TRAVERSAL_STATES).
signal traversal_started(move: String)
signal traversal_finished(move: String)
## A modifier was added or removed (attributes or capabilities may have changed).
signal capabilities_changed

const STATES := ["grounded", "crouching", "airborne", "sliding", "flipping", "vaulting", "mantling", "hanging"]
const TRAVERSAL_STATES := ["sliding", "flipping", "vaulting", "mantling", "hanging"]
const SKELETON_VIEW_ALPHA := 0.4   ## body opacity while the skeleton view is on

var params: Params = Params.new()                   ## baseline movement parameters (tunable)
var traversal_params = TraversalParams.create()     ## traversal switches and tunables
var locomotion_params = LocomotionParams.create()   ## authored-animation tunables
var vault_profile = VaultProfile.new()              ## the authored vault measured on the mannequin
var traversal = TraversalController.new()           ## jump / vault / mantle / grab / hang / slide / flip / air jump
var vault = traversal.vault
var capabilities = traversal.capabilities           ## effective attributes, modifiers and capabilities
var body                                            ## character_body.gd (CharacterBody3D) once built
var visual                                          ## authored_mannequin.gd (the drawn character)
var animation                                       ## authored_animation.gd (AnimationTree + IK)
var skeleton_overlay                                ## animation/skeleton_overlay.gd once the skeleton view was opened

var presentation := true      ## false: the drawn character is hidden and not animated (the body moves identically)
var traversal_clips := true   ## false: build as if the traversal clips were not installed (no vault / mantle presentation)
var drive_self := false       ## true: sample the keyboard every tick and present every frame by itself
var input_yaw := 0.0          ## camera yaw used by drive_self (radians; 0 looks along -Z)
var live = InputSource.Live.new()
var state := "airborne"       ## current movement state (STATES)

var _built := false
var _teleported := false


func _ready() -> void:
	if not _built:
		build()


## Assembles the character (add the node to the scene tree first). Configure `params`, `traversal_params`,
## `presentation` and `traversal_clips` before it if needed.
func build() -> void:
	if _built:
		return
	_built = true
	body = Body.new()
	body.name = "Body"
	add_child(body)
	body.setup(params)
	body.landed.connect(func(impact: float) -> void: landed.emit(impact))
	body.respawned.connect(func() -> void:
		_teleported = true
		respawned.emit())
	visual = AuthoredVisual.new()
	visual.name = "AuthoredVisual"
	visual.top_level = true
	visual.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	if not traversal_clips:
		visual.traversal_source = null
		visual.climb_source = null
	body.add_child(visual)
	animation = AuthoredAnimation.new()
	visual.add_child(animation)
	animation.setup(visual, locomotion_params)
	vault_profile.build(visual)
	var exclude: Array[RID] = [body.get_rid()]
	traversal.setup(traversal_params, vault_profile, params, exclude)
	body.core.p = capabilities.core   # the movement core reads the effective (upgraded) parameters
	body.action = traversal
	animation.setup_traversal(traversal_params, vault_profile)
	animation.ray_exclude.append(body.get_rid())   # hang hand and leg probes never hit the character itself
	capabilities.changed.connect(func() -> void: capabilities_changed.emit())
	set_presentation(presentation)
	state = current_state()


## Registers the movement input actions (move_*, jump, sprint, crouch) if the project does not define them.
static func register_input_actions() -> void:
	Actions.register()


## The input frame for a tick: {move: Vector2 (x right, y forward), yaw: float, jump_pressed, jump_held, sprint, crouch}.
static func empty_frame(yaw := 0.0) -> Dictionary:
	return InputSource.empty_frame(yaw)


# ------------------------------------------------------------------------------------------------ simulation

## One fixed physics tick (dt = 1.0 / TICK_RATE). Emits state_changed / traversal_started / traversal_finished.
func simulate(frame: Dictionary, dt: float) -> void:
	body.simulate(frame, dt)
	var now := current_state()
	if now != state:
		var previous := state
		state = now
		if TRAVERSAL_STATES.has(previous):
			traversal_finished.emit(previous)
		if TRAVERSAL_STATES.has(now):
			traversal_started.emit(now)
		state_changed.emit(previous, now)


## Updates the drawn character for one rendered frame. `animate` false keeps it following the body but unanimated.
func present(delta: float, animate := true) -> void:
	var v: Vector3 = body.core.velocity
	var speed := Vector2(v.x, v.z).length()
	var heading := atan2(-v.x, -v.z) if speed > 0.01 else NAN
	var fwd_accel := 0.0
	if speed > 0.01:
		fwd_accel = Vector3(body.core.acceleration.x, 0, body.core.acceleration.z).dot(Vector3(v.x, 0, v.z).normalized())
	animation.follow(body, body.presentation_offset(), _teleported, delta)
	if animate and presentation:
		animation.update(delta, {"speed": animation.measured_speed, "vy": v.y, "grounded": body.core.grounded,
			"crouching": body.core.crouching and not vault.presenting and not traversal.mantle.presenting, "accel_forward": fwd_accel,
			"heading": heading, "teleported": _teleported, "vault": traversal.presentation(Engine.get_physics_interpolation_fraction())})
	_teleported = false


func _physics_process(dt: float) -> void:
	if drive_self and _built:
		simulate(live.sample(input_yaw), dt)


func _process(delta: float) -> void:
	if drive_self and _built:
		present(delta)


## The movement state derived from the body and the traversal controller (one of STATES).
func current_state() -> String:
	if body == null:
		return "airborne"
	if vault.presenting:
		return "vaulting"
	if traversal.mantle.hanging():
		return "hanging"
	if traversal.mantle.presenting:
		return "mantling"
	if traversal.flipping:
		return "flipping"
	if traversal.sliding:
		return "sliding"
	if body.core.grounded:
		return "crouching" if body.core.crouching else "grounded"
	return "airborne"


# ------------------------------------------------------------------------------------------------ queries

func velocity() -> Vector3:
	return body.core.velocity


func grounded() -> bool:
	return body.core.grounded


func traversing() -> bool:
	return TRAVERSAL_STATES.has(state)


## A capability is available now ("vault", "mantle", "climb", "air_jump", "slide", "flip", ...).
func can(capability: String) -> bool:
	return capabilities.can(capability)


## Effective value of a movement or traversal attribute after every modifier (see movement_attributes.gd).
func attribute(id: String) -> float:
	return capabilities.get_value(id)


## Plain-data state for other systems, recording and multiplayer snapshots.
func snapshot() -> Dictionary:
	return {"version": VERSION, "position": body.global_position, "velocity": body.core.velocity, "state": state,
		"grounded": body.core.grounded, "crouching": body.core.crouching, "capabilities": capabilities.capabilities.keys(),
		"modifiers": capabilities.modifiers.map(func(m) -> String: return m.id)}


# ------------------------------------------------------------------------------------------------ requests

## Adds an equipment / upgrade / spell / injury modifier (MovementModifier). False if one with its id is present.
func add_modifier(modifier) -> bool:
	var added: bool = capabilities.add(modifier)
	traversal.resources.refill()
	return added


func remove_modifier(modifier_id: String) -> bool:
	return capabilities.remove(modifier_id)


## Turns every traversal move on or off (a restriction another system may request); plain movement stays.
func set_traversal_enabled(on: bool) -> void:
	traversal_params.set_value("traversal", 1.0 if on else 0.0)


## Adds a velocity change (knockback, explosion). Refused (false) while a traversal move owns the body.
func apply_impulse(impulse: Vector3) -> bool:
	if traversal.busy():
		return false
	body.core.velocity += impulse
	body.velocity = body.core.velocity
	if impulse.y > 0.0:
		body.core.grounded = false
		body.core.coyote_left = 0.0
	return true


func spawn(at: Transform3D) -> void:
	build()   # no-op once built; lets a caller spawn before the node's _ready has run
	body.spawn_transform = at
	teleport(at.origin, at.basis)


func teleport(position: Vector3, basis := Basis.IDENTITY) -> void:
	body.teleport(position, basis)
	_teleported = true


func respawn() -> void:
	body.respawn()


## Tells the presentation to snap instead of easing on the next present() (after an external move of the body).
func note_teleport() -> void:
	_teleported = true


# ------------------------------------------------------------------------------------------------ presentation and debug

func set_presentation(on: bool) -> void:
	presentation = on
	if visual != null:
		visual.visible = on
		animation.set_enabled(on)


## The biomechanical skeleton view: the real runtime skeleton drawn through the body at 40 % opacity.
func toggle_skeleton_view() -> bool:
	if skeleton_overlay == null:
		skeleton_overlay = SkeletonOverlay.new()
		skeleton_overlay.name = "SkeletonOverlay"
		visual.add_child(skeleton_overlay)
		skeleton_overlay.setup(visual.skeleton, visual.bone_index)
		skeleton_overlay.visible = false
	skeleton_overlay.visible = not skeleton_overlay.visible
	visual.set_body_alpha(SKELETON_VIEW_ALPHA if skeleton_overlay.visible else 1.0)
	return skeleton_overlay.visible


## A traversal debug overlay (interaction regions, contacts, ledge paths) for this character; add it to the scene and
## call its redraw(fraction) each frame while traversal_params "debug_overlay" is on.
func create_debug_overlay() -> Node:
	var overlay = TraversalDebug.new()
	overlay.name = "TraversalDebug"
	overlay.setup(vault, body, traversal)
	overlay.animation = animation
	return overlay
