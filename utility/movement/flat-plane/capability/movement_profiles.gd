## Example progression content on the one shared traversal architecture: the baseline human is the attribute
## defaults; these modifiers demonstrate a permanent cybernetic upgrade, a temporary magical effect and an injury.
## Every number here changes what is feasible or how it executes (heights, reach, impulse, gravity, costs), not how
## fast an animation plays.
extends RefCounted

const Modifier = preload("res://capability/movement_modifier.gd")

const CYBERNETIC := "kinetic_legs"
const MAGIC := "zephyr_step"
const INJURY := "sprained_ankle"
const MAGIC_DURATION := 25.0


## Stage 2: powered leg actuators. Stronger, faster, higher; moves beyond the unaugmented limits cost battery energy
## and generate heat, so chaining powered moves is a skill (heat management) rather than free.
static func cybernetic_legs():
	return Modifier.make(CYBERNETIC, "Kinetic leg actuators Mk1", "cybernetic", [
		["max_ground_speed", "add", 1.0],
		["ground_accel", "mul", 1.3],
		["jump_impulse", "mul", 1.25],
		["vault_max_height", "add", 0.45],
		["vault_lift", "add", 0.55],
		["vault_max_depth", "add", 0.3],
		["mantle_max_height", "add", 0.75],
		["grip_reach", "add", 0.6],
		["catch_distance", "add", 0.25],
		["grip_strength", "add", 5.0],
		["mantle_strength", "mul", 1.4],
		["mantle_exit_speed", "add", 1.5],
		["momentum_conservation", "add", 0.2],
		["landing_tolerance", "add", 1.5],
		["energy_max", "add", 100.0],
		["energy_regen", "add", 6.0],
		["energy_cost_assist", "add", 20.0],
		["heat_per_assist", "add", 35.0],
	], ["powered_traversal"])


## Stage 3: a temporary spell. Lighter body and a mana-fuelled air jump: reaching places by timing two jumps.
static func zephyr_step():
	return Modifier.make(MAGIC, "Zephyr step (spell)", "magic", [
		["gravity", "mul", 0.65],
		["air_control", "add", 0.35],
		["air_speed_cap", "add", 1.0],
		["landing_tolerance", "add", 1.0],
		["grip_reach", "add", 0.3],
		["mana_max", "add", 60.0],
		["mana_regen", "add", 3.0],
		["mana_cost_air_jump", "add", 15.0],
	], ["air_jump"], MAGIC_DURATION)


## An impairment, to show modifiers that cap and revoke: slower, weaker jump, no vaulting until it heals.
static func sprained_ankle():
	return Modifier.make(INJURY, "Sprained ankle", "injury", [
		["max_ground_speed", "cap", 4.0],
		["sprint_multiplier", "cap", 1.2],
		["jump_impulse", "mul", 0.8],
		["mantle_strength", "mul", 0.7],
	], [], INF, ["vault"])
