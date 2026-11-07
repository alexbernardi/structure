## Cost of the spring library (Movement Lab 2.0 phase 1). Compare with bench_baseline.gd: these are what springs ADD.
extends RefCounted

const Springs = preload("res://animation/springs.gd")
const Math = preload("res://animation/spring_math.gd")
const DT := 1.0 / 120.0


func bench_scalar_spring_step(b) -> void:
	var sp := Springs.Scalar.new(3.0, 0.6, 0.0)
	sp.set_target(1.0)
	var n := 300000
	var t0 := Time.get_ticks_usec()
	for i in n:
		sp.step(DT)
		if i % 100 == 0:
			sp.set_target(sin(float(i)))
	b.record("Scalar.step (cached coefficients)", n, Time.get_ticks_usec() - t0)


func bench_vector_spring_step(b) -> void:
	var sp := Springs.Vector.new(3.0, 0.6)
	sp.set_target(Vector3(1, 2, 3))
	var n := 300000
	var t0 := Time.get_ticks_usec()
	for i in n:
		sp.step(DT)
	b.record("Vector.step", n, Time.get_ticks_usec() - t0)


func bench_rotation_spring_step(b) -> void:
	var sp := Springs.Rotation.new(3.0, 0.6)
	sp.set_target(Quaternion(Vector3(1, 2, 3).normalized(), 1.5))
	var n := 200000
	var t0 := Time.get_ticks_usec()
	for i in n:
		sp.step(DT)
	b.record("Rotation.step (log + exp + propagator)", n, Time.get_ticks_usec() - t0)


func bench_spring_with_changing_timestep(b) -> void:
	# worst case for the cache: a different dt every call forces the closed form to be re-evaluated each time
	var sp := Springs.Scalar.new(3.0, 0.6, 0.0)
	sp.set_target(1.0)
	var n := 200000
	var t0 := Time.get_ticks_usec()
	for i in n:
		sp.step(0.004 + float(i % 7) * 0.001)
	b.record("Scalar.step (dt changes every call: no cache hit)", n, Time.get_ticks_usec() - t0)


func bench_propagator(b) -> void:
	var n := 200000
	var t0 := Time.get_ticks_usec()
	for i in n:
		Math.propagator(3.0, 0.2 + float(i % 3) * 0.8, DT)   # under, critical-ish, over
	b.record("propagator (closed form, all regimes)", n, Time.get_ticks_usec() - t0)
