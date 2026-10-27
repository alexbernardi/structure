## Benchmarks: python TOOLS/cli/structure.py room bench {{ROOM_NAME}}
## Record exactly the measured loop: b.record(name, ops, elapsed_usec). Targets live in room.json.
extends RefCounted

const System = preload("../src/system.gd")


func bench_example(b) -> void:
	var n := 100_000
	var acc := 0.0
	var t0 := Time.get_ticks_usec()
	for i in n:
		acc += System.clamp_to_range(float(i % 7), 1.0, 5.0)
	b.record("{{ROOM_NAME}}.example", n, Time.get_ticks_usec() - t0, {"checksum": acc})
