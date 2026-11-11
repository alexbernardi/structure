extends SceneTree

const Visual = preload("res://systems/movement_core/character/character_visual.gd")
const Walk = preload("res://animation/walk_animation.gd")
const Gait = preload("res://animation/gait_model.gd")
const GaitParams = preload("res://animation/gait_params.gd")
const RigParams = preload("res://systems/movement_core/animation/rig_params.gd")
const Graph = preload("res://animation/walk_tree.tres")


func _initialize() -> void:
	call_deferred("_generate")


func _own(node: Node, owner_node: Node) -> void:
	for child in node.get_children():
		child.owner = owner_node
		_own(child, owner_node)


func _generate() -> void:
	var visual := Visual.new()
	visual.name = "Visual"
	root.add_child(visual)
	visual.apply_rig(RigParams.create())
	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	visual.add_child(player)
	var library := AnimationLibrary.new()
	library.resource_local_to_scene = true
	for name in ["RESET", "legacy", "body", "walk"]:
		library.add_animation(name, Walk.static_clip(visual))
	player.add_animation_library("", library)
	var tree := AnimationTree.new()
	tree.name = "AnimationTree"
	tree.anim_player = ^"../AnimationPlayer"
	tree.tree_root = Graph.duplicate(true)
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	visual.add_child(tree)
	tree.set("parameters/WalkBlend/blend_amount", 1.0)
	tree.set("parameters/Locomotion/blend_amount", 1.0)
	tree.set("parameters/BodyAdd/add_amount", 1.0)
	tree.set("parameters/WalkSpeed/scale", 1.0)
	var driver := Walk.new()
	driver.name = "WalkAnimation"
	visual.add_child(driver)
	var model := Gait.new(GaitParams.create(), RigParams.create())
	model.update(0.0, model.p.get_value("walk_speed"))
	driver.setup(visual, model)
	driver.regenerate()
	tree.active = false
	# Reference the shared, editable graph rather than embedding an inaccessible runtime copy.
	tree.tree_root = Graph
	_own(visual, visual)
	var packed := PackedScene.new()
	var err := packed.pack(visual)
	if err == OK:
		err = ResourceSaver.save(packed, "res://character/walk_visual.tscn")
	if err != OK:
		push_error("Could not save walk_visual.tscn: %s" % error_string(err))
	visual.queue_free()
	quit(0 if err == OK else 1)
