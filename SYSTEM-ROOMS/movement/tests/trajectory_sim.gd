## Scripted trajectory used by the determinism test and tools/make_golden.gd (not a test file).
extends RefCounted

const Model = preload("../src/movement_model.gd")
const STEPS := 120
const DT := 1.0 / 60.0


## Integrates a fixed input script on flat ground; returns [px, py, pz, vx, vy, vz] per step.
static func simulate(params: Dictionary) -> Array:
	var pos := Vector3.ZERO
	var vel := Vector3.ZERO
	var out := []
	for i in STEPS:
		var wish := Vector3.ZERO
		if i < 60:
			wish = Vector3(0, 0, -1)
		elif i < 90:
			wish = Vector3(1, 0, -1)
		var jump := i == 30 or i == 95
		vel = Model.step(vel, wish, pos.y <= 0.0, jump, DT, params)
		pos += vel * DT
		if pos.y < 0.0:
			pos.y = 0.0
			vel.y = 0.0
		out.append([pos.x, pos.y, pos.z, vel.x, vel.y, vel.z])
	return out
