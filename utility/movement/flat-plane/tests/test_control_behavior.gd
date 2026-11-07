extends RefCounted

const B = preload("res://midi/control_behavior.gd")
const Replay = preload("res://tests/capture_replay.gd")


func _ramp(from: int, to: int, step: int) -> Array:
	var out := []
	var v := from
	while v <= to:
		out.append(v)
		v += step
	return out


func test_real_fader_capture_is_absolute(t) -> void:
	var a := B.analyze(Replay.values_of("pb:0:0"), 16383)
	t.eq(a.behavior, B.ABSOLUTE, "pitch-bend fader")
	t.eq(a["min"], 0, "sweep starts at 0")
	t.eq(a["max"], 16256, "full travel reaches 16256 (7 effective bits)")
	t.eq(a.step, 128, "low byte is always 0")


func test_real_knob_capture_is_relative(t) -> void:
	var a := B.analyze(Replay.values_of("cc:0:16"), 127)
	t.eq(a.behavior, B.RELATIVE, "CC16 stream is relative")
	t.ok(a.repeat_ratio > 0.8, "values repeat (1 1 1 ... / 65 65 ...)")


func test_synthetic_absolute_streams(t) -> void:
	t.eq(B.analyze(_ramp(0, 127, 3)).behavior, B.ABSOLUTE, "slow rising ramp")
	var up_down := _ramp(0, 127, 9)
	up_down.append_array(_ramp(0, 118, 9).map(func(v: int) -> int: return 118 - v))
	t.eq(B.analyze(up_down).behavior, B.ABSOLUTE, "up then down")
	t.eq(B.analyze([10, 14, 20, 29, 41, 56, 74, 95]).behavior, B.ABSOLUTE, "accelerating sweep")


func test_synthetic_relative_streams(t) -> void:
	t.eq(B.analyze([1, 1, 1, 1, 1, 1]).behavior, B.RELATIVE, "constant +1")
	t.eq(B.analyze([127, 127, 127, 127, 127]).behavior, B.RELATIVE, "constant -1 (twos complement)")
	t.eq(B.analyze([65, 65, 65, 65, 66, 65]).behavior, B.RELATIVE, "sign-magnitude with slight acceleration")


func test_too_few_samples_is_unknown(t) -> void:
	t.eq(B.analyze([1, 1, 1]).behavior, B.UNKNOWN, "3 samples")
	t.eq(B.analyze([]).behavior, B.UNKNOWN, "empty")


func test_force_decision_on_ambiguous_stream(t) -> void:
	var a := B.analyze([3, 3, 90, 5, 3, 100, 4, 99])
	t.eq(a.behavior, B.UNKNOWN, "jumpy stream stays ambiguous")
	t.ok([B.ABSOLUTE, B.RELATIVE].has(B.force_decision(a)), "forced to one of the two")


func test_infer_sign_magnitude_both_orientations(t) -> void:
	var r := B.infer_relative([1, 1, 2], [65, 65])
	t.eq([r.encoding, r.invert], [B.ENC_SIGN_MAGNITUDE, false], "cw=1, ccw=65")
	var r2 := B.infer_relative([65, 65], [1, 1])
	t.eq([r2.encoding, r2.invert], [B.ENC_SIGN_MAGNITUDE, true], "cw=65, ccw=1 is inverted sign-magnitude")


func test_infer_twos_complement_and_offset(t) -> void:
	var r := B.infer_relative([1], [127])
	t.eq(r.encoding, B.ENC_TWOS_COMPLEMENT, "cw=1, ccw=127")
	var r2 := B.infer_relative([65], [63])
	t.eq([r2.encoding, r2.invert], [B.ENC_BINARY_OFFSET, false], "cw=65, ccw=63")


func test_infer_fixed_and_errors(t) -> void:
	var r := B.infer_relative([127], [0])
	t.ok(r.ok, "unusual pair still maps")
	var bad := B.infer_relative([1], [1])
	t.ok(not bad.ok, "same value both ways is rejected")
	t.ok(bad.reason != "", "with a reason")
	t.ok(not B.infer_relative([], [1]).ok, "missing direction")


func test_decode_relative(t) -> void:
	var sm := {"encoding": B.ENC_SIGN_MAGNITUDE, "invert": false}
	t.eq(B.decode_relative(1, sm), 1, "+1")
	t.eq(B.decode_relative(65, sm), -1, "-1")
	t.eq(B.decode_relative(3, sm), 3, "+3 (fast)")
	t.eq(B.decode_relative(67, sm), -3, "-3 (fast)")
	t.eq(B.decode_relative(64, sm), 0, "64 is no movement")
	sm.invert = true
	t.eq(B.decode_relative(1, sm), -1, "invert flips")
	var tc := {"encoding": B.ENC_TWOS_COMPLEMENT}
	t.eq(B.decode_relative(127, tc), -1, "twos -1")
	var off := {"encoding": B.ENC_BINARY_OFFSET}
	t.eq([B.decode_relative(65, off), B.decode_relative(63, off)], [1, -1], "offset +-1")
	var fx := {"encoding": B.ENC_FIXED, "cw_values": [100], "ccw_values": [28]}
	t.eq([B.decode_relative(100, fx), B.decode_relative(28, fx), B.decode_relative(50, fx)], [1, -1, 0], "fixed lists")


func test_normalize_absolute(t) -> void:
	var m := {"raw_min": 0, "raw_max": 16256, "invert": false}
	t.near(B.normalize_absolute(0, m), 0.0, 0.0001, "bottom")
	t.near(B.normalize_absolute(16256, m), 1.0, 0.0001, "top reaches exactly 1.0")
	t.near(B.normalize_absolute(8128, m), 0.5, 0.0001, "middle")
	t.near(B.normalize_absolute(20000, m), 1.0, 0.0001, "clamped above")
	m.invert = true
	t.near(B.normalize_absolute(0, m), 1.0, 0.0001, "inverted")
