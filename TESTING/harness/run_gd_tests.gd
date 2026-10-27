## Zero-dependency GDScript test, benchmark and smoke runner shared by the sandbox and every system room.
##
##   godot --headless --path <project> --script <abs>/TESTING/harness/run_gd_tests.gd -- \
##         [--mode=test|bench|smoke] [--dir=res://tests]... [--filter=substr] [--report=<abs .json>]
##
## Test files  : test_*.gd  (extends RefCounted); methods `func test_<name>(t) -> void`.
## Bench files : bench_*.gd (extends RefCounted); methods `func bench_<name>(b) -> void`.
## Optional per-method hooks: before_each(), after_each().
## A test FAILS if an assertion fails OR the engine reports an error while it runs
## (captured through the Logger API), unless the test declared it with t.expect_engine_errors(n).
## Exit code: 0 = all passed, 1 = failures, 2 = harness problem (nothing found, bad arguments).
extends SceneTree


class Ctx:
	extends RefCounted
	var failures: Array[String] = []
	var checks := 0
	var expected_engine_errors := 0

	func ok(condition: bool, message := "expected condition to be true") -> bool:
		checks += 1
		if not condition:
			failures.append(message)
		return condition

	func eq(actual: Variant, expected: Variant, message := "values differ") -> bool:
		checks += 1
		if not Ctx.same(actual, expected):
			failures.append("%s: expected <%s> got <%s>" % [message, Ctx.show(expected), Ctx.show(actual)])
			return false
		return true

	func ne(actual: Variant, unexpected: Variant, message := "values should differ") -> bool:
		checks += 1
		if Ctx.same(actual, unexpected):
			failures.append("%s: got <%s>" % [message, Ctx.show(actual)])
			return false
		return true

	func near(actual: Variant, expected: Variant, tolerance: float, message := "values not within tolerance") -> bool:
		checks += 1
		var diff := INF
		if actual is Vector3 and expected is Vector3:
			diff = (actual as Vector3).distance_to(expected)
		elif Ctx.is_num(actual) and Ctx.is_num(expected):
			diff = absf(float(actual) - float(expected))
		if diff > tolerance:
			failures.append("%s: expected <%s> +/- %s got <%s>" % [message, Ctx.show(expected), tolerance, Ctx.show(actual)])
			return false
		return true

	func fail(message: String) -> void:
		checks += 1
		failures.append(message)

	## Declare engine errors this test intentionally provokes (e.g. parsing a corrupt file).
	func expect_engine_errors(count: int) -> void:
		expected_engine_errors += count

	static func is_num(v: Variant) -> bool:
		return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT

	static func is_str(v: Variant) -> bool:
		return typeof(v) == TYPE_STRING or typeof(v) == TYPE_STRING_NAME

	static func same(a: Variant, b: Variant) -> bool:
		if typeof(a) == typeof(b):
			return a == b
		if is_num(a) and is_num(b):
			return float(a) == float(b)
		if is_str(a) and is_str(b):
			return String(a) == String(b)
		return false

	static func show(v: Variant) -> String:
		return "%s:%s" % [type_string(typeof(v)), var_to_str(v).replace("\n", " ")]


class Bench:
	extends RefCounted
	var results: Array[Dictionary] = []

	## Record a measured loop. `elapsed_usec` must cover exactly `ops` operations.
	func record(name: String, ops: int, elapsed_usec: int, extra := {}) -> void:
		var us_per_op := float(elapsed_usec) / maxf(1.0, float(ops))
		var entry := {"name": name, "ops": ops, "elapsed_usec": elapsed_usec,
			"us_per_op": us_per_op, "ops_per_sec": 1_000_000.0 / maxf(us_per_op, 0.000001)}
		entry.merge(extra)
		results.append(entry)


class ErrorCatcher:
	extends Logger
	var _mutex := Mutex.new()
	var _errors: Array[String] = []

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		_mutex.lock()
		_errors.append("%s:%d %s() %s %s" % [file, line, function, code, rationale])
		_mutex.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass

	func take() -> Array[String]:
		_mutex.lock()
		var out := _errors.duplicate()
		_errors.clear()
		_mutex.unlock()
		return out


var _args := {}
var _dirs: Array[String] = []
var _catcher := ErrorCatcher.new()


func _initialize() -> void:
	_parse_args()
	OS.add_logger(_catcher)
	var mode: String = _args.get("mode", "test")
	var code := 2
	match mode:
		"test":
			code = await _run_methods("test_", "test")
		"bench":
			code = await _run_methods("bench_", "bench")
		"smoke":
			code = _run_smoke()
		_:
			printerr("Unknown --mode=%s" % mode)
	OS.remove_logger(_catcher)
	quit(code)


func _parse_args() -> void:
	for raw in OS.get_cmdline_user_args():
		var arg := String(raw)
		if not arg.begins_with("--"):
			continue
		var parts := arg.substr(2).split("=", true, 1)
		var key := parts[0]
		var value := parts[1] if parts.size() > 1 else "true"
		if key == "dir":
			_dirs.append(value)
		else:
			_args[key] = value
	if _dirs.is_empty():
		_dirs.append("res://tests")


func _collect(dir_path: String, prefix: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		var full := dir_path.path_join(name)
		if dir.current_is_dir():
			if not name.begins_with("."):
				_collect(full, prefix, out)
		elif name.begins_with(prefix) and name.ends_with(".gd"):
			out.append(full)
		name = dir.get_next()
	dir.list_dir_end()


func _run_methods(prefix: String, mode: String) -> int:
	var files: Array[String] = []
	for d in _dirs:
		_collect(d, prefix, files)
	files.sort()
	var filter: String = _args.get("filter", "")
	var report := {"mode": mode, "project": ProjectSettings.get_setting("application/config/name", ""),
		"engine": Engine.get_version_info().get("string", ""), "dirs": _dirs, "results": [], "benchmarks": []}
	var passed := 0
	var failed := 0
	var started_all := Time.get_ticks_msec()
	for path in files:
		var script: GDScript = load(path)
		var load_errors := _catcher.take()
		if script == null or not script.can_instantiate():
			failed += 1
			print("FAIL %s (could not load) %s" % [path, load_errors])
			report.results.append({"file": path, "name": "<load>", "ok": false, "failures": ["load failed"], "errors": load_errors})
			continue
		var methods: Array[String] = []
		for m in script.get_script_method_list():
			var mname := String(m.name)
			if mname.begins_with(prefix) and not methods.has(mname):
				methods.append(mname)
		for mname in methods:
			if filter != "" and not (path + "::" + mname).contains(filter):
				continue
			var obj: Object = script.new()
			var ctx: Variant = Ctx.new() if mode == "test" else Bench.new()
			var t0 := Time.get_ticks_usec()
			if obj.has_method("before_each"):
				await obj.call("before_each")
			await obj.callv(mname, [ctx])
			if obj.has_method("after_each"):
				await obj.call("after_each")
			var ms := (Time.get_ticks_usec() - t0) / 1000.0
			var errors := _catcher.take()
			if obj is Node:
				obj.free()
			var failures: Array[String] = []
			if mode == "test":
				failures = ctx.failures.duplicate()
				var allowed: int = ctx.expected_engine_errors
				if errors.size() > allowed:
					failures.append("engine reported %d unexpected error(s)" % (errors.size() - allowed))
				elif errors.size() < allowed:
					failures.append("expected %d engine error(s), saw %d" % [allowed, errors.size()])
			elif not errors.is_empty():
				failures.append("engine reported errors during benchmark")
			var ok := failures.is_empty()
			if ok:
				passed += 1
			else:
				failed += 1
			print("%s %s::%s (%.1f ms)" % ["PASS" if ok else "FAIL", path.get_file(), mname, ms])
			for f in failures:
				print("    - ", f)
			if not ok:
				for e in errors:
					print("    ! ", e)
			report.results.append({"file": path, "name": mname, "ok": ok, "ms": ms, "failures": failures, "errors": errors})
			if mode == "bench":
				for r in ctx.results:
					r["file"] = path
					report.benchmarks.append(r)
					print("    %-40s %12d ops  %10.4f us/op  %14.0f ops/s" % [r.name, r.ops, r.us_per_op, r.ops_per_sec])
	report["passed"] = passed
	report["failed"] = failed
	report["elapsed_ms"] = Time.get_ticks_msec() - started_all
	_write_report(report)
	print("%s: %d passed, %d failed (%d files, %d ms)" % [mode.to_upper(), passed, failed, files.size(), report.elapsed_ms])
	if passed + failed == 0:
		printerr("No %s methods found in %s" % [prefix, _dirs])
		return 2
	return 0 if failed == 0 else 1


## Loads every script and scene under the given dirs; catches parse errors and broken references.
func _run_smoke() -> int:
	var files: Array[String] = []
	for d in _dirs:
		_collect_ext(d, files)
	files.sort()
	var failed: Array[Dictionary] = []
	for path in files:
		var res := load(path)
		var errors := _catcher.take()
		if res is PackedScene:
			var inst := (res as PackedScene).instantiate()
			if inst == null:
				errors.append("instantiate() returned null")
			else:
				inst.free()
			errors.append_array(_catcher.take())
		if res == null or not errors.is_empty():
			failed.append({"file": path, "errors": errors})
			print("FAIL ", path)
			for e in errors:
				print("    ! ", e)
	_write_report({"mode": "smoke", "checked": files.size(), "failed": failed})
	print("SMOKE: %d resources checked, %d failed" % [files.size(), failed.size()])
	if files.is_empty():
		return 2
	return 0 if failed.is_empty() else 1


func _collect_ext(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		var full := dir_path.path_join(name)
		if dir.current_is_dir():
			if not name.begins_with("."):
				_collect_ext(full, out)
		elif name.ends_with(".gd") or name.ends_with(".tscn"):
			out.append(full)
		name = dir.get_next()
	dir.list_dir_end()


func _write_report(report: Dictionary) -> void:
	var path: String = _args.get("report", "")
	if path == "":
		return
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(report, "  "))
		f.close()
