## Traversal debug overlay (F10 / traversal.debug_overlay): what the vault perceived and planned, drawn in the world.
##   yellow  probe hits: face, top, back, and the expected landing point
##   cyan    planned collider path (the body)       magenta  planned visual root path (the animation)
##   white   takeoff point and travel direction     green    support-hand contact target (bright while bearing weight)
##   orange  actual velocity                        red      current root misalignment (visual root minus the body)
## Visual only; reads the action and never writes to it.
extends MeshInstance3D

const Planner = preload("res://traversal/vault_planner.gd")
const Clip = preload("res://traversal/vault_clip.gd")
const PATH_SAMPLES := 24

var action
var body
var _mesh := ImmediateMesh.new()


func _init() -> void:
	mesh = _mesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.no_depth_test = true
	material_override = material
	top_level = true


func setup(vault_action, character) -> void:
	action = vault_action
	body = character


func redraw(fraction: float) -> void:
	_mesh.clear_surfaces()
	if action == null or body == null:
		return
	_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var feet: Vector3 = body.get_global_transform_interpolated().origin
	var velocity: Vector3 = body.core.velocity
	_line(feet + Vector3.UP * 0.05, feet + Vector3.UP * 0.05 + velocity * 0.25, Color.ORANGE)
	var root: Vector3 = feet + action.offset(fraction)
	_line(feet, root, Color.RED)
	_cross(root, 0.06, Color.RED)
	var obstacle: Dictionary = action.obstacle
	var seen: bool = action.armed() or action.presenting
	if seen and not obstacle.is_empty():
		for key in ["face", "top", "back", "landing_point"]:
			if obstacle.has(key):
				_cross(obstacle[key], 0.08, Color.YELLOW)
	if action.presenting or action.active():
		var plan: Dictionary = action.plan
		_line(action.origin, action.origin + action.direction * 0.6, Color.WHITE)
		_cross(action.origin, 0.1, Color.WHITE)
		var previous_body := Vector3.ZERO
		var previous_root := Vector3.ZERO
		for i in PATH_SAMPLES + 1:
			var t := Clip.LENGTH * i / PATH_SAMPLES
			var along: float = Planner.travel(plan, minf(t, Clip.LANDING))
			var collider: Vector3 = action.origin + action.direction * along + Vector3.UP * Planner.collider_height(plan, minf(t, Clip.LANDING))
			var visual: Vector3 = action.origin + action.direction * along + Vector3.UP * Planner.visual_height(plan, minf(t, Clip.LANDING))
			if i > 0:
				_line(previous_body, collider, Color.CYAN)
				_line(previous_root, visual, Color.MAGENTA)
			previous_body = collider
			previous_root = visual
		var hand: Vector3 = action.to_world(plan.hand_point)
		var weight: float = Planner.hand_weight(plan, action.time)
		_cross(hand, 0.07, Color(0.2, 1.0, 0.3).lerp(Color(0.1, 0.3, 0.1), 1.0 - weight))
	_mesh.surface_end()


func _line(a: Vector3, b: Vector3, color: Color) -> void:
	_mesh.surface_set_color(color)
	_mesh.surface_add_vertex(a)
	_mesh.surface_set_color(color)
	_mesh.surface_add_vertex(b)


func _cross(p: Vector3, size: float, color: Color) -> void:
	for axis in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
		_line(p - axis * size, p + axis * size, color)
