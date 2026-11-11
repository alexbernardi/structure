## The authored vault measured once on the mannequin rig: the body's capsules and sole points per sample (for exact
## clearance against an obstacle slab), the support-hand and shoulder paths (for hand contact), and the jog phases whose
## poses match the vault's entry and exit. Pure data after build(); the planner evaluates it for any stride stretch,
## obstacle depth and approach angle.
extends RefCounted

const ClipPose = preload("res://traversal/clip_pose.gd")
const Clip = preload("res://traversal/vault_clip.gd")
const STEP := 1.0 / 120.0
const EDGE_OFFSETS := [1.0, 0.7, 0.4, 0.15, 0.0]  ## capsule sample points past each slab edge, in radii
## [bone, end bone, radius] capsules of the primitive mannequin (authored_mannequin._build_meshes); torso radii are
## rounded up to cover its ellipsoids.
const SEGMENTS := [["Hips", "Spine", 0.13], ["Spine", "UpperChest", 0.13],
	["LeftUpperLeg", "LeftLowerLeg", 0.075], ["LeftLowerLeg", "LeftFoot", 0.058],
	["RightUpperLeg", "RightLowerLeg", 0.075], ["RightLowerLeg", "RightFoot", 0.058],
	["LeftUpperArm", "LeftLowerArm", 0.055], ["LeftLowerArm", "LeftHand", 0.05],
	["RightUpperArm", "RightLowerArm", 0.055], ["RightLowerArm", "RightHand", 0.05]]
const SUPPORT_SEGMENT := 9          ## the right forearm: pinned by hand IK while in contact, so not a clearance surface
const SUPPORT_WINDOW := [Clip.HAND_PLANT - 0.06, Clip.HAND_RELEASE + 0.10]

var times := PackedFloat32Array()
var segments: Array[PackedVector3Array] = []  ## per sample: start, end pairs of SEGMENTS (root-relative, travel +Z)
var points: Array[PackedVector3Array] = []    ## per sample: sole corners and the bottom of the pelvis
var hand := PackedVector3Array()               ## per sample: right wrist
var shoulder := PackedVector3Array()           ## per sample: right shoulder joint
var spine := PackedVector3Array()              ## per sample: the Spine joint, pivot of the support-arm lean
var hips := PackedVector3Array()
var radii := PackedFloat32Array()
var arm_length := 0.0
var entry_phase := 0.0                         ## jog phase (0..1) whose pose matches the vault's first frame
var exit_phase := 0.0                          ## jog phase matching the vault's last frame
var mirror_entry_phase := 0.5                  ## the same for the mirrored (left-hand) vault, when installed
var mirror_exit_phase := 0.5
var has_mirror := false
var valid := false
var _lowest := PackedFloat32Array()            ## per sample: lowest clearance surface (see _summarise)
var _extent := PackedVector4Array()            ## per sample: z min, z max, x min, x max of the surface centres
var _widest := PackedFloat32Array()            ## per sample: largest capsule radius


## Measures the vault clip on `mannequin`; leaves `valid` false when the clip or the jog loop is missing.
func build(mannequin) -> void:
	var player: AnimationPlayer = mannequin.player
	if not player.has_animation(Clip.CLIP) or not player.has_animation("Jog_Fwd"):
		return
	var skeleton: Skeleton3D = mannequin.skeleton
	var clip := player.get_animation(Clip.CLIP)
	var map := ClipPose.tracks(clip)
	var index: Dictionary = mannequin.bone_index
	arm_length = skeleton.get_bone_rest(index.RightLowerArm).origin.length() + skeleton.get_bone_rest(index.RightHand).origin.length()
	for segment in SEGMENTS:
		radii.append(segment[2])
	var count := int(round(Clip.LENGTH / STEP)) + 1
	for i in count:
		var time := minf(i * STEP, Clip.LENGTH)
		var pose := ClipPose.sample(clip, skeleton, time, map)
		var ends := PackedVector3Array()
		for segment in SEGMENTS:
			ends.append(pose[index[segment[0]]].origin)
			ends.append(pose[index[segment[1]]].origin)
		var dots := PackedVector3Array()
		dots.append(pose[index.Hips].origin - Vector3(0, 0.13, 0))
		for side in ["Left", "Right"]:
			var foot: Transform3D = pose[index[side + "Foot"]]
			for corner in mannequin.sole_points[side]:
				dots.append(foot * corner)
		times.append(time)
		segments.append(ends)
		points.append(dots)
		hand.append(pose[index.RightHand].origin)
		shoulder.append(pose[index.RightUpperArm].origin)
		spine.append(pose[index.Spine].origin)
		hips.append(pose[index.Hips].origin)
	var jog := player.get_animation("Jog_Fwd")
	entry_phase = match_phase(jog, skeleton, index, ClipPose.sample(clip, skeleton, 0.0, map))
	exit_phase = match_phase(jog, skeleton, index, ClipPose.sample(clip, skeleton, Clip.LENGTH, map))
	if player.has_animation("SafetyVault_Mirror"):
		var mirrored := player.get_animation("SafetyVault_Mirror")
		var mirror_map := ClipPose.tracks(mirrored)
		mirror_entry_phase = match_phase(jog, skeleton, index, ClipPose.sample(mirrored, skeleton, 0.0, mirror_map))
		mirror_exit_phase = match_phase(jog, skeleton, index, ClipPose.sample(mirrored, skeleton, Clip.LENGTH, mirror_map))
		has_mirror = true
	_summarise()
	valid = true


## Per sample, over the clearance surfaces zones() counts (capsules, less the support forearm in its window, and
## points): the lowest surface height, the extent of the centres along z and x, and the largest radius. Lets zones()
## settle a sample that lies wholly in front of or beyond a slab without visiting its capsules.
func _summarise() -> void:
	for i in times.size():
		var skip := SUPPORT_SEGMENT if times[i] > SUPPORT_WINDOW[0] and times[i] < SUPPORT_WINDOW[1] else -1
		var low := INF
		var extent := AABB()
		var widest := 0.0
		var first := true
		var ends: PackedVector3Array = segments[i]
		for s in radii.size():
			if s == skip:
				continue
			low = minf(low, minf(ends[s * 2].y, ends[s * 2 + 1].y) - radii[s])
			widest = maxf(widest, radii[s])
			for end in [ends[s * 2], ends[s * 2 + 1]]:
				extent = AABB(end, Vector3.ZERO) if first else extent.expand(end)
				first = false
		for p in points[i]:
			low = minf(low, p.y)
			extent = AABB(p, Vector3.ZERO) if first else extent.expand(p)
			first = false
		_lowest.append(low)
		_extent.append(Vector4(extent.position.z, extent.end.z, extent.position.x, extent.end.x))
		_widest.append(widest)


## Phase (0..1) of looping `cycle` whose limb layout relative to the hips best matches `pose`.
static func match_phase(cycle: Animation, skeleton: Skeleton3D, index: Dictionary, pose: Array[Transform3D]) -> float:
	var map := ClipPose.tracks(cycle)
	var limbs := ["LeftFoot", "RightFoot", "LeftLowerLeg", "RightLowerLeg", "LeftHand", "RightHand"]
	var best := INF
	var phase := 0.0
	for i in 120:
		var other := ClipPose.sample(cycle, skeleton, cycle.length * i / 120.0, map)
		var cost := 0.0
		for limb in limbs:
			var a: Vector3 = pose[index[limb]].origin - pose[index.Hips].origin
			var b: Vector3 = other[index[limb]].origin - other[index.Hips].origin
			cost += a.distance_squared_to(b) * (2.0 if limb.ends_with("Foot") else 1.0)
		if cost < best:
			best = cost
			phase = i / 120.0
	return phase


## Where the right shoulder sits at sample i once the torso leans `lean` rad toward the support arm (a roll about the
## travel axis through the Spine joint; the character's right is -x, so a positive roll lowers the right shoulder).
func leaned_shoulder(i: int, lean: float) -> Vector3:
	return spine[i] + Basis(Vector3.BACK, lean) * (shoulder[i] - spine[i])


## Nearest sample index to a clip time.
func index_at(time: float) -> int:
	return clampi(int(round(time / STEP)), 0, times.size() - 1)


func sample_count() -> int:
	return times.size()


## Lowest body surface per sample in three zones along the travel frame (x = clip x, z along travel): in front of an
## obstacle slab, over it, and beyond it. The slab's face is `face` ahead of the root at t = 0 on the centre line and
## `face + x * slope` elsewhere; it is `depth` deep along travel. Capsules are clipped to the zones exactly (their
## lowest centre-line point in a zone is at a clip end), so no thin crossing can slip between samples of a limb.
## INF where nothing is in a zone.
func zones(stretch: float, face: float, depth: float, slope: float, margin := 0.03) -> Array[PackedFloat32Array]:
	# A sphere of radius r centred at height y and travel-axis position g counts in front (g <= lo), beyond (g >= hi)
	# and, with only the part overhanging a rounded corner just past an edge, over the slab. Inlined: this runs for every
	# capsule of every sample on each plan.
	const EPSILON := 0.0001
	var count := times.size()
	var low: Array[PackedFloat32Array] = [PackedFloat32Array(), PackedFloat32Array(), PackedFloat32Array()]
	for zone in 3:
		low[zone].resize(count)
	var lo := face - margin
	var hi := face + depth + margin
	var skew := sqrt(1.0 + slope * slope)   # travel-axis metres per metre perpendicular to the face
	var before := lo + EPSILON
	var beyond := hi - EPSILON
	var fringe := EPSILON * skew            # ends this close to touching a corner take the exact path
	var edges: Array = EDGE_OFFSETS
	var capsules := radii.size()
	var speed := Clip.ROOT_SPEED * stretch
	for i in count:
		var time: float = times[i]
		var travel := speed * clampf(time, 0.0, Clip.LENGTH)
		var b0 := INF
		var b1 := INF
		var b2 := INF
		var extent := _extent[i]
		var sway := absf(slope) * maxf(absf(extent.z), absf(extent.w))   # most that slope * x can shift a centre
		var reach := _widest[i] * skew + fringe
		if extent.y + travel + sway + reach < lo:
			low[0][i] = _lowest[i]    # the whole body is in front of the slab
			low[1][i] = INF
			low[2][i] = INF
			continue
		if extent.x + travel - sway - reach > hi:
			low[0][i] = INF
			low[1][i] = INF
			low[2][i] = _lowest[i]    # the whole body is beyond it
			continue
		var skip := SUPPORT_SEGMENT if time > SUPPORT_WINDOW[0] and time < SUPPORT_WINDOW[1] else -1
		var ends: PackedVector3Array = segments[i]
		for s in capsules:
			if s == skip:
				continue
			var a: Vector3 = ends[s * 2]
			var b: Vector3 = ends[s * 2 + 1]
			var r: float = radii[s]
			var ga := a.z + travel - slope * a.x
			var gb := b.z + travel - slope * b.x
			var reach_g := r * skew
			if maxf(ga, gb) < lo - reach_g - fringe:
				b0 = minf(b0, minf(a.y, b.y) - r)   # entirely in front: the lowest point is an end
				continue
			if minf(ga, gb) > hi + reach_g + fringe:
				b2 = minf(b2, minf(a.y, b.y) - r)
				continue
			var dg := gb - ga
			var dy := b.y - a.y
			var candidates := 2 + edges.size() * 2 if absf(dg) > 0.000001 else 2
			for k in candidates:
				var t := float(k)
				if k >= 2:
					var edge: float = edges[(k - 2) >> 1] * reach_g
					t = ((lo - edge if (k & 1) == 0 else hi + edge) - ga) / dg
					if t <= 0.0 or t >= 1.0:
						continue   # clamps onto an end, which is already a candidate
				var g := ga + dg * t
				var y := a.y + dy * t
				if g <= before:
					b0 = minf(b0, y - r)
				if g >= beyond:
					b2 = minf(b2, y - r)
				var outside := maxf(maxf(lo - g, g - hi), 0.0) / skew
				if outside <= r + EPSILON:
					b1 = minf(b1, y - sqrt(maxf(r * r - outside * outside, 0.0)))
		for p in points[i]:
			var g := p.z + travel - slope * p.x
			if g <= before:
				b0 = minf(b0, p.y)
			if g >= beyond:
				b2 = minf(b2, p.y)
			if g >= lo - fringe and g <= hi + fringe:
				b1 = minf(b1, p.y)
		low[0][i] = b0
		low[1][i] = b1
		low[2][i] = b2
	return low
