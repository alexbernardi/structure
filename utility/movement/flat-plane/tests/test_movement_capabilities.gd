## Movement Lab 5.0 capability layer: attribute definitions, the modifier op order, removal back to the exact baseline,
## timed expiry, capability grants/revokes, resources, and that the movement core sees upgrades without the tuned
## baseline ever being written.
extends RefCounted

const Attributes = preload("res://capability/movement_attributes.gd")
const Modifier = preload("res://capability/movement_modifier.gd")
const Capabilities = preload("res://capability/movement_capabilities.gd")
const Resources = preload("res://capability/movement_resources.gd")
const Profiles = preload("res://capability/movement_profiles.gd")
const Params = preload("res://movement/movement_params.gd")
const TraversalParams = preload("res://traversal/traversal_params.gd")


func _caps():
	var caps = Capabilities.new()
	caps.setup(Params.new(), TraversalParams.create())
	return caps


func test_attribute_definitions_have_units_meanings_and_legal_defaults(t) -> void:
	t.eq(Attributes.check_definitions(), [] as Array[String], "attribute definitions are consistent")
	for d in Attributes.DEFS:
		t.ok(String(d.meaning).length() > 15, "%s explains what it does" % d.id)
	for m in [Profiles.cybernetic_legs(), Profiles.zephyr_step(), Profiles.sprained_ankle()]:
		t.eq(m.check(), [] as Array[String], "%s is a valid modifier" % m.id)
		for e in m.effects:
			t.ok(not Params.def(e.stat).is_empty() or not Attributes.def(e.stat).is_empty(), "%s targets a real attribute (%s)" % [m.id, e.stat])


func test_no_modifiers_leaves_every_value_bit_identical_to_its_baseline(t) -> void:
	var caps = _caps()
	for id in Params.ids():
		t.eq(caps.core[id], caps.params.get_value(id), "core %s equals the tuned value" % id)
	for d in Attributes.DEFS:
		t.eq(caps.values[d.id], caps.base_value(d.id), "%s equals its baseline" % d.id)
	t.eq(caps.base_value("vault_window"), caps.traversal_params.get_value("anticipation"), "the vault window's baseline is the tuned anticipation control")
	t.ok(caps.can("vault") and caps.can("mantle") and caps.can("jump") and not caps.can("air_jump"), "a human vaults, mantles and jumps")


func test_ops_combine_in_a_fixed_order_independent_of_insertion(t) -> void:
	var a = Modifier.make("a", "", "training", [["max_ground_speed", "add", 1.0], ["jump_impulse", "mul", 1.2]])
	var b = Modifier.make("b", "", "equipment", [["max_ground_speed", "mul", 1.5], ["jump_impulse", "add", 0.5]])
	var c = Modifier.make("c", "", "debuff", [["max_ground_speed", "cap", 8.0]])
	var results := []
	for order in [[a, b, c], [c, b, a], [b, c, a]]:
		var caps = _caps()
		for m in order:
			caps.add(m)
		results.append([caps.get_value("max_ground_speed"), caps.get_value("jump_impulse")])
	t.eq(results[0], results[1], "insertion order does not matter")
	t.eq(results[0], results[2], "insertion order does not matter (again)")
	t.near(results[0][0], minf((6.0 + 1.0) * 1.5, 8.0), 1e-6, "(base + adds) x muls, then caps")
	t.near(results[0][1], (5.5 + 0.5) * 1.2, 1e-6, "adds before multipliers")
	var caps = _caps()
	caps.add(Modifier.make("low", "", "magic", [["gravity", "set", 5.0]], [], INF, [], 0))
	caps.add(Modifier.make("high", "", "magic", [["gravity", "set", 2.0]], [], INF, [], 3))
	t.near(caps.get_value("gravity"), 2.0, 1e-6, "the highest priority override wins")
	caps.add(Modifier.make("wild", "", "buff", [["gravity", "mul", 1000.0]]))
	caps.remove("high")
	caps.remove("low")
	t.near(caps.get_value("gravity"), 60.0, 1e-6, "results stay inside the parameter's legal range")


func test_removal_restores_the_exact_baseline_and_never_writes_it(t) -> void:
	var caps = _caps()
	var tuned: Dictionary = caps.params.values.duplicate()
	var before: Dictionary = caps.core.duplicate()
	var attributes: Dictionary = caps.values.duplicate()
	caps.add(Profiles.cybernetic_legs())
	caps.add(Profiles.zephyr_step())
	caps.add(Profiles.sprained_ankle())
	t.ok(caps.get_value("gravity") < before.gravity and caps.get_value("vault_max_height") > attributes.vault_max_height, "modifiers took effect")
	t.eq(caps.params.values, tuned, "the tuned movement parameters are never written")
	caps.remove(Profiles.CYBERNETIC)
	caps.remove(Profiles.INJURY)
	caps.remove(Profiles.MAGIC)
	t.eq(caps.core, before, "removing every modifier restores the core parameters bit for bit")
	t.eq(caps.values, attributes, "and every traversal attribute")
	caps.add(Profiles.cybernetic_legs())
	caps.add(Profiles.cybernetic_legs())
	t.eq(caps.modifiers.size(), 1, "re-adding a modifier replaces it instead of stacking it")
	t.eq(caps.remove_source("cybernetic"), 1, "modifiers can be removed by source")
	t.eq(caps.core, before, "back to baseline")
	caps.params.set_value("max_ground_speed", 7.0)
	caps.add(Profiles.cybernetic_legs())
	t.near(caps.core.max_ground_speed, 8.0, 1e-6, "live tuning of the baseline composes with modifiers")


func test_timed_modifiers_expire_on_the_fixed_tick(t) -> void:
	var caps = _caps()
	caps.add(Profiles.zephyr_step())
	t.ok(caps.can("air_jump"), "the spell grants an air jump")
	var ticks := 0
	while caps.has(Profiles.MAGIC) and ticks < 100000:
		caps.tick(1.0 / 120.0)
		ticks += 1
	t.eq(ticks, int(ceil(Profiles.MAGIC_DURATION * 120.0)), "expires after its duration in ticks (%d)" % ticks)
	t.ok(not caps.can("air_jump"), "and its capability goes with it")
	caps.add(Profiles.sprained_ankle())
	caps.add(Modifier.make("haste", "", "buff", [], ["vault"]))
	t.ok(not caps.can("vault"), "a revoke wins over a grant")


func test_resources_gate_moves_and_recover(t) -> void:
	var caps = _caps()
	var pools = Resources.new()
	pools.setup(caps)
	t.eq(pools.refusal({"stamina": 10.0}), "", "a rested human can pay for a vault")
	t.eq(pools.refusal({"energy": 1.0}), "no_energy", "a human has no battery")
	t.eq(pools.refusal({"mana": 1.0}), "no_mana", "or mana")
	pools.spend({"stamina": 95.0})
	t.eq(pools.refusal({"stamina": 8.0}), "exhausted", "exhaustion refuses costly moves")
	for i in 60:
		pools.tick(1.0 / 120.0, false)
	t.near(pools.level.stamina, 5.0, 1e-6, "no stamina recovery in the air")
	for i in 120:
		pools.tick(1.0 / 120.0, true)
	t.near(pools.level.stamina, 25.0, 1e-4, "recovers on the ground at stamina_regen")
	caps.add(Profiles.cybernetic_legs())
	pools.refill()
	for i in 3:
		t.eq(pools.refusal({"energy": 20.0, "heat": 35.0}), "", "powered move %d allowed" % i)
		pools.spend({"energy": 20.0, "heat": 35.0})
	t.ok(pools.overheated, "three quick powered moves overheat the actuators")
	t.eq(pools.refusal({"energy": 20.0, "heat": 35.0}), "overheated", "and lock out the next one")
	var seconds := 0.0
	while pools.overheated:
		pools.tick(1.0 / 120.0, true)
		seconds += 1.0 / 120.0
	t.near(seconds, 5.5, 0.05, "until heat dissipates below half capacity (%.2f s)" % seconds)
	caps.remove(Profiles.CYBERNETIC)
	pools.tick(1.0 / 120.0, true)
	t.eq(pools.level.energy, 0.0, "removing the battery empties the pool")
