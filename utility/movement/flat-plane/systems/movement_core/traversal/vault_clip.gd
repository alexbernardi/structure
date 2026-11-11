## Measured reference of the authored UAL2 SafetyVault (CC0) at mannequin scale. The clip root starts on the left-foot
## contact of a run and travels along +Z at a constant speed (root motion is linear); tests/test_traversal_vault.gd
## re-measures these numbers from the imported clip, so they cannot silently drift. The clip is not authored against a
## particular obstacle: its support hand sits about 0.1 m above any top its knees clear, so the planner adapts the body
## path and the hand contact instead of trusting a nominal obstacle height.
extends RefCounted

const CLIP := "SafetyVault"
const LENGTH := 22.0 / 30.0
const ROOT_SPEED := 4.358          ## m/s: root-motion travel / length (2.901 m source x 1.1018 proportion)
const FACE_DISTANCE := 1.20        ## m: wall face ahead of the clip root at t = 0 when stretch = 1 (the trailing knee has risen before it crosses the near edge)
const FACE_PER_STRETCH := 0.8      ## m of extra face distance per unit of stride stretch keeps that crossing time
const TAKEOFF := 0.05              ## s: left foot leaves the ground
const HAND_PLANT := 0.13           ## s: the authored right hand is lowest (it is meant to touch here or soon after)
const HAND_RELEASE := 0.30         ## s: the authored right hand starts lifting away
const LANDING := 0.69              ## s: left foot back on the ground
const PALM := 0.035                ## m: wrist above the contact surface
const RISE := [0.03, 0.17]         ## s: body warp fades in after the push-off and is complete before the knee crosses
const FALL := [0.50, 0.66]         ## s: and out before the landing foot reaches the ground


static func height_weight(time: float) -> float:
	return minf(smoothstep(RISE[0], RISE[1], time), 1.0 - smoothstep(FALL[0], FALL[1], time))


static func landing_weight(time: float) -> float:
	return smoothstep(0.40, LANDING, time)


## Root travel along the vault direction after `time` clip seconds at stride stretch `stretch`.
static func travel(time: float, stretch: float) -> float:
	return ROOT_SPEED * stretch * clampf(time, 0.0, LENGTH)


static func face_distance(stretch: float) -> float:
	return FACE_DISTANCE + FACE_PER_STRETCH * (stretch - 1.0)
