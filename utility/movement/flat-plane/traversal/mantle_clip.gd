## Measured reference of the authored UAL2 ClimbUp_1m (CC0) at mannequin scale (tools/audit_climb_clip.gd).
## A running climb onto a ledge: the left hand and right foot plant on the top, the body rises and steps forward
## onto it. The root-motion export moves the root linearly 1.0 m up and 1.676 m forward (source units, x 1.1018).
## The in-place clip is played by clip time; the mantle action warps that root path onto the measured ledge so the
## authored contacts land on the actual face and top (motion warping), while the collider follows its own safe path.
extends RefCounted

const CLIP := "ClimbUp_1m"
const LENGTH := 20.0 / 30.0
const RISE := 1.1018           ## m: authored ledge height (root rise over the clip), = top under the planted foot
const EDGE := RISE             ## the same, under the name the pull-up clip uses (shared clip interface)
const FORWARD := 1.8466        ## m: authored root travel over the clip
const FACE := 0.75             ## m: authored face ahead of the clip root at t = 0 (hand at 0.86 m, planted foot at 0.885 m)
const HAND_ON := 0.15          ## s: left hand reaches the top
const FOOT_ON := 0.22          ## s: right foot set on the top (stays until about 0.5 s)
const CONTACT := 0.15          ## s: by now the warp has aligned the authored contacts with the actual ledge
const RELEASE := 0.62          ## s: both feet on top; control returns to the movement core


static func rise(time: float) -> float:
	return RISE * clampf(time / LENGTH, 0.0, 1.0)


static func forward(time: float) -> float:
	return FORWARD * clampf(time / LENGTH, 0.0, 1.0)


## How far beyond the face the authored root ends.
static func exit_inset() -> float:
	return FORWARD - FACE
