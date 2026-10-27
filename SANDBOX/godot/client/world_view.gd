## Client-side presentation of the replicated world (placeholder geometry only).
## Never mutates game state: it mirrors the WorldState replica the ClientApp maintains.
extends Node3D

const WorldGen = preload("res://world/world_gen.gd")
const WorldState = preload("res://world/world_state.gd")
const Palette = preload("res://client/palette.gd")
const RemoteAvatar = preload("res://client/remote_avatar.gd")

## Produced by the Blender pipeline (COMMON-ASSETS/models/resource_stone). Falls back to a box if absent.
const RESOURCE_MODEL := "res://assets/common/models/resource_stone/resource_stone.glb"
const BLOCKS_PER_LAYER := 4
const BLOCK_SIZE := Vector3(1.0, 0.5, 1.0)
const PLATFORM_HEIGHT := 0.3

var _world_root: Node3D
var _resources := {}   # id -> Node3D
var _avatars := {}     # peer -> RemoteAvatar
var _sites := {}       # id -> {blocks: Node3D, label: Label3D, body: CollisionShape3D}
var _resource_scene: PackedScene


func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = Sky.new()
	env.sky.sky_material = ProceduralSkyMaterial.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, -35.0, 0.0)
	sun.shadow_enabled = true
	add_child(sun)
	if ResourceLoader.exists(RESOURCE_MODEL):
		_resource_scene = load(RESOURCE_MODEL)


func build_world(state: WorldState, me: int) -> void:
	clear_world()
	_world_root = Node3D.new()
	_world_root.name = "World"
	add_child(_world_root)
	_build_ground()
	_build_obstacles(state.world_seed)
	for site in state.sites.values():
		_add_site(site)
	for r in state.resources.values():
		_add_resource(r)
	for p in state.players.values():
		if p.peer != me:
			_add_avatar(p)
	refresh_carrying(state, me)


func clear_world() -> void:
	if _world_root != null:
		_world_root.queue_free()
		_world_root = null
	_resources.clear()
	_avatars.clear()
	_sites.clear()


func on_event(e: Dictionary, state: WorldState, me: int) -> void:
	match String(e.type):
		"resource_spawned":
			_add_resource(state.resources[e.id])
		"resource_picked":
			if _resources.has(e.id):
				_resources[e.id].visible = false
		"resource_dropped":
			if _resources.has(e.id):
				_resources[e.id].position = e.pos
				_resources[e.id].visible = true
		"resource_deposited":
			if _resources.has(e.id):
				_resources[e.id].queue_free()
				_resources.erase(e.id)
			if state.sites.has(e.site):
				_update_site(state.sites[e.site])
		"player_joined":
			if e.peer != me and not _avatars.has(e.peer):
				_add_avatar(state.players[e.peer])
		"player_left":
			if _avatars.has(e.peer):
				_avatars[e.peer].queue_free()
				_avatars.erase(e.peer)
	refresh_carrying(state, me)


func update_players(state: WorldState, me: int) -> void:
	for peer in _avatars:
		if state.players.has(peer):
			_avatars[peer].set_target(state.players[peer].pos, state.players[peer].yaw)


func refresh_carrying(state: WorldState, me: int) -> void:
	for peer in _avatars:
		if state.players.has(peer):
			_avatars[peer].set_carrying(state.players[peer].carrying != "")


# ------------------------------------------------------------------------------------------ builders

func _build_ground() -> void:
	var size := WorldState.WORLD_HALF_EXTENT * 2.0 + 20.0
	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(size, size)
	mesh.mesh = plane
	mesh.material_override = Palette.ground_material()
	_world_root.add_child(mesh)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	floor_shape.shape = WorldBoundaryShape3D.new()
	floor_body.add_child(floor_shape)
	_world_root.add_child(floor_body)
	var e := WorldState.WORLD_HALF_EXTENT
	for wall in [[Vector3(e + 0.5, 10, 0), Vector3(1, 20, 2 * e)], [Vector3(-e - 0.5, 10, 0), Vector3(1, 20, 2 * e)],
			[Vector3(0, 10, e + 0.5), Vector3(2 * e, 20, 1)], [Vector3(0, 10, -e - 0.5), Vector3(2 * e, 20, 1)]]:
		_world_root.add_child(_static_box(wall[0], wall[1], null))


func _build_obstacles(world_seed: int) -> void:
	for o in WorldGen.obstacles(world_seed):
		_world_root.add_child(_static_box(o.pos + Vector3(0, o.size.y * 0.5, 0), o.size, Palette.material(Palette.OBSTACLE)))


func _add_site(site: Dictionary) -> void:
	var root := Node3D.new()
	root.position = site.pos
	_world_root.add_child(root)
	var platform_size := Vector3(WorldGen.SITE_HALF_EXTENT * 2.0, PLATFORM_HEIGHT, WorldGen.SITE_HALF_EXTENT * 2.0)
	root.add_child(_static_box(Vector3(0, PLATFORM_HEIGHT * 0.5, 0), platform_size, Palette.material(Palette.PLATFORM)))
	var blocks := Node3D.new()
	root.add_child(blocks)
	var column := StaticBody3D.new()
	var column_shape := CollisionShape3D.new()
	column_shape.shape = BoxShape3D.new()
	column_shape.disabled = true
	column.add_child(column_shape)
	root.add_child(column)
	var label := Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 96
	label.pixel_size = 0.01
	label.outline_size = 12
	root.add_child(label)
	_sites[site.id] = {"blocks": blocks, "label": label, "shape": column_shape}
	_update_site(site)


## One placeholder block per deposited resource, stacked in 2x2 layers.
func _update_site(site: Dictionary) -> void:
	var nodes: Dictionary = _sites[site.id]
	var blocks: Node3D = nodes.blocks
	var count := int(site.deposited)
	while blocks.get_child_count() < count:
		var i := blocks.get_child_count()
		var layer := i / BLOCKS_PER_LAYER
		var slot := i % BLOCKS_PER_LAYER
		var offset := Vector3(-0.55 if slot % 2 == 0 else 0.55, 0, -0.55 if slot < 2 else 0.55)
		var block := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = BLOCK_SIZE
		block.mesh = mesh
		block.material_override = Palette.material(Palette.BLOCK)
		block.position = offset + Vector3(0, PLATFORM_HEIGHT + BLOCK_SIZE.y * (layer + 0.5), 0)
		blocks.add_child(block)
	var height := ceili(count / float(BLOCKS_PER_LAYER)) * BLOCK_SIZE.y
	var shape: CollisionShape3D = nodes.shape
	shape.disabled = height <= 0.0
	(shape.shape as BoxShape3D).size = Vector3(2.1, maxf(height, 0.01), 2.1)
	shape.position.y = PLATFORM_HEIGHT + height * 0.5
	var label: Label3D = nodes.label
	label.text = "STRUCTURE\n%d deposited" % count
	label.position.y = PLATFORM_HEIGHT + height + 1.6


func _add_resource(r: Dictionary) -> void:
	var node: Node3D
	if _resource_scene != null:
		node = _resource_scene.instantiate()
	else:
		node = Node3D.new()  # origin at the base, like the pipeline asset
		var box := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.5, 0.4, 0.5)
		box.mesh = mesh
		box.material_override = Palette.material(Palette.RESOURCE)
		box.position.y = 0.2
		node.add_child(box)
	node.name = "Resource_%s" % r.id
	node.position = r.pos
	node.visible = int(r.carrier) == 0
	_world_root.add_child(node)
	_resources[r.id] = node


func _add_avatar(p: Dictionary) -> void:
	var avatar := RemoteAvatar.new(p.name, p.pos, p.yaw)
	_world_root.add_child(avatar)
	_avatars[p.peer] = avatar


func _static_box(center: Vector3, size: Vector3, material: Material) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = center
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	if material != null:
		var mesh := MeshInstance3D.new()
		var box_mesh := BoxMesh.new()
		box_mesh.size = size
		mesh.mesh = box_mesh
		mesh.material_override = material
		body.add_child(mesh)
	return body
