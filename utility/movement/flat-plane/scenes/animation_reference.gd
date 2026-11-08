## Unretargeted Quaternius source playback. No controller, generated gait, body dynamics or root-motion consumer.
extends Node3D

const CLIPS := ["Idle", "Jog_Fwd", "Sprint", "Jump_Start", "Jump", "Jump_Land", "SafetyVault"]
const LABELS := ["Idle", "Jog", "Sprint", "Jump start", "Air loop (no separate Fall clip)", "Land", "Safety vault (UAL2)"]
const TRAVERSAL := ["SafetyVault"]
const Mannequin = preload("res://character/authored_mannequin.gd")

@onready var source: Node3D = $Source
@onready var traversal_source: Node3D = $TraversalSource
@onready var selector: OptionButton = $HUD/Panel/Controls/Clip
@onready var readout: Label = $HUD/Panel/Controls/Readout
var player: AnimationPlayer
var skeleton: Skeleton3D
var mannequin
var options := {}
var _frames := 0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--"):
			var pair := arg.trim_prefix("--").split("=", true, 1)
			if not options.has(pair[0]):
				options[pair[0]] = pair[1] if pair.size() > 1 else "true"
	traversal_source.hide()
	if options.has("mannequin"):
		source.hide()
		mannequin = Mannequin.new()
		mannequin.rotation.y = PI
		add_child(mannequin)
	if not _select_source(false):
		push_error("Quaternius reference requires exactly one AnimationPlayer and Skeleton3D")
		get_tree().quit(1)
		return
	print("Quaternius imported clips: ", player.get_animation_list())
	for i in CLIPS.size():
		var clip_player := player
		if mannequin == null and CLIPS[i] in TRAVERSAL:
			clip_player = traversal_source.find_children("*", "AnimationPlayer", true, false)[0]
		if not clip_player.has_animation(CLIPS[i]):
			push_error("Missing authentic Quaternius clip: %s" % CLIPS[i])
			get_tree().quit(1)
			return
		selector.add_item("%d - %s [%s]" % [i + 1, LABELS[i], CLIPS[i]])
	selector.item_selected.connect(play_clip)
	$HUD/Panel/Controls/Restart.pressed.connect(func() -> void: play_clip(selector.selected))
	$HUD/Panel/Controls/Pause.toggled.connect(func(paused: bool) -> void: player.speed_scale = 0.0 if paused else 1.0)
	var clip := String(options.get("clip", "Jog_Fwd"))
	if not CLIPS.has(clip):
		push_error("Unknown reference clip '%s'; available: %s" % [clip, CLIPS])
		get_tree().quit(1)
		return
	play_clip(CLIPS.find(clip))


## The original UAL1 character plays UAL1 clips; the original UAL2 character plays traversal clips (same rig).
func _select_source(traversal: bool) -> bool:
	if mannequin != null:
		player = mannequin.player
		skeleton = mannequin.skeleton
		return true
	var active: Node3D = traversal_source if traversal else source
	source.visible = not traversal
	traversal_source.visible = traversal
	var players := active.find_children("*", "AnimationPlayer", true, false)
	var skeletons := active.find_children("*", "Skeleton3D", true, false)
	if players.size() != 1 or skeletons.size() != 1:
		return false
	if player != null and player != players[0]:
		player.stop()
	player = players[0]
	skeleton = skeletons[0]
	return true


func play_clip(index: int) -> void:
	selector.select(index)
	_select_source(CLIPS[index] in TRAVERSAL)
	player.stop()
	player.play(CLIPS[index])
	player.advance(0.0)
	readout.text = "%s | 1x authored timing | in place\nNative humanoid import. No procedural corrections. Keys 1-%d select clips." % [
		"23-bone primitive target" if mannequin != null else "Original 65-bone reference", CLIPS.size()]


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode >= KEY_1 and event.keycode < KEY_1 + CLIPS.size():
		play_clip(event.keycode - KEY_1)


func _process(_delta: float) -> void:
	_frames += 1
	if options.has("screenshot") and _frames == int(options.get("screenshot-frame", 90)):
		if options.has("sample-time"):
			player.seek(float(options["sample-time"]), true)
		await RenderingServer.frame_post_draw
		var error := get_viewport().get_texture().get_image().save_png(String(options.screenshot))
		if error != OK:
			push_error("Reference screenshot failed: %s" % error_string(error))
		get_tree().quit(0 if error == OK else 1)
