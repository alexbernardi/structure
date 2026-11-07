## Input actions for the lab, registered at runtime so the project needs no hand-edited InputMap.
extends RefCounted

const ACTIONS := {
	"move_forward": [KEY_W, KEY_UP],
	"move_back": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"jump": [KEY_SPACE],
	"sprint": [KEY_SHIFT],
	"crouch": [KEY_CTRL, KEY_C],
	"respawn": [KEY_R],
	"release_mouse": [KEY_ESCAPE],
	"toggle_hud": [KEY_F3],
	"toggle_midi": [KEY_F2],
	"toggle_editor": [KEY_F4],
	"bank_next": [KEY_PAGEDOWN],
	"bank_prev": [KEY_PAGEUP],
	"reset_all_params": [KEY_HOME],
	"preset_next": [KEY_BRACKETRIGHT],
	"preset_prev": [KEY_BRACKETLEFT],
	"preset_save": [KEY_F5],
}


static func register() -> void:
	for action in ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key in ACTIONS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			if not InputMap.action_has_event(action, ev):
				InputMap.action_add_event(action, ev)
