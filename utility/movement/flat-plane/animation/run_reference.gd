extends RefCounted

const LABELS := ["Contact", "Down", "Passing", "Flight"]
const SOURCE_FRAMES := [1, 5, 9, 13, 17]


## The source frames 1-17 span one step (half a cycle): Contact, Down and Passing fall through the stance (Passing is
## late stance, the free knee driving past the planted foot) and Flight sits in the following no-contact interval.
static func phases(duty: float) -> Array[float]:
	var stance := clampf(duty, 0.18, 0.48)
	return [0.0, stance * 5.0 / 12.0, stance * 5.0 / 6.0, stance + 0.375 * (0.5 - stance)]
