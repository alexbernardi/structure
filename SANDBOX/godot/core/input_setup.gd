## Input map is defined in code (readable diffs, no serialized InputEvent blobs in project.godot).
extends RefCounted

const BINDINGS := {
	"move_forward": [KEY_W, KEY_UP],
	"move_back": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"jump": [KEY_SPACE],
	"interact": [KEY_E],
	"drop": [KEY_Q],
	"release_mouse": [KEY_ESCAPE],
	"toggle_debug": [KEY_F3],
}


static func ensure_actions() -> void:
	for action in BINDINGS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for key in BINDINGS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)
