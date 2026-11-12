## Physical body plan: separate from animation bones, complete, mass-consistent, symmetric.
extends RefCounted

const BodyPlan = preload("res://systems/bone_ik/rig/body_plan.gd")
const Humanoid = preload("res://systems/bone_ik/rig/humanoid.gd")


func test_every_animation_bone_has_exactly_one_owner(t) -> void:
	var plan := BodyPlan.load_plan()
	var owner := {}
	for body in plan.bodies:
		var b: Dictionary = plan.bodies[body]
		for bone in [b.driver] + Array(b.followers):
			t.ok(not owner.has(bone), "%s owned once (%s and %s)" % [bone, owner.get(bone, ""), body])
			owner[bone] = body
	for bone in Humanoid.all_bones():
		t.ok(owner.has(bone), "%s rides on a body" % bone)
	t.eq(plan.bodies.size(), 16, "16 bodies for 29 animation bones (no body per animation bone)")


func test_masses(t) -> void:
	var plan := BodyPlan.load_plan()
	var m := BodyPlan.masses(plan, 75.0)
	var total := 0.0
	for k in m:
		total += m[k]
	t.near(total, 75.0, 1e-6, "segment masses sum to the body mass (de Leva fractions sum to 100 %)")
	t.near(m.thigh_l, m.thigh_r, 1e-9, "symmetric")
	var armoured := BodyPlan.masses(plan, 75.0, {"thorax": 12.0, "head": 2.5})
	t.near(armoured.thorax - m.thorax, 12.0, 1e-9, "armour adds mass per body without a new skeleton")
