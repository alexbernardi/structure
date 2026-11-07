## Soft takeover ("pickup"): a physical fader whose position no longer matches the parameter it controls must not
## move the parameter until it reaches the current value. This is what prevents abrupt jumps when switching banks or
## presets (or when a knob / reset changed the value while the fader stayed where it was).
## State: {engaged: bool, side: -1|0|1} where side is which side of the target the fader was last seen on.
extends RefCounted

const TOLERANCE := 0.025   ## normalised distance that counts as "reached" (a 7-bit fader step is ~0.008)


## State when a slot becomes active or its parameter changed. `physical` is the fader's last known 0..1 position
## or a negative number if it has not been touched yet.
static func arm(physical: float, target: float, tol := TOLERANCE) -> Dictionary:
	if physical >= 0.0 and absf(physical - target) <= tol:
		return {"engaged": true, "side": 0}
	return {"engaged": false, "side": 0 if physical < 0.0 else int(signf(physical - target))}


## Feeds a new physical position. The fader engages when it is within tolerance of the target or has crossed it.
static func update(state: Dictionary, physical: float, target: float, tol := TOLERANCE) -> Dictionary:
	if state.engaged:
		return state
	var diff := physical - target
	if absf(diff) <= tol:
		return {"engaged": true, "side": 0}
	var side := int(signf(diff))
	if state.side != 0 and side != state.side:
		return {"engaged": true, "side": 0}
	return {"engaged": false, "side": side}
