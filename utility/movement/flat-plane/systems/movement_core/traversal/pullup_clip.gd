## Measured reference of the authored UAL2 ClimbUp_2m (CC0) at mannequin scale: a two-handed jump, grip and pull-up
## onto a 2 m edge. Its root motion is not linear, so the root-motion export's keys (30 fps, source units) are kept
## here and scaled by the mannequin proportion (1.1018). Contact times and positions: tools/audit_pullup_clip.gd.
## Movement Lab 5.2 plays it from the grip frame: hanging braced on the edge, then the pull-up and the step over.
extends RefCounted

const CLIP := "ClimbUp_2m"
const LENGTH := 39.0 / 30.0
const SCALE := 1.1018
const UP := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.04, 0.08, 0.12, 0.16, 0.24, 0.2933, 0.3467, 0.4, 0.4436, 0.4873, 0.5309,
	0.5745, 0.6182, 0.6618, 0.7055, 0.7491, 0.7927, 0.8364, 0.88, 0.96, 1.04, 1.12, 1.2, 1.28, 1.36, 1.44, 1.52, 1.6, 1.68,
	1.76, 1.84, 1.92, 2.0]
const FWD := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0335, 0.0671, 0.1006, 0.1341, 0.2012, 0.2459, 0.2906, 0.3353, 0.3719,
	0.4084, 0.445, 0.4816, 0.5182, 0.5547, 0.5913, 0.6279, 0.6645, 0.701, 0.7376, 0.8047, 0.8717, 0.9388, 1.0058, 1.0729,
	1.1399, 1.207, 1.274, 1.3411, 1.4082, 1.4752, 1.5423, 1.6093, 1.6764]
const EDGE := 2.0 * SCALE        ## m: authored edge height (the root rises onto it)

## From tools/audit_pullup_clip.gd: both hands reach the lip at 0.33 s (wrists about 0.08 m below the top, gripping
## over the edge) and stay braced there while the feet push on the wall until about 0.5 s; the torso rises 0.5-0.9 s;
## the right foot plants on the top 0.9-1.13 s; standing by 1.25 s.
const REACH := 0.333             ## s: the hands arrive on the lip
const GRIP := 0.4                ## s: the hang pose (both hands gripping, body braced), held while hanging
const FACE := 0.70               ## m: authored face ahead of the clip root at t = 0 (wrists at 0.72-0.73 m, right foot on top at 0.97 m)
const LIP := 0.08                ## m: wrists below the top while gripping
const RIGHT_RELEASE := 0.68      ## s: the right hand leaves the edge (the left at 0.78 s)
const LEFT_RELEASE := 0.78
const RELEASE := 1.25            ## s: feet on top; control returns to the movement core


## Feet below the edge in the hang pose.
static func hang_drop() -> float:
	return EDGE - rise(GRIP)


static func _sample(table: Array, time: float) -> float:
	var f := clampf(time * 30.0, 0.0, table.size() - 1.0)
	var i := int(floorf(f))
	if i >= table.size() - 1:
		return float(table[-1]) * SCALE
	return lerpf(float(table[i]), float(table[i + 1]), f - i) * SCALE


static func rise(time: float) -> float:
	return _sample(UP, time)


static func forward(time: float) -> float:
	return _sample(FWD, time)
