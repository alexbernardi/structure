## Physical body plan (data/body_plan.json): which animation bones get a rigid body in phase 3, their masses, and
## which bones only ride along. Pure data in phase 1; the physics adapter will build PhysicalBone3D nodes from it.
extends RefCounted

const DATA_PATH := "res://systems/bone_ik/data/body_plan.json"


static func load_plan(path := DATA_PATH) -> Dictionary:
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY or not data.has("bodies"):
		push_error("body plan %s is not valid JSON" % path)
		return {}
	return data


## Body masses in kg for a total body mass (proportions' `body_mass`), plus optional extra mass per body (armour).
static func masses(plan: Dictionary, body_mass: float, extra := {}) -> Dictionary:
	var out := {}
	for name in plan.bodies:
		out[name] = body_mass * float(plan.bodies[name].mass_pct) / 100.0 + float(extra.get(name, 0.0))
	return out
