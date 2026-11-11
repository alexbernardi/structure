## Measured reference of the authored UAL2 JogToFlip (CC0, in-place export) on the mannequin (tools/audit_flip_clip.gd):
## a running front flip. The in-place export keeps the hips' own rise (to 2.1 m) while the feet go over the head, so the
## body's physics jump owns the height instead: the presentation offset cancels the clip's rise (hips_lift).
## Movement Lab 5.3 plays it from the deepest crouch (START) and spreads the airborne turn over the real airtime.
extends RefCounted

const CLIP := "JogToFlip"
const LENGTH := 1.2
## Hips height above the clip root, 30 fps, mannequin scale (audit).
const HIPS := [0.913, 0.856, 0.753, 0.698, 0.799, 1.022, 1.262, 1.490, 1.693, 1.860, 1.979, 2.037, 2.082, 2.106, 2.038,
	1.937, 1.838, 1.705, 1.558, 1.414, 1.284, 1.166, 1.051, 0.940, 0.838, 0.748, 0.677, 0.629, 0.612, 0.653, 0.751,
	0.867, 0.964, 1.005, 0.981, 0.937, 0.913]
## Lowest drawn point (toes, feet, head, hands) above the clip root, 30 fps (audit).
const LOWEST := [0.184, 0.048, 0.017, 0.017, 0.039, 0.129, 0.225, 0.426, 0.623, 0.789, 0.986, 1.349, 1.417, 1.473, 1.385,
	1.353, 1.433, 1.554, 1.521, 1.303, 1.098, 0.678, 0.304, 0.063, 0.04, 0.018, 0.018, 0.018, 0.018, 0.017, 0.014, 0.013,
	0.122, 0.15, 0.172, 0.18, 0.184]

## From the audit: deepest crouch 0.10 s (hips 0.70 m); the feet leave at 0.13 s; the hips pass upside down at 0.52 s;
## both toes are back on the ground at 0.80 s with 340 of the 360 degrees turned; the knees absorb the landing to
## 0.93 s and the body stands by 1.10 s.
const START := 0.10              ## s: shown on the takeoff tick (the crouch the flip is taken from)
const TAKEOFF := 0.133           ## s: feet off the ground
const INVERTED := 0.52           ## s: upside down
const LAND := 0.80               ## s: toes down again (the airborne part ends here)
const ABSORB := 0.93             ## s: deepest landing crouch
const END := 1.10                ## s: standing; the flip's presentation ends (the rest of the clip is a jog step)
const UPRIGHT := 0.70            ## s: from here the body is upright enough to catch a ledge again
const FADE_IN := 0.12            ## s: default crossfade into the flip (traversal transition_response); the drop follows
                                 ## its weight, since the pose being faded out (crouch, slide) has its feet at the root


static func _sample(table: Array, time: float) -> float:
	var f := clampf(time * 30.0, 0.0, table.size() - 1.0)
	var i := int(floorf(f))
	if i >= table.size() - 1:
		return float(table[-1])
	return lerpf(float(table[i]), float(table[i + 1]), f - i)


static func hips(time: float) -> float:
	return _sample(HIPS, time)


static func lowest(time: float) -> float:
	return _sample(LOWEST, time)


## The clip's own vertical rise of the hips at `time` above a line from the takeoff crouch to the landing: what the
## presentation removes while airborne, so the body's ballistic arc is the only height.
static func hips_lift(time: float) -> float:
	if time <= START or time >= LAND:
		return 0.0
	var u := (time - START) / (LAND - START)
	return hips(time) - lerpf(hips(START), hips(LAND), u)


## How far the drawn character is lowered at `time` with the body `height` above the ground under it: the clip's rise,
## but never so much that its lowest point goes below that ground. During the push-off (the clip's hips rise faster than
## the body's arc) the feet stay on the ground while the legs extend; into the landing they meet it as the knees bend.
static func drawn_drop(time: float, height: float) -> float:
	return clampf(hips_lift(time), 0.0, maxf(0.0, height + lowest(time)))
