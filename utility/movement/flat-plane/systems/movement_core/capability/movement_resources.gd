## Resource pools that traversal moves draw on: stamina (body), energy and heat (cybernetics), mana (magic).
## Capacities and rates come from the effective attributes, so upgrades change them. Fixed-tick, deterministic.
## Heat is a lockout rather than a cost: at capacity powered moves are refused until it has dropped below half.
extends RefCounted

const POOLS := ["stamina", "energy", "heat", "mana"]

var capabilities                       ## MovementCapabilities
var level := {"stamina": 100.0, "energy": 0.0, "heat": 0.0, "mana": 0.0}
var overheated := false
var spent := {"stamina": 0.0, "energy": 0.0, "heat": 0.0, "mana": 0.0}   ## lifetime totals (telemetry, tests)


func setup(movement_capabilities) -> void:
	capabilities = movement_capabilities
	refill()


func capacity(pool: String) -> float:
	if pool == "heat":
		return capabilities.get_value("heat_capacity")
	return capabilities.get_value(pool + "_max")


func refill() -> void:
	for pool in ["stamina", "energy", "mana"]:
		level[pool] = capacity(pool)
	level.heat = 0.0
	overheated = false


func tick(dt: float, grounded: bool) -> void:
	if grounded:
		level.stamina = minf(capacity("stamina"), level.stamina + capabilities.get_value("stamina_regen") * dt)
	level.energy = minf(capacity("energy"), level.energy + capabilities.get_value("energy_regen") * dt)
	level.mana = minf(capacity("mana"), level.mana + capabilities.get_value("mana_regen") * dt)
	level.heat = maxf(0.0, level.heat - capabilities.get_value("heat_dissipation") * dt)
	# A lost upgrade can leave more in a pool than it now holds.
	for pool in ["stamina", "energy", "mana"]:
		level[pool] = minf(level[pool], capacity(pool))
	if overheated and level.heat < capacity("heat") * 0.5:
		overheated = false


## "" when `cost` ({pool: points}) can be paid, otherwise the refusal reason.
func refusal(cost: Dictionary) -> String:
	if cost.get("stamina", 0.0) > level.stamina + 1e-6:
		return "exhausted"
	if cost.get("energy", 0.0) > level.energy + 1e-6:
		return "no_energy"
	if cost.get("heat", 0.0) > 0.0 and (overheated or capacity("heat") <= 0.0):
		return "overheated"
	if cost.get("mana", 0.0) > level.mana + 1e-6:
		return "no_mana"
	return ""


func spend(cost: Dictionary) -> void:
	for pool in ["stamina", "energy", "mana"]:
		var amount := minf(float(cost.get(pool, 0.0)), level[pool])
		level[pool] -= amount
		spent[pool] += amount
	var heat := float(cost.get("heat", 0.0))
	if heat > 0.0:
		level.heat += heat
		spent.heat += heat
		if level.heat >= capacity("heat"):
			overheated = true


func describe() -> String:
	var parts: Array[String] = ["stamina %.0f/%.0f" % [level.stamina, capacity("stamina")]]
	if capacity("energy") > 0.0:
		parts.append("energy %.0f/%.0f" % [level.energy, capacity("energy")])
		parts.append("heat %.0f/%.0f%s" % [level.heat, capacity("heat"), " OVERHEATED" if overheated else ""])
	if capacity("mana") > 0.0:
		parts.append("mana %.0f/%.0f" % [level.mana, capacity("mana")])
	return "  ".join(parts)
