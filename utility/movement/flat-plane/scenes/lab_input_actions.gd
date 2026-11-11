## The laboratory's input actions: the Movement Core's movement actions plus the lab's own (respawn, mouse, HUD,
## MIDI, tuning editor, banks and presets). Registered at runtime, so the project needs no hand-edited InputMap.
extends RefCounted

const CoreActions = preload("res://systems/movement_core/movement/input_actions.gd")

const ACTIONS := {
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
	CoreActions.register()
	CoreActions.register(ACTIONS)
