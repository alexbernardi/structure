## Where movement input frames come from. The simulation only ever sees frames, so a recorded list of frames
## replays exactly (Phase 5). A frame is {move: Vector2, yaw: float, jump_pressed, jump_held, sprint, crouch}.
extends RefCounted


## Reads the keyboard; `yaw` comes from the camera.
class Live:
	extends RefCounted
	var enabled := true

	func sample(yaw: float) -> Dictionary:
		if not enabled:
			return {"move": Vector2.ZERO, "yaw": yaw, "jump_pressed": false, "jump_held": false, "sprint": false, "crouch": false}
		return {
			"move": Input.get_vector("move_left", "move_right", "move_back", "move_forward"),
			"yaw": yaw,
			"jump_pressed": Input.is_action_just_pressed("jump"),
			"jump_held": Input.is_action_pressed("jump"),
			"sprint": Input.is_action_pressed("sprint"),
			"crouch": Input.is_action_pressed("crouch"),
		}


static func empty_frame(yaw := 0.0) -> Dictionary:
	return {"move": Vector2.ZERO, "yaw": yaw, "jump_pressed": false, "jump_held": false, "sprint": false, "crouch": false}
