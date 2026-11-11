## Movement Core input actions, registered at runtime so a consumer project needs no hand-edited InputMap. Existing
## actions of the same name keep their events (a project may rebind them); these keys are added only if missing.
## Laboratory-only actions (tuning, HUD, presets) live with the laboratory, not here.
extends RefCounted

const ACTIONS := {
	"move_forward": [KEY_W, KEY_UP],
	"move_back": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"jump": [KEY_SPACE],
	"sprint": [KEY_SHIFT],
	"crouch": [KEY_CTRL, KEY_C],
}


static func register(actions: Dictionary = ACTIONS) -> void:
	for action in actions:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key in actions[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			if not InputMap.action_has_event(action, ev):
				InputMap.action_add_event(action, ev)
