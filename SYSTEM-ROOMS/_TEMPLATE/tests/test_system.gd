## Tests run in isolation: python TOOLS/cli/structure.py room test {{ROOM_NAME}}
## Assertions: t.ok(cond, msg), t.eq(actual, expected, msg), t.ne(a, b, msg), t.near(a, b, tol, msg), t.fail(msg).
extends RefCounted

const System = preload("../src/system.gd")


func test_example_clamps_into_range(t) -> void:
	t.eq(System.clamp_to_range(5.0, 0.0, 1.0), 1.0, "upper bound")
	t.eq(System.clamp_to_range(-5.0, 0.0, 1.0), 0.0, "lower bound")
	t.near(System.clamp_to_range(0.25, 0.0, 1.0), 0.25, 1e-6, "inside the range")
