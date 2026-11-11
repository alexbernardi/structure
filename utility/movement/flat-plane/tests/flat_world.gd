## Tiny deterministic world for testing the movement core without the physics server: a flat floor at y = 0.
extends RefCounted

const Core = preload("res://systems/movement_core/movement/movement_core.gd")

const DT := 1.0 / 120.0

var core: Core = Core.new()
var pos := Vector3.ZERO
var floor_normal := Vector3.UP
var log_speed: Array[float] = []


func input(move := Vector2.ZERO, extra := {}) -> Dictionary:
	var d := {"move": move, "yaw": 0.0, "jump_pressed": false, "jump_held": false, "sprint": false, "crouch": false}
	d.merge(extra, true)
	return d


func tick(inp: Dictionary) -> void:
	var on_floor := pos.y <= 0.0001 and core.velocity.y <= 0.0
	core.step(inp, {"grounded": on_floor, "normal": floor_normal, "can_stand": true}, DT)
	pos += core.velocity * DT
	if pos.y < 0.0:
		pos.y = 0.0
	log_speed.append(core.horizontal_speed())


func run(inp: Dictionary, seconds: float) -> void:
	for i in int(round(seconds / DT)):
		tick(inp)


## Highest point reached while running `inp` for `seconds`.
func peak_height(inp: Dictionary, seconds: float) -> float:
	var top := pos.y
	for i in int(round(seconds / DT)):
		tick(inp)
		top = maxf(top, pos.y)
	return top
