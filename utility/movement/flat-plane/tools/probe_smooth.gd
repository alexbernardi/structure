extends SceneTree

const GP = preload("res://animation/gait_params.gd")
const GM = preload("res://animation/gait_model.gd")


# Best-fit  c + a*cos(4 pi q) + b*sin(4 pi q)  and the residual relative to the fitted amplitude.
func _fit(ys: Array) -> Dictionary:
	var n := ys.size()
	var c := 0.0
	var a := 0.0
	var b := 0.0
	for i in n:
		var q := float(i) / n
		c += ys[i]
		a += ys[i] * cos(4.0 * PI * q)
		b += ys[i] * sin(4.0 * PI * q)
	c /= n
	a *= 2.0 / n
	b *= 2.0 / n
	var rss := 0.0
	for i in n:
		var q := float(i) / n
		var e: float = ys[i] - (c + a * cos(4.0 * PI * q) + b * sin(4.0 * PI * q))
		rss += e * e
	var amp := sqrt(a * a + b * b)
	return {"amp": amp, "rms": sqrt(rss / n), "ratio": sqrt(rss / n) / maxf(amp, 1e-9), "c": c}


func _initialize() -> void:
	var p = GP.create()
	var m = GM.new(p)
	for set in OS.get_cmdline_user_args():
		var kv := String(set).split("=")
		if kv.size() == 2:
			p.set_value(kv[0], float(kv[1]))
	for speed in [0.8, 1.2, 1.6, 2.0]:
		m.cycle = m.cycle_for(speed)
		var ys := []
		var assist := 0.0
		var series := {"thigh_l": [], "knee_l": [], "foot_l": [], "thigh_r": [], "knee_r": [], "foot_r": []}
		var n := 600
		for i in n:
			var pose: Dictionary = m.pose_at(float(i) / n)
			ys.append(pose.pelvis.y)
			assist = maxf(assist, pose.reach_assist)
			for k in series:
				series[k].append(pose[k])
		var f := _fit(ys)
		var msg := "v=%.1f hips: p-p %.1f mm, sine amp %.1f mm, residual %.1f %% of amp, assist %.1f mm   |" % [speed, 2000.0 * f.amp, 1000.0 * f.amp, 100.0 * f.ratio, 1000.0 * assist]
		# angular acceleration (second difference per cycle^2), worst and the 99th percentile ratio
		for k in ["knee_l", "thigh_l", "foot_l"]:
			var acc := []
			for i in n:
				var a0: float = series[k][(i + n - 1) % n]
				var a1: float = series[k][i]
				var a2: float = series[k][(i + 1) % n]
				acc.append(absf(a2 - 2.0 * a1 + a0) * n * n)
			var sorted := acc.duplicate()
			sorted.sort()
			var med: float = sorted[n / 2]
			var worst: float = sorted[n - 1]
			var at := acc.find(worst)
			msg += " %s accel median %.0f max %.0f at q=%.3f (x%.1f) |" % [k, med, worst, float(at) / n, worst / maxf(med, 1e-9)]
		print(msg)
	quit(0)
