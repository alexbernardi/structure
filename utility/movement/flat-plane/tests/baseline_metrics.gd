## Baseline movement behaviour of the original (Stage I) controller, measured on a flat floor with the core alone.
## Phase 0 of Movement Lab 2.0 records these numbers; later phases must keep them when their feature flags are off.
## Pure measurement code: used by tests/test_baseline_behavior.gd and tools/audit_baseline.gd.
extends RefCounted

const Core = preload("res://movement/movement_core.gd")


## One flat-floor simulation. Returns {pos, core} after `seconds`. `script` is a Callable(tick, core) -> input dict.
static func simulate(seconds: float, hz: int, script: Callable, start_velocity := Vector3.ZERO, params := {}) -> Dictionary:
	var core: Core = Core.new()
	for k in params:
		core.p[k] = params[k]
	core.velocity = start_velocity
	core.grounded = true
	var pos := Vector3.ZERO
	var dt := 1.0 / float(hz)
	var trace: Array[Dictionary] = []
	for i in int(round(seconds * hz)):
		var on_floor := pos.y <= 0.0001 and core.velocity.y <= 0.0
		core.step(script.call(i, core), {"grounded": on_floor, "normal": Vector3.UP, "can_stand": true}, dt)
		pos += core.velocity * dt
		if pos.y < 0.0:
			pos.y = 0.0
		trace.append({"t": float(i + 1) * dt, "speed": core.horizontal_speed(), "vz": core.velocity.z, "pos": pos, "vy": core.velocity.y, "grounded": core.grounded})
	return {"pos": pos, "core": core, "trace": trace}


static func _input(move := Vector2.ZERO, extra := {}) -> Dictionary:
	var d := {"move": move, "yaw": 0.0, "jump_pressed": false, "jump_held": false, "sprint": false, "crouch": false}
	d.merge(extra, true)
	return d


## All baseline numbers at one physics rate.
static func measure(hz: int) -> Dictionary:
	var fwd := Vector2(0, 1)
	var out := {"hz": hz}
	var run_time := 2.0

	var accel := simulate(run_time, hz, func(_i: int, _c: Core) -> Dictionary: return _input(fwd))
	out["max_speed"] = accel.core.horizontal_speed()
	out["time_to_95pct_s"] = _first_time(accel.trace, func(r: Dictionary) -> bool: return r.speed >= 0.95 * out.max_speed)
	out["speed_at_0_1s"] = _at(accel.trace, 0.1).speed
	out["distance_2s_m"] = -accel.pos.z

	var sprint := simulate(run_time, hz, func(_i: int, _c: Core) -> Dictionary: return _input(fwd, {"sprint": true}))
	out["sprint_speed"] = sprint.core.horizontal_speed()
	var crouch := simulate(run_time, hz, func(_i: int, _c: Core) -> Dictionary: return _input(fwd, {"crouch": true}))
	out["crouch_speed"] = crouch.core.horizontal_speed()

	var stop := simulate(2.0, hz, func(_i: int, _c: Core) -> Dictionary: return _input(), Vector3(0, 0, -out.max_speed))
	out["stop_time_s"] = _first_time(stop.trace, func(r: Dictionary) -> bool: return r.speed <= 0.05)
	out["stop_distance_m"] = -_at(stop.trace, out.stop_time_s).pos.z

	var reverse := simulate(2.0, hz, func(_i: int, _c: Core) -> Dictionary: return _input(Vector2(0, -1)), Vector3(0, 0, -out.max_speed))
	out["reverse_zero_cross_s"] = _first_time(reverse.trace, func(r: Dictionary) -> bool: return r.vz >= 0.0)
	out["reverse_to_95pct_s"] = _first_time(reverse.trace, func(r: Dictionary) -> bool: return r.vz >= 0.95 * out.max_speed)

	var turn := simulate(1.0, hz, func(_i: int, _c: Core) -> Dictionary: return _input(Vector2(1, 0)), Vector3(0, 0, -out.max_speed))
	var min_speed := 99.0
	for r in turn.trace:
		min_speed = minf(min_speed, r.speed)
	out["turn90_min_speed"] = min_speed
	out["turn90_recover_95pct_s"] = _first_time(turn.trace, func(r: Dictionary) -> bool: return r.t > 0.05 and r.speed >= 0.95 * out.max_speed)

	var jump := simulate(2.0, hz, func(i: int, _c: Core) -> Dictionary: return _input(Vector2.ZERO, {"jump_pressed": i == 0}))
	var apex := 0.0
	var air_time := 0.0
	for r in jump.trace:
		apex = maxf(apex, r.pos.y)
		if not r.grounded or r.vy > 0.0 or r.pos.y > 0.001:
			air_time = r.t
	out["jump_apex_m"] = apex
	out["jump_air_time_s"] = air_time

	var hop := simulate(1.5, hz, func(i: int, _c: Core) -> Dictionary: return _input(fwd, {"jump_pressed": i == 0, "jump_held": false}), Vector3(0, 0, -out.max_speed))
	var landing_speed := 0.0
	var seen_air := false
	for r in hop.trace:
		if not r.grounded:
			seen_air = true
		elif seen_air:
			landing_speed = r.speed
			break
	out["jump_momentum_kept_pct"] = 100.0 * landing_speed / out.max_speed
	return out


static func _at(trace: Array[Dictionary], t: float) -> Dictionary:
	for r in trace:
		if r.t >= t - 1e-9:
			return r
	return trace[trace.size() - 1]


static func _first_time(trace: Array[Dictionary], pred: Callable) -> float:
	for r in trace:
		if pred.call(r):
			return r.t
	return -1.0
