## Lightweight local performance instrumentation (no external services).
## ServerMetrics: tick duration, CPU %, memory, players, entities, network bytes.
## FrameStats: client FPS / frame-time distribution.
extends RefCounted


class ServerMetrics:
	extends RefCounted
	var _ticks := PackedInt64Array()
	var _process_ms := 0.0
	var _process_samples := 0
	var _last_cpu_ticks := -1
	var _last_wall_usec := 0
	var _started_usec := Time.get_ticks_usec()

	func record_tick(usec: int) -> void:
		_ticks.append(usec)
		_process_ms += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		_process_samples += 1

	## Returns the metrics for the interval since the previous call and resets the interval.
	func collect(players: int, entities: int, net: Dictionary) -> Dictionary:
		var sorted := _ticks.duplicate()
		sorted.sort()
		var count := sorted.size()
		var total := 0
		for v in sorted:
			total += v
		var out := {
			"uptime_s": (Time.get_ticks_usec() - _started_usec) / 1_000_000.0,
			"ticks": count,
			"tick_avg_ms": (total / 1000.0 / count) if count > 0 else 0.0,
			"tick_p95_ms": (sorted[mini(count - 1, int(count * 0.95))] / 1000.0) if count > 0 else 0.0,
			"tick_max_ms": (sorted[count - 1] / 1000.0) if count > 0 else 0.0,
			"frame_process_avg_ms": (_process_ms / _process_samples) if _process_samples > 0 else 0.0,
			"cpu_pct": _cpu_pct(),
			"mem_static_mb": OS.get_static_memory_usage() / 1048576.0,
			"rss_mb": _rss_mb(),
			"players": players,
			"entities": entities,
			"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
			"net_in_bps": net.get("in_bps", 0.0),
			"net_out_bps": net.get("out_bps", 0.0),
		}
		_ticks.clear()
		_process_ms = 0.0
		_process_samples = 0
		return out

	## Process CPU utilisation (100 = one full core) from /proc on Linux; null elsewhere.
	func _cpu_pct() -> Variant:
		var line := _read_first_line("/proc/self/stat")
		if line == "":
			return null
		var fields := line.substr(line.rfind(")") + 2).split(" ")
		if fields.size() < 13:
			return null
		var cpu_ticks := fields[11].to_int() + fields[12].to_int()  # utime + stime (clock ticks)
		var now := Time.get_ticks_usec()
		var result: Variant = null
		if _last_cpu_ticks >= 0 and now > _last_wall_usec:
			var cpu_s := (cpu_ticks - _last_cpu_ticks) / 100.0  # CLK_TCK is 100 on Linux
			result = 100.0 * cpu_s / ((now - _last_wall_usec) / 1_000_000.0)
		_last_cpu_ticks = cpu_ticks
		_last_wall_usec = now
		return result

	func _rss_mb() -> Variant:
		var f := FileAccess.open("/proc/self/status", FileAccess.READ)
		if f == null:
			return null
		while not f.eof_reached():
			var line := f.get_line()
			if line.begins_with("VmRSS:"):
				return line.split(":")[1].strip_edges().split(" ")[0].to_int() / 1024.0
			if line == "":
				break
		return null

	func _read_first_line(path: String) -> String:
		var f := FileAccess.open(path, FileAccess.READ)
		return f.get_line() if f != null else ""


class FrameStats:
	extends RefCounted
	var _frame_ms := PackedFloat32Array()

	func record(delta: float) -> void:
		_frame_ms.append(delta * 1000.0)

	func summary() -> Dictionary:
		var sorted := _frame_ms.duplicate()
		sorted.sort()
		var n := sorted.size()
		if n == 0:
			return {"frames": 0}
		var total := 0.0
		for v in sorted:
			total += v
		var avg := total / n
		return {
			"frames": n,
			"fps_avg": 1000.0 / avg,
			"frame_avg_ms": avg,
			"frame_p50_ms": sorted[int(n * 0.5)],
			"frame_p99_ms": sorted[mini(n - 1, int(n * 0.99))],
			"frame_max_ms": sorted[n - 1],
		}
