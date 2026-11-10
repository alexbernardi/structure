## Character traversal attributes (Movement Lab 5.0): what the body is physically able to do, independent of input
## and of any one move. Every attribute is read by the traversal code; none is a presentation knob. Defaults are the
## baseline human. The movement core's own parameters (speed, acceleration, jump impulse, gravity, air control ...)
## live in movement/movement_params.gd and are upgraded through the same modifier stack (movement_capabilities.gd).
##
## Units: metres, seconds, metres per second; "x" is a dimensionless multiplier; pools are abstract points.
extends RefCounted

const DEFS: Array[Dictionary] = [
	# Vault (running hand-plant over an obstacle; authored SafetyVault)
	{"id": "vault_max_height", "unit": "m", "min": 0.6, "max": 2.5, "default": 1.25,
		"meaning": "Tallest obstacle top above the takeoff ground that can be vaulted"},
	{"id": "vault_max_depth", "unit": "m", "min": 0.1, "max": 2.0, "default": 0.9,
		"meaning": "Thickest obstacle (along travel) that can be cleared in one vault"},
	{"id": "vault_lift", "unit": "m", "min": 0.0, "max": 1.5, "default": 0.3,
		"meaning": "Leg drive: how far the body may be lifted above the authored vault path to clear a top"},
	{"id": "vault_window", "unit": "s", "min": 0.1, "max": 1.0, "default": 0.35,
		"meaning": "Interaction region: Space commits a vault this long (at the approach speed) before the takeoff point"},
	{"id": "vault_late_window", "unit": "m", "min": 0.0, "max": 0.6, "default": 0.2,
		"meaning": "A late press still vaults this far inside the nominal takeoff point, with a shorter, faster stride"},
	{"id": "landing_tolerance", "unit": "m", "min": 0.1, "max": 6.0, "default": 0.6,
		"meaning": "Deepest drop below the takeoff ground a vault or mantle may land into"},
	# Mantle (climb onto a top; authored ClimbUp_1m)
	{"id": "mantle_max_height", "unit": "m", "min": 0.6, "max": 4.0, "default": 1.45,
		"meaning": "Highest top above the feet a grounded mantle reaches"},
	{"id": "grip_reach", "unit": "m", "min": 0.6, "max": 4.0, "default": 2.1,
		"meaning": "Highest top above the feet the hands can catch while airborne (ledge grab)"},
	{"id": "mantle_strength", "unit": "x", "min": 0.3, "max": 3.0, "default": 1.0,
		"meaning": "Climb power: a 1.1 m mantle takes the authored 0.67 s at 1.0; taller climbs take longer"},
	{"id": "mantle_reach", "unit": "m", "min": 0.2, "max": 2.0, "default": 0.8,
		"meaning": "Furthest the face may be (from the body's surface) when a grounded mantle starts"},
	{"id": "mantle_exit_speed", "unit": "m/s", "min": 0.0, "max": 10.0, "default": 2.5,
		"meaning": "Forward speed kept on top after a mantle when moving on"},
	# Momentum and recovery
	{"id": "momentum_conservation", "unit": "x", "min": 0.0, "max": 1.0, "default": 0.6,
		"meaning": "Share of an approach speed above the vault travel speed that survives the landing"},
	{"id": "recovery_time", "unit": "s", "min": 0.0, "max": 1.0, "default": 0.12,
		"meaning": "Time after a vault landing over which speed returns to the planned exit speed"},
	# Air abilities (only used when the capability is granted)
	{"id": "air_jumps", "unit": "count", "min": 0.0, "max": 5.0, "default": 1.0,
		"meaning": "Air jumps per airborne phase when the air_jump capability is granted"},
	{"id": "air_jump_impulse", "unit": "m/s", "min": 0.0, "max": 20.0, "default": 5.0,
		"meaning": "Vertical speed set by an air jump"},
	# Resource pools: capacity, recovery, and per-move costs
	{"id": "stamina_max", "unit": "pt", "min": 0.0, "max": 1000.0, "default": 100.0, "meaning": "Stamina capacity"},
	{"id": "stamina_regen", "unit": "pt/s", "min": 0.0, "max": 200.0, "default": 20.0, "meaning": "Stamina recovered per second on the ground"},
	{"id": "stamina_cost_jump", "unit": "pt", "min": 0.0, "max": 100.0, "default": 4.0, "meaning": "Stamina per jump (a jump is never refused)"},
	{"id": "stamina_cost_vault", "unit": "pt", "min": 0.0, "max": 100.0, "default": 8.0, "meaning": "Stamina per vault"},
	{"id": "stamina_cost_mantle", "unit": "pt", "min": 0.0, "max": 100.0, "default": 15.0, "meaning": "Stamina per mantle"},
	{"id": "energy_max", "unit": "pt", "min": 0.0, "max": 1000.0, "default": 0.0, "meaning": "Battery capacity (cybernetics)"},
	{"id": "energy_regen", "unit": "pt/s", "min": 0.0, "max": 200.0, "default": 0.0, "meaning": "Battery recharge per second"},
	{"id": "energy_cost_assist", "unit": "pt", "min": 0.0, "max": 200.0, "default": 0.0,
		"meaning": "Energy per powered move: a vault or mantle beyond the unaugmented body's limits"},
	{"id": "heat_capacity", "unit": "pt", "min": 0.0, "max": 1000.0, "default": 100.0, "meaning": "Heat at which powered moves are locked out"},
	{"id": "heat_per_assist", "unit": "pt", "min": 0.0, "max": 200.0, "default": 0.0, "meaning": "Heat added per powered move"},
	{"id": "heat_dissipation", "unit": "pt/s", "min": 0.0, "max": 200.0, "default": 10.0, "meaning": "Heat shed per second"},
	{"id": "mana_max", "unit": "pt", "min": 0.0, "max": 1000.0, "default": 0.0, "meaning": "Mana capacity (magic)"},
	{"id": "mana_regen", "unit": "pt/s", "min": 0.0, "max": 200.0, "default": 0.0, "meaning": "Mana recovered per second"},
	{"id": "mana_cost_air_jump", "unit": "pt", "min": 0.0, "max": 200.0, "default": 0.0, "meaning": "Mana per air jump"},
]

## The moves a baseline human has. Modifiers grant or revoke further capabilities (air_jump, powered_traversal ...).
const BASE_CAPABILITIES := ["jump", "vault", "mantle"]

static var _index := {}


static func def(id: String) -> Dictionary:
	if _index.is_empty():
		for d in DEFS:
			_index[d.id] = d
	return _index.get(id, {})


static func defaults() -> Dictionary:
	var out := {}
	for d in DEFS:
		out[d.id] = float(d.default)
	return out


static func check_definitions() -> Array[String]:
	var problems: Array[String] = []
	var seen := {}
	for d in DEFS:
		if seen.has(d.id):
			problems.append("duplicate %s" % d.id)
		seen[d.id] = true
		if not (float(d.min) <= float(d.default) and float(d.default) <= float(d.max)):
			problems.append("%s: default outside range" % d.id)
		if String(d.get("unit", "")) == "" or String(d.get("meaning", "")) == "":
			problems.append("%s: unit and meaning are required" % d.id)
	return problems
