## Step-response measurements of a spring, used by the tests and the spring diagnostic scene.
extends RefCounted

const Springs = preload("res://animation/springs.gd")
const Math = preload("res://animation/spring_math.gd")


## Simulates a step of height `step` from rest at the given tick rate. Returns
## {overshoot (fraction of the step), peak_time, rise_time (10 -> 90 %), settle_time (stays within `band` of the goal
##  from then on), crossings (times the response crossed the goal), monotonic (never moved away from the goal),
##  max_speed, final_error, regime}. Times are -1.0 when never reached within `duration`.
static func step_response(frequency_hz: float, damping_ratio: float, dt := 0.001, duration := 10.0, step := 1.0, band := 0.02) -> Dictionary:
	var sp := Springs.Scalar.new(frequency_hz, damping_ratio, 0.0)
	sp.set_target(step)
	var peak := 0.0
	var peak_time := 0.0
	var t10 := -1.0
	var t90 := -1.0
	var last_outside := 0.0
	var crossings := 0
	var monotonic := true
	var max_speed := 0.0
	var prev_x := 0.0
	var prev_err := step
	var n := int(round(duration / dt))
	for i in n:
		sp.step(dt)
		var t := float(i + 1) * dt
		if sp.x > peak:
			peak = sp.x
			peak_time = t
		if t10 < 0.0 and sp.x >= 0.1 * step:
			t10 = t
		if t90 < 0.0 and sp.x >= 0.9 * step:
			t90 = t
		var err := step - sp.x
		if absf(err) > band * absf(step):
			last_outside = t
		if err * prev_err < 0.0:
			crossings += 1
		if absf(err) > absf(prev_err) + 1e-12:
			monotonic = false
		max_speed = maxf(max_speed, absf(sp.v))
		prev_x = sp.x
		prev_err = err
	return {
		"overshoot": maxf(0.0, (peak - step) / step),
		"peak_time": peak_time if peak > step else -1.0,
		"rise_time": (t90 - t10) if t10 >= 0.0 and t90 >= 0.0 else -1.0,
		"settle_time": last_outside if absf(step - prev_x) <= band * absf(step) else -1.0,
		"crossings": crossings,
		"monotonic": monotonic,
		"max_speed": max_speed,
		"final_error": absf(step - prev_x),
		"regime": Math.regime_name(damping_ratio),
	}
