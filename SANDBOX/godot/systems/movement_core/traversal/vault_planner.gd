## Pure vault planning: one measured obstacle and the approach speed in, a complete timed vault or a rejection reason
## out. No nodes, physics queries or bones. Plan frame: origin = the body (collider bottom centre) at takeoff, on the
## takeoff ground; z along the travel direction; x = the clip's x (the character's left); y up.
##
## The visual body follows the authored clip, lifted by a warp that keeps every limb above the top (computed from the
## clip's measured silhouette, so it is exact for any stretch, depth and angle) and dipped while the hand is planted
## so the support arm can reach the top. The collider follows its own smooth hump that clears the obstacle.
extends RefCounted

const Clip = preload("res://systems/movement_core/traversal/vault_clip.gd")

const MIN_ENTRY_SPEED := 2.0       ## m/s: slower approaches never vault
const MIN_TRAVEL := 3.0            ## m/s: vault ground speed range; the approach eases into it
const MAX_TRAVEL := 8.0
const MIN_RATE := 0.8              ## clip playback rate range (as the run cadence)
const MAX_RATE := 1.45
const MIN_STRETCH := 0.85          ## root travel stretch range
const MAX_STRETCH := 1.3
const MIN_HEIGHT := 0.6
const MAX_HEIGHT := 1.25
const MAX_ANGLE := 0.6109          ## rad (35 degrees) between the travel direction and the face normal
const MAX_DEPTH := 0.9             ## m of obstacle along the travel direction
const LANDING_RANGE := [-0.6, 0.3] ## m of landing ground relative to the takeoff ground
const WARP_RANGE := [-0.45, 0.3]   ## m the visual body may be lowered / lifted against the authored clip
const MAX_DIP := 0.15              ## m the body may sink while the hand is planted
const CLEARANCE := 0.03            ## m between limb surfaces and the top
const GROUND_TOLERANCE := 0.02
const HAND_INSET := 0.06           ## m: planted hand at least this far inside the top's edges
const HAND_HOLD := 0.045           ## s (clip): the hand is fully planted this long either side of the shoulder passing over it
const MIN_HOLD := 0.025            ## s (clip): the shortest full plant a far or high top may shorten the hold to
const MAX_LEAN := 0.3142           ## rad (18 degrees) the torso may roll onto the support arm
const LEAN_SEARCH := 6             ## bisection steps for the lean (about 0.3 degrees)
const CENTRE_STRIDE := 2           ## samples between candidate contact centres
const REACH := 0.97                ## share of the arm length the hand IK may use
const MAX_HAND_GAP := 0.02         ## m of reach the support hand may leave unmet before the vault is refused
const BODY_RADIUS := 0.38          ## m: collider radius plus skin
const CREST := 0.04                ## m: collider bottom above the top
const TAKEOFF_TOLERANCE := 0.1     ## m: accepted error of the actual takeoff distance

var _memo_key := []
var _memo := {}


## Vault ground speed, playback rate, stride stretch and takeoff distance for an approach speed.
static func timing(entry_speed: float) -> Dictionary:
	var travel_speed := clampf(entry_speed, MIN_TRAVEL, MAX_TRAVEL)
	var ratio := travel_speed / Clip.ROOT_SPEED
	var stretch := clampf(ratio / clampf(sqrt(ratio), MIN_RATE, MAX_RATE), MIN_STRETCH, MAX_STRETCH)
	var rate := clampf(ratio / stretch, MIN_RATE, MAX_RATE)
	return {"travel_speed": Clip.ROOT_SPEED * stretch * rate, "rate": rate, "stretch": stretch,
		"takeoff": Clip.face_distance(stretch), "duration": Clip.LENGTH / rate}


## Timing that takes off from `distance` (a late press, inside the nominal takeoff point): the stride is shortened so
## the authored contact still lands on the obstacle and the playback quickens to keep the ground speed. Empty when no
## stretch / rate within the authored bounds reaches that distance.
static func timing_at(entry_speed: float, distance: float) -> Dictionary:
	var travel_speed := clampf(entry_speed, MIN_TRAVEL, MAX_TRAVEL)
	var ratio := travel_speed / Clip.ROOT_SPEED
	var stretch := 1.0 + (distance - Clip.FACE_DISTANCE) / Clip.FACE_PER_STRETCH
	if stretch < MIN_STRETCH - 1e-6 or stretch > MAX_STRETCH + 1e-6:
		return {}
	var rate := ratio / stretch
	if rate < MIN_RATE - 1e-6 or rate > MAX_RATE + 1e-6:
		return {}
	rate = clampf(rate, MIN_RATE, MAX_RATE)
	return {"travel_speed": Clip.ROOT_SPEED * stretch * rate, "rate": rate, "stretch": stretch,
		"takeoff": Clip.face_distance(stretch), "duration": Clip.LENGTH / rate}


## Closest face distance a late press can still vault from at this approach speed.
static func latest_takeoff(entry_speed: float) -> float:
	var ratio := clampf(entry_speed, MIN_TRAVEL, MAX_TRAVEL) / Clip.ROOT_SPEED
	return Clip.face_distance(clampf(ratio / MAX_RATE, MIN_STRETCH, MAX_STRETCH))


## The character's limits (from its effective attributes); missing keys use the baseline-human constants.
static func limits_from(capabilities) -> Dictionary:
	if capabilities == null:
		return {}
	return {"max_height": capabilities.get_value("vault_max_height"), "max_depth": capabilities.get_value("vault_max_depth"),
		"max_lift": capabilities.get_value("vault_lift"), "landing_drop": capabilities.get_value("landing_tolerance")}


static func reject(reason: String, extra := {}) -> Dictionary:
	var result := {"ok": false, "reason": reason}
	result.merge(extra)
	return result


## The geometric limits alone (no timing or clearance): the rejection reason, or "" when the obstacle's size, angle and
## landing are in range. Cheap enough to screen an obstacle seen far ahead.
static func screen(obstacle: Dictionary, limits := {}) -> String:
	var height: float = obstacle.height
	if height < MIN_HEIGHT:
		return "too_low"
	if height > limits.get("max_height", MAX_HEIGHT):
		return "too_high"
	if absf(obstacle.angle) > MAX_ANGLE:
		return "too_angled"
	if obstacle.depth > limits.get("max_depth", MAX_DEPTH):
		return "too_deep"
	if obstacle.landing < -limits.get("landing_drop", -LANDING_RANGE[0]) or obstacle.landing > LANDING_RANGE[1]:
		return "bad_landing"
	return ""


## obstacle: {distance (face ahead of the body along travel), height (top above takeoff ground), depth (along
## travel), slope (face offset along travel per metre of clip x), angle (rad), landing (ground beyond, relative)}.
## The latest plan is remembered: arming and the takeoff plan the same measured obstacle, and a plan costs about a
## millisecond.
## `limits`: see limits_from(). `timed`: a timing to use instead of timing(entry_speed) (a late press, timing_at()).
func plan(profile, obstacle: Dictionary, entry_speed: float, momentum: float, limits := {}, timed := {}) -> Dictionary:
	var key := [profile, snappedf(obstacle.distance, 0.0001), snappedf(obstacle.height, 0.0001), snappedf(obstacle.depth, 0.0001),
		snappedf(obstacle.slope, 0.0001), snappedf(obstacle.landing, 0.0001), snappedf(entry_speed, 0.0001), snappedf(momentum, 0.0001),
		limits, snappedf(timed.get("stretch", 0.0), 0.0001)]
	if key != _memo_key:
		_memo_key = key
		_memo = _plan(profile, obstacle, entry_speed, momentum, limits, timed)
	return _memo.duplicate()


func _plan(profile, obstacle: Dictionary, entry_speed: float, momentum: float, limits := {}, timed_override := {}) -> Dictionary:
	if profile == null or not profile.valid:
		return reject("no_clip")
	if entry_speed < MIN_ENTRY_SPEED:
		return reject("too_slow")
	var screened := screen(obstacle, limits)
	if screened != "":
		return reject(screened)
	var height: float = obstacle.height
	var depth: float = obstacle.depth
	var slope: float = obstacle.slope
	var landing: float = obstacle.landing
	var timed := timing(entry_speed) if timed_override.is_empty() else timed_override
	var stretch: float = timed.stretch
	var face: float = obstacle.distance
	if absf(face - timed.takeoff) > TAKEOFF_TOLERANCE:
		return reject("off_takeoff", {"takeoff": timed.takeoff})
	var speed: float = Clip.ROOT_SPEED * stretch
	var radius := BODY_RADIUS * sqrt(1.0 + slope * slope)
	var rise_end := (face - radius) / speed
	var fall_start := (face + depth + radius) / speed
	if rise_end < 0.08:
		return reject("too_close")
	if fall_start > Clip.LANDING - 0.06:
		return reject("too_deep")
	if Clip.travel(Clip.LANDING, stretch) - face - depth < radius + 0.1:
		return reject("short_landing")
	var zones: Array = profile.zones(stretch, face, depth, slope)
	var count: int = profile.sample_count()
	var bound := PackedFloat32Array()
	var warp: float = WARP_RANGE[0]
	for i in count:
		var t: float = profile.times[i]
		var need := -INF
		if is_finite(zones[1][i]):
			need = height + CLEARANCE - zones[1][i]
		if is_finite(zones[0][i]):
			need = maxf(need, -GROUND_TOLERANCE - zones[0][i])
		if is_finite(zones[2][i]):
			need = maxf(need, landing - GROUND_TOLERANCE - zones[2][i])
		bound.append(need)
		var lift := Clip.height_weight(t)
		var base := landing * Clip.landing_weight(t)
		if lift >= 0.02:
			warp = maxf(warp, (need - base) / lift)
		elif base < need - 0.005:
			return reject("body_clip", {"time": t})
	if warp > limits.get("max_lift", WARP_RANGE[1]):
		return reject("too_high")
	var result := {"ok": true, "reason": "ok", "stretch": stretch, "rate": timed.rate, "travel_speed": timed.travel_speed,
		"duration": timed.duration, "exit_speed": lerpf(timed.travel_speed, maxf(entry_speed, timed.travel_speed), clampf(momentum, 0.0, 1.0)),
		"face": face, "depth": depth, "height": height, "slope": slope, "landing": landing, "warp": warp,
		"crest": height + CREST, "rise_end": rise_end, "fall_start": fall_start, "dip": 0.0, "lean": 0.0, "hand_gap": 0.0}
	if not _plan_hand(profile, result, bound):
		return reject("no_hand_contact")
	if result.hand_gap > MAX_HAND_GAP:
		return reject("out_of_reach", {"hand_gap": result.hand_gap})
	return result


## Picks the planted hand point and contact window, then the smallest torso lean onto the support arm and the dip
## (within the per-sample clearance slack) that bring the top within reach. Candidate contacts are centred where the
## shoulder passes over the top; the one leaving the least reach unmet wins (a top still out of reach at the ends of the
## hold gets a shorter full plant, down to MIN_HOLD). Records any reach left unmet as `hand_gap`.
func _plan_hand(profile, result: Dictionary, bound: PackedFloat32Array) -> bool:
	var stretch: float = result.stretch
	var reach: float = profile.arm_length * REACH
	var base := PackedFloat32Array()
	var travel := PackedFloat32Array()
	for i in profile.sample_count():
		var t: float = profile.times[i]
		base.append(result.warp * Clip.height_weight(t) + result.landing * Clip.landing_weight(t))
		travel.append(Clip.travel(t, stretch))
	var best := {}
	var c: int = profile.index_at(Clip.HAND_PLANT)
	while c <= profile.index_at(Clip.HAND_RELEASE):
		var trial := _hand_trial(profile, result, base, bound, travel, c, reach)
		if best.is_empty() or trial.cost < best.cost - 0.0005:
			best = trial
		c += CENTRE_STRIDE
	if best.is_empty():
		return false
	for key in ["hand_on", "hand_off", "hand_point", "dip", "lean", "hand_gap"]:
		result[key] = best[key]
	return true


func _hand_trial(profile, result: Dictionary, base: PackedFloat32Array, bound: PackedFloat32Array, travel: PackedFloat32Array, c: int, reach: float) -> Dictionary:
	var stretch: float = result.stretch
	var centre: float = profile.times[c]
	var s: Vector3 = profile.shoulder[c]
	var h: Vector3 = profile.hand[c]
	var point := Vector3(lerpf(h.x, s.x, 0.5), result.height + Clip.PALM, s.z + Clip.travel(centre, stretch))
	var near: float = result.face + point.x * result.slope
	if result.depth > HAND_INSET * 2.0:
		point.z = clampf(point.z, near + HAND_INSET, near + result.depth - HAND_INSET)
	else:
		point.z = near + result.depth * 0.5
	var trial := {"hand_on": centre - HAND_HOLD, "hand_off": centre + HAND_HOLD, "hand_point": point, "stretch": stretch}
	var first: int = profile.index_at(centre - HAND_HOLD - 0.06)
	var last: int = profile.index_at(centre + HAND_HOLD + 0.10)
	var held := PackedInt32Array()
	var allowed: float = MAX_DIP
	var times: PackedFloat32Array = profile.times
	var on: float = trial.hand_on
	var off: float = trial.hand_off
	for i in range(first, last + 1):
		var t := times[i]
		var sink := smoothstep(on - 0.06, on, t) * (1.0 - smoothstep(off, off + 0.10, t))   # support_weight
		if sink > 0.0:
			allowed = minf(allowed, maxf(0.0, base[i] - bound[i]) / sink)
		if smoothstep(on - 0.05, on, t) * (1.0 - smoothstep(off, off + 0.06, t)) >= 0.999:   # hand_weight
			held.append(i)
	# Lean first (it keeps the authored body path); the dip, bounded by clearance, covers what the lean cannot.
	var lean := 0.0
	var needed := _dip_needed(profile, point, held, 0.0, base, travel, reach)
	if needed > allowed:
		var lo := 0.0
		var hi := MAX_LEAN
		var needed_hi := NAN
		for step in LEAN_SEARCH:
			var mid := (lo + hi) * 0.5
			var at_mid := _dip_needed(profile, point, held, mid, base, travel, reach)
			if at_mid > allowed:
				lo = mid
			else:
				hi = mid
				needed_hi = at_mid
		lean = hi
		needed = _dip_needed(profile, point, held, hi, base, travel, reach) if is_nan(needed_hi) else needed_hi
	trial.lean = lean
	trial.dip = clampf(minf(needed, allowed), 0.0, MAX_DIP)
	trial.hand_gap = needed - trial.dip    # the reach left unmet at the worst fully planted sample
	var shortfall := 0.0
	if trial.hand_gap > 0.0005:
		# A far or high top: a quicker touch, fully planted only while the arm reaches (the support envelope narrows with
		# it, so the clearance-bounded dip stays clear).
		var touch := _reached_window(profile, point, held, lean, trial.dip, base, travel, reach)
		if not touch.is_empty() and touch[1] - touch[0] >= MIN_HOLD - 1e-5:
			shortfall = (off - on) - (touch[1] - touch[0])
			trial.hand_on = touch[0]
			trial.hand_off = touch[1]
			trial.hand_gap = 0.0
	trial.cost = trial.hand_gap * 10.0 + trial.dip + lean * 0.2 + shortfall
	return trial


## Times of the longest run of fully planted samples (within `held`) at which the arm reaches the point with the given
## lean and dip, or [] when none does.
func _reached_window(profile, point: Vector3, held: PackedInt32Array, lean: float, dip: float, base: PackedFloat32Array, travel: PackedFloat32Array, reach: float) -> Array:
	var best := []
	var start := -1
	for k in held.size() + 1:
		var ok := false
		if k < held.size():
			ok = _dip_needed(profile, point, PackedInt32Array([held[k]]), lean, base, travel, reach) <= dip + 0.0005
		if ok and start < 0:
			start = k
		elif not ok and start >= 0:
			if best.is_empty() or k - start > best[2]:
				best = [profile.times[held[start]], profile.times[held[k - 1]], k - start]
			start = -1
	return [] if best.is_empty() else [best[0], best[1]]


## Dip that lets the arm reach the planted point at every fully planted sample (indices `held`), given the torso lean:
## the most any of them leaves the lowest wrist position the arm can reach (shoulder leaned by `lean` about the Spine
## joint, body lifted by `base`) above the point. INF when the point is out of reach horizontally.
func _dip_needed(profile, point: Vector3, held: PackedInt32Array, lean: float, base: PackedFloat32Array, travel: PackedFloat32Array, reach: float) -> float:
	var spine: PackedVector3Array = profile.spine
	var shoulder: PackedVector3Array = profile.shoulder
	var cosine := cos(lean)
	var sine := sin(lean)
	var reach_squared := reach * reach
	var needed := 0.0
	for i in held:
		var pivot := spine[i]
		var arm := shoulder[i] - pivot
		# The shoulder rolled about the travel axis through the Spine joint (Basis(Vector3.BACK, lean)).
		var dx := pivot.x + arm.x * cosine - arm.y * sine - point.x
		var dz := pivot.z + arm.z + travel[i] - point.z
		var flat := dx * dx + dz * dz
		if flat > reach_squared:
			return INF
		needed = maxf(needed, pivot.y + arm.x * sine + arm.y * cosine + base[i] - sqrt(reach_squared - flat) - point.y)
	return needed


static func visual_height(plan: Dictionary, time: float) -> float:
	return plan.warp * Clip.height_weight(time) + plan.landing * Clip.landing_weight(time) - plan.dip * support_weight(plan, time)


## Envelope of the support adjustments (dip and torso lean): in place as the hand plants, gone shortly after release.
static func support_weight(plan: Dictionary, time: float) -> float:
	return smoothstep(plan.hand_on - 0.06, plan.hand_on, time) * (1.0 - smoothstep(plan.hand_off, plan.hand_off + 0.10, time))


static func hand_weight(plan: Dictionary, time: float) -> float:
	return smoothstep(plan.hand_on - 0.05, plan.hand_on, time) * (1.0 - smoothstep(plan.hand_off, plan.hand_off + 0.06, time))


## Collider bottom above the takeoff ground: a smooth hump that is over the top before the collider reaches the face
## and stays there until it has passed the back, then settles onto the landing ground.
static func collider_height(plan: Dictionary, time: float) -> float:
	if time < plan.rise_end:
		return plan.crest * smoothstep(0.0, plan.rise_end, time)
	if time < plan.fall_start:
		return plan.crest
	return lerpf(plan.crest, plan.landing, smoothstep(plan.fall_start, Clip.LANDING, time))


static func travel(plan: Dictionary, time: float) -> float:
	return Clip.travel(time, plan.stretch)
