extends RefCounted

const Metrics = preload("res://tests/baseline_metrics.gd")

## Stage I controller, remeasured for the requested 6 m/s run and 2x sprint defaults in task 0004.
## If a later phase changes these on purpose, change them HERE in the same commit and say why in the task note.
const BASELINE_120 := {
	"max_speed": 6.0, "sprint_speed": 12.0, "crouch_speed": 2.0,
	"time_to_95pct_s": 0.1333, "speed_at_0_1s": 4.5, "distance_2s_m": 11.6250,
	"stop_time_s": 0.1583, "stop_distance_m": 0.3578,
	"reverse_zero_cross_s": 0.075, "reverse_to_95pct_s": 0.2,
	"turn90_min_speed": 4.7339, "turn90_recover_95pct_s": 0.1167,
	"jump_apex_m": 0.7489, "jump_air_time_s": 0.5583, "jump_momentum_kept_pct": 100.0,
}

## Documented tick-rate dependence of the Stage I controller (explicit Euler friction/gravity): 60 Hz must stay within
## these of 120 Hz. Measured in Phase 0: stop distance 10.8 % apart, stop time 6.7 %, jump apex 3.0 %, 2 s distance 0.2 %.
const TOLERANCE_60_VS_120 := {
	"max_speed": 0.001, "sprint_speed": 0.001, "crouch_speed": 0.001, "time_to_95pct_s": 0.02, "speed_at_0_1s": 0.001,
	"distance_2s_m": 0.05, "stop_time_s": 0.08, "stop_distance_m": 0.12, "reverse_to_95pct_s": 0.02, "turn90_min_speed": 0.02,
	"turn90_recover_95pct_s": 0.02, "jump_apex_m": 0.04, "jump_air_time_s": 0.02, "jump_momentum_kept_pct": 0.5,
}


func test_stage_one_controller_matches_the_recorded_baseline(t) -> void:
	var m := Metrics.measure(120)
	for k in BASELINE_120:
		t.near(m[k], BASELINE_120[k], maxf(0.0005, absf(BASELINE_120[k]) * 0.002), "baseline %s" % k)


func test_baseline_is_deterministic(t) -> void:
	t.eq(Metrics.measure(120), Metrics.measure(120), "two runs are bit-identical")


func test_physical_sanity_of_the_baseline(t) -> void:
	var m := Metrics.measure(120)
	t.near(m.jump_apex_m, 5.5 * 5.5 / (2.0 * 19.6), 0.03, "apex is close to v^2/2g")
	t.ok(m.reverse_zero_cross_s < m.reverse_to_95pct_s, "reversing passes through zero before reaching speed the other way")
	t.ok(m.stop_distance_m < 0.5 and m.stop_time_s < 0.3, "a human-scale stop (%.2f m in %.2f s)" % [m.stop_distance_m, m.stop_time_s])
	t.ok(m.turn90_min_speed > 0.0 and m.turn90_min_speed < m.max_speed, "a 90 degree turn costs some speed but does not stop")


func test_sixty_hertz_stays_within_documented_tolerance_of_120(t) -> void:
	var a := Metrics.measure(120)
	var b := Metrics.measure(60)
	for k in TOLERANCE_60_VS_120:
		var rel := absf(b[k] - a[k]) / maxf(absf(a[k]), 0.01)
		t.ok(rel <= TOLERANCE_60_VS_120[k], "%s: 60 Hz %.4f vs 120 Hz %.4f (%.1f%% apart, allowed %.1f%%)" % [k, b[k], a[k], rel * 100.0, TOLERANCE_60_VS_120[k] * 100.0])


func test_the_known_tick_rate_dependence_is_real_and_bounded(t) -> void:
	# Documents the limitation instead of hiding it: jump height and stop distance move a few percent with the tick rate.
	var a := Metrics.measure(120)
	var b := Metrics.measure(60)
	t.ok(absf(b.jump_apex_m - a.jump_apex_m) > 0.005, "apex differs between rates (explicit Euler): %.4f vs %.4f" % [b.jump_apex_m, a.jump_apex_m])
	t.ok(absf(b.stop_distance_m - a.stop_distance_m) > 0.005, "stop distance differs: %.4f vs %.4f" % [b.stop_distance_m, a.stop_distance_m])
