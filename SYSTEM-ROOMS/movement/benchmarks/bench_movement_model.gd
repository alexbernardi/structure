extends RefCounted

const Model = preload("../src/movement_model.gd")
const DT := 1.0 / 60.0


func bench_single_step(b) -> void:
	var p := Model.default_params()
	var v := Vector3.ZERO
	var wish := Vector3(0.6, 0, -0.8)
	var n := 200_000
	var t0 := Time.get_ticks_usec()
	for i in n:
		v = Model.step(v, wish, true, (i & 63) == 0, DT, p)
	b.record("movement.step", n, Time.get_ticks_usec() - t0)


## Models a server validating/simulating 64 players for one 30 Hz tick.
func bench_tick_64_players(b) -> void:
	var p := Model.default_params()
	var players := 64
	var vels: Array[Vector3] = []
	vels.resize(players)
	vels.fill(Vector3.ZERO)
	var ticks := 2_000
	var t0 := Time.get_ticks_usec()
	for tick in ticks:
		for i in players:
			vels[i] = Model.step(vels[i], Vector3(sin(i), 0, cos(i)), true, false, 1.0 / 30.0, p)
	b.record("movement.tick_64_players", ticks, Time.get_ticks_usec() - t0, {"players": players})
