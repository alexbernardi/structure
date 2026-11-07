## Decides how a physical control behaves from the messages it sends, and decodes those messages.
## Absolute: the value is a position. Relative: each message is a step (endless encoders).
## Pure functions, unit-tested with synthetic streams and a real SMC-Mixer capture.
extends RefCounted

const ABSOLUTE := "absolute"
const RELATIVE := "relative"
const UNKNOWN := "unknown"

const ENC_SIGN_MAGNITUDE := "sign_magnitude"   # 1..63 = +n, 65..127 = -(n-64)   (Mackie V-Pot)
const ENC_TWOS_COMPLEMENT := "twos_complement" # 1..63 = +n, 65..127 = -(128-n)
const ENC_BINARY_OFFSET := "binary_offset"     # 64 = 0, above = +, below = -
const ENC_FIXED := "fixed"                     # explicit value lists, every message is one step
const ENCODINGS := [ENC_SIGN_MAGNITUDE, ENC_TWOS_COMPLEMENT, ENC_BINARY_OFFSET, ENC_FIXED]

const MIN_SAMPLES := 4


## Classifies a stream of raw values from ONE signature. `domain_max` is 127 (7-bit) or 16383 (pitch bend).
## Returns {behavior, confidence 0..1, n, distinct, repeat_ratio, jump_ratio, reversal_ratio, min, max, step}.
static func analyze(values: Array, domain_max := 127) -> Dictionary:
	var n := values.size()
	var out := {"behavior": UNKNOWN, "confidence": 0.0, "n": n, "distinct": 0, "repeat_ratio": 0.0,
		"jump_ratio": 0.0, "reversal_ratio": 0.0, "min": 0, "max": 0, "step": 1}
	if n == 0:
		return out
	var seen := {}
	var vmin: int = values[0]
	var vmax: int = values[0]
	var g := 0
	for v in values:
		seen[v] = true
		vmin = mini(vmin, v)
		vmax = maxi(vmax, v)
		g = _gcd(g, int(v))
	out.distinct = seen.size()
	out.min = vmin
	out.max = vmax
	out.step = maxi(1, g)
	if n < MIN_SAMPLES:
		return out
	var repeats := 0
	var jumps := 0
	var reversals := 0
	var moves := 0
	var prev_sign := 0
	for i in range(1, n):
		var d: int = values[i] - values[i - 1]
		if d == 0:
			repeats += 1
			continue
		if absi(d) > domain_max / 4:
			jumps += 1
		var s := 1 if d > 0 else -1
		if prev_sign != 0 and s != prev_sign:
			reversals += 1
		prev_sign = s
		moves += 1
	out.repeat_ratio = float(repeats) / float(n - 1)
	out.jump_ratio = float(jumps) / float(n - 1)
	out.reversal_ratio = float(reversals) / maxf(1.0, float(moves))
	if out.repeat_ratio >= 0.4:
		out.behavior = RELATIVE
		out.confidence = minf(1.0, out.repeat_ratio + 0.2)
	elif out.distinct >= MIN_SAMPLES and out.jump_ratio <= 0.15 and out.reversal_ratio <= 0.25:
		out.behavior = ABSOLUTE
		out.confidence = minf(1.0, 1.0 - out.reversal_ratio - out.jump_ratio)
	return out


## Last-resort decision for a stream that stayed ambiguous after many samples.
static func force_decision(analysis: Dictionary) -> String:
	if analysis.behavior != UNKNOWN:
		return analysis.behavior
	return RELATIVE if analysis.repeat_ratio >= 0.25 else ABSOLUTE


static func _gcd(a: int, b: int) -> int:
	a = absi(a)
	b = absi(b)
	while b != 0:
		var t := b
		b = a % b
		a = t
	return a


## Signed step of one raw value under an encoding (positive = the encoding's "increase" direction).
static func decode_encoding(raw: int, encoding: String) -> int:
	match encoding:
		ENC_SIGN_MAGNITUDE:
			if raw >= 1 and raw <= 63:
				return raw
			if raw >= 65 and raw <= 127:
				return -(raw - 64)
			return 0
		ENC_TWOS_COMPLEMENT:
			if raw >= 1 and raw <= 63:
				return raw
			if raw >= 65 and raw <= 127:
				return -(128 - raw)
			return 0
		ENC_BINARY_OFFSET:
			return raw - 64
	return 0


## Works out the relative encoding from the values seen turning clockwise and counter-clockwise.
## Returns {ok, encoding, invert, cw_values, ccw_values, reason}. Among the encodings that explain both
## directions, the one with the smallest per-message step wins (slow turns are single steps).
static func infer_relative(cw: Array, ccw: Array) -> Dictionary:
	var cw_set := _unique(cw)
	var ccw_set := _unique(ccw)
	var out := {"ok": false, "encoding": ENC_FIXED, "invert": false, "cw_values": cw_set, "ccw_values": ccw_set, "reason": ""}
	if cw_set.is_empty() or ccw_set.is_empty():
		out.reason = "need values from both turning directions"
		return out
	for v in cw_set:
		if ccw_set.has(v):
			out.reason = "both directions sent the same value (%d); turn only in the requested direction" % v
			return out
	var best_score := 1 << 30
	for enc in [ENC_SIGN_MAGNITUDE, ENC_TWOS_COMPLEMENT, ENC_BINARY_OFFSET]:
		for inv in [false, true]:
			var cw_min := _min_magnitude(cw_set, enc, inv, 1)
			var ccw_min := _min_magnitude(ccw_set, enc, inv, -1)
			if cw_min < 0 or ccw_min < 0:
				continue
			var score := maxi(cw_min, ccw_min)
			if score < best_score:
				best_score = score
				out.encoding = enc
				out.invert = inv
				out.ok = true
	if not out.ok:
		out.encoding = ENC_FIXED
		out.ok = true
	return out


## Smallest |step| over `vals` if every value decodes with the wanted sign, else -1.
static func _min_magnitude(vals: Array, enc: String, invert: bool, want_sign: int) -> int:
	var smallest := 1 << 30
	for v in vals:
		var s := decode_encoding(int(v), enc)
		if invert:
			s = -s
		if s == 0 or (s > 0) != (want_sign > 0):
			return -1
		smallest = mini(smallest, absi(s))
	return smallest


static func _unique(values: Array) -> Array:
	var seen := {}
	var out := []
	for v in values:
		if not seen.has(v):
			seen[v] = true
			out.append(int(v))
	out.sort()
	return out


## Signed step count for one message of a relative mapping (positive = clockwise / "up").
static func decode_relative(raw: int, mapping: Dictionary) -> int:
	var enc: String = mapping.get("encoding", ENC_SIGN_MAGNITUDE)
	var steps := 0
	if enc == ENC_FIXED:
		if (mapping.get("cw_values", []) as Array).has(raw):
			steps = 1
		elif (mapping.get("ccw_values", []) as Array).has(raw):
			steps = -1
	else:
		steps = decode_encoding(raw, enc)
	return -steps if mapping.get("invert", false) else steps


## 0..1 position of an absolute control within its learned raw range.
static func normalize_absolute(raw: int, mapping: Dictionary) -> float:
	var lo: float = mapping.get("raw_min", 0)
	var hi: float = mapping.get("raw_max", 127)
	if hi <= lo:
		return 0.0
	var x := clampf((float(raw) - lo) / (hi - lo), 0.0, 1.0)
	return 1.0 - x if mapping.get("invert", false) else x
