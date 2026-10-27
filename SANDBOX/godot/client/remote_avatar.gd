## Another player's body: placeholder capsule + name tag, interpolated toward server snapshots.
extends Node3D

const Palette = preload("res://client/palette.gd")
const SMOOTHING := 12.0

var target_position := Vector3.ZERO
var target_yaw := 0.0
var _label: Label3D
var _carried: MeshInstance3D


func _init(player_name: String, pos: Vector3, yaw: float) -> void:
	position = pos
	rotation.y = yaw
	target_position = pos
	target_yaw = yaw
	var body := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	body.mesh = capsule
	body.position.y = 0.9
	body.material_override = Palette.material(Palette.AVATAR)
	add_child(body)
	var visor := MeshInstance3D.new()
	var visor_mesh := BoxMesh.new()
	visor_mesh.size = Vector3(0.5, 0.15, 0.2)
	visor.mesh = visor_mesh
	visor.position = Vector3(0, 1.55, -0.32)
	visor.material_override = Palette.material(Palette.VISOR)
	add_child(visor)
	_carried = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.4, 0.3, 0.4)
	_carried.mesh = box
	_carried.position = Vector3(0, 1.1, -0.55)
	_carried.material_override = Palette.material(Palette.RESOURCE)
	_carried.visible = false
	add_child(_carried)
	_label = Label3D.new()
	_label.text = player_name
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position.y = 2.15
	_label.font_size = 48
	_label.pixel_size = 0.006
	add_child(_label)


func set_target(pos: Vector3, yaw: float) -> void:
	target_position = pos
	target_yaw = yaw


func set_carrying(carrying: bool) -> void:
	_carried.visible = carrying


func _process(delta: float) -> void:
	var w := 1.0 - exp(-SMOOTHING * delta)
	position = position.lerp(target_position, w)
	rotation.y = lerp_angle(rotation.y, target_yaw, w)
