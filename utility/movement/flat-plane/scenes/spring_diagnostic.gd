## Spring diagnostic (Movement Lab 2.0, Phase 1 checkpoint). Drives the analytic springs with a target you choose and
## plots target, response, velocity and the measured overshoot, next to the theory.
##   godot --path utility/movement/flat-plane res://scenes/spring_diagnostic.tscn
## Options after `--`: --screenshot=<abs.png>  --quit-after=<seconds>  --no-window-state  --preset=under|critical|over
extends Control

const Springs = preload("res://animation/springs.gd")
const Math = preload("res://animation/spring_math.gd")
const WindowState = preload("res://scenes/window_state.gd")

const WINDOW_SEC := 6.0
const MAX_SAMPLES := 6000
const MODES := ["Square wave", "Manual (Space / click)", "Sine", "Ramp (moving target)", "Random steps"]
const TICKS := [["240 Hz", 240.0], ["120 Hz", 120.0], ["60 Hz", 60.0], ["30 Hz", 30.0], ["15 Hz", 15.0], ["jittery 8-60 ms", 0.0]]
const C_TARGET := Color(0.95, 0.95, 1.0)
const C_RESPONSE := Color(0.30, 0.85, 1.0)
const C_VELOCITY := Color(1.0, 0.65, 0.25)
const C_NAIVE := Color(1.0, 0.30, 0.30)
const C_UNDER := Color(0.85, 0.45, 1.0)
const C_CRIT := Color(0.40, 0.95, 0.45)
const C_OVER := Color(1.0, 0.90, 0.35)

var spring = Springs.Scalar.new(2.0, 0.3, 0.0)
var naive = Springs.NaiveEuler.new(2.0, 0.3, 0.0)
var regimes := {"under": Springs.Scalar.new(2.0, 0.25, 0.0), "crit": Springs.Scalar.new(2.0, 1.0, 0.0), "over": Springs.Scalar.new(2.0, 3.0, 0.0)}
var rot_spring = Springs.Rotation.new(2.0, 0.3)

# settings (also read by tests)
var frequency := 2.0
var damping := 0.3
var amplitude := 1.0
var mode := 0
var period := 2.0
var feed_forward := true
var tick_index := 2
var show_regimes := false
var show_naive := false
var use_limits := false
var paused := false

var time := 0.0
var target_value := 1.0
var target_speed := 0.0
var samples: Array[Dictionary] = []   # {t, target, x, v, naive, under, crit, over}
var measure := {}                      # step response being measured now
var last_measure := {}                 # the last COMPLETED measurement (what the readout shows)
var rotation_goal_deg := 0.0

var _args := {}
var _acc := 0.0
var _frames := 0
var _next_change := 0.0
var _rng := RandomNumberGenerator.new()
var _plot: Control
var _dial: Control
var _readout: RichTextLabel
var _sliders := {}
var _updaters := {}
var _mode_opt: OptionButton
var _tick_opt: OptionButton
var _checks := {}
var _rot_goals := [170.0, -170.0, 90.0, 0.0, -90.0, 179.0]
var _rot_index := 0
var options := {}


func _ready() -> void:
	for raw in OS.get_cmdline_user_args():
		var a := String(raw)
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			_args[kv[0]] = kv[1] if kv.size() > 1 else "true"
	_args.merge(options, true)
	_rng.seed = 12345
	_build_ui()
	if _args.has("tick"):
		tick_index = clampi(int(_args.tick), 0, TICKS.size() - 1)
		_tick_opt.select(tick_index)
	show_regimes = _args.has("regimes")
	show_naive = _args.has("naive")
	_checks.regimes.button_pressed = show_regimes
	_checks.naive.button_pressed = show_naive
	match String(_args.get("preset", "")):
		"under":
			_apply_preset(0.25)
		"critical":
			_apply_preset(1.0)
		"over":
			_apply_preset(3.0)
	_configure()
	if DisplayServer.get_name() != "headless" and not _args.has("no-window-state"):
		var ws := WindowState.new()
		add_child(ws)
		ws.attach(get_window(), "center", "user://window_state_springs.json")
	_next_change = 0.0
	if _args.has("prerun"):   # fill the plot before the first frame (screenshots, tests)
		for i in int(float(_args.prerun) * 60.0):
			advance(1.0 / 60.0)


# ------------------------------------------------------------------ simulation

func _configure() -> void:
	for s in [spring, naive]:
		s.frequency_hz = frequency
		s.damping_ratio = damping
	spring.amplitude = amplitude
	for key in regimes:
		regimes[key].frequency_hz = frequency
		regimes[key].amplitude = amplitude
	regimes.under.damping_ratio = 0.25
	regimes.crit.damping_ratio = 1.0
	regimes.over.damping_ratio = 3.0
	rot_spring.frequency_hz = frequency
	rot_spring.damping_ratio = damping
	spring.min_value = -0.6 if use_limits else -INF
	spring.max_value = 0.6 if use_limits else INF
	_update_readout()


func current_tick() -> float:
	return float(TICKS[tick_index][1])


## Advances the whole experiment by `seconds` of wall time using the selected tick rate.
func advance(seconds: float) -> void:
	_acc += seconds
	var hz := current_tick()
	var guard := 0
	while guard < 20000:
		var dt := 1.0 / hz if hz > 0.0 else _rng.randf_range(0.008, 0.06)
		if _acc < dt:
			break
		_acc -= dt
		_tick(dt)
		guard += 1


func _tick(dt: float) -> void:
	time += dt
	_drive_target(dt)
	spring.step(dt)
	naive.step(dt)
	for key in regimes:
		regimes[key].step(dt)
	rot_spring.step(dt)
	var s := {"t": time, "target": spring.effective_target(), "x": spring.x, "v": spring.v, "naive": naive.x,
		"under": regimes.under.x, "crit": regimes.crit.x, "over": regimes.over.x}
	samples.append(s)
	if samples.size() > MAX_SAMPLES or float(samples[0].t) < time - WINDOW_SEC - 1.0:
		while samples.size() > 1 and float(samples[0].t) < time - WINDOW_SEC - 1.0:
			samples.pop_front()
	_track(s)


func _set_target(g: float, q: float) -> void:
	var before: float = spring.target
	var q_used := q if feed_forward else 0.0
	spring.set_target(g, q_used)
	naive.target = g * amplitude
	naive.target_velocity = q_used * amplitude
	for key in regimes:
		regimes[key].set_target(g, q_used)
	if absf(g - before) > 0.5 and absf(q) < 1e-9:
		_begin_measure(spring.x, g * amplitude)


func _drive_target(dt: float) -> void:
	match mode:
		0:   # square wave
			if time >= _next_change:
				target_value = -target_value if time > 0.0 else 1.0
				_set_target(target_value, 0.0)
				_next_change = time + period
		1:   # manual: target changes only on input
			if time < dt * 1.5 and _next_change == 0.0:
				_set_target(target_value, 0.0)
				_next_change = INF
		2:   # sine: the target and its true velocity
			var w := TAU / period
			_set_target(sin(w * time), w * cos(w * time))
		3:   # ramp: moves at constant velocity and bounces
			if time >= _next_change:
				target_speed = 1.5 if target_speed <= 0.0 else -1.5
				_next_change = time + period
			_set_target(spring.target, target_speed)
		4:   # random steps
			if time >= _next_change:
				target_value = _rng.randf_range(-1.0, 1.0)
				_set_target(target_value, 0.0)
				_next_change = time + _rng.randf_range(0.6, period)
	# the rot_spring dial hops between goals on the square-wave clock, always taking the short way
	if time >= rotation_goal_deg_next():
		_rot_index = (_rot_index + 1) % _rot_goals.size()
		rotation_goal_deg = _rot_goals[_rot_index]
		rot_spring.set_target(Quaternion(Vector3.UP, deg_to_rad(rotation_goal_deg)))
		_rot_next = time + maxf(period, 1.5)


var _rot_next := 0.0


func rotation_goal_deg_next() -> float:
	return _rot_next


func manual_flip() -> void:
	if mode == 1:
		target_value = -target_value if absf(target_value) > 0.0 else 1.0
		_set_target(target_value, 0.0)


# ------------------------------------------------------------------ step response tracking

func _begin_measure(from: float, to: float) -> void:
	if not measure.is_empty() and time - measure.t0 > 0.3:
		last_measure = measure.duplicate()   # freeze the previous step's numbers before starting the next
		last_measure["done"] = true
	measure = {"from": from, "to": to, "peak": from, "peak_t": 0.0, "t0": time, "last_out": time, "done": false}


func _track(s: Dictionary) -> void:
	if measure.is_empty() or measure.done:
		return
	var span: float = measure.to - measure.from
	if absf(span) < 1e-9:
		return
	var progress: float = (float(s.x) - measure.from) / span   # 1.0 = on the goal
	if progress > (measure.peak - measure.from) / span:
		measure.peak = s.x
		measure.peak_t = float(s.t) - measure.t0
	if absf(1.0 - progress) > 0.02:
		measure.last_out = s.t
	if time - measure.t0 > 12.0:
		_finish_measure()


func _finish_measure() -> void:
	measure["done"] = true


func shown_measure() -> Dictionary:
	return last_measure if not last_measure.is_empty() else measure


func measured_overshoot_pct() -> float:
	var m := shown_measure()
	if m.is_empty():
		return NAN
	var span: float = m.to - m.from
	return maxf(0.0, ((m.peak - m.from) / span - 1.0) * 100.0)


func measured_settle_time() -> float:
	var m := shown_measure()
	return m.last_out - m.t0 if not m.is_empty() else NAN


func theory_overshoot_pct() -> float:
	return Math.overshoot_fraction(damping) * 100.0


# ------------------------------------------------------------------ settings

func set_frequency(f: float) -> void:
	frequency = f
	_configure()


func set_damping(z: float) -> void:
	damping = z
	_configure()


func _apply_preset(z: float) -> void:
	damping = z
	if _sliders.has("damping"):
		_sliders.damping.set_value_no_signal(z)
		_updaters.damping.call(z)
	_configure()


func _process(delta: float) -> void:
	_frames += 1
	if not paused:
		advance(delta)
	_plot.queue_redraw()
	_dial.queue_redraw()
	if _frames % 6 == 0:
		_update_readout()
	if _args.has("screenshot") and _frames == int(_args.get("screenshot-frame", 240)):
		get_viewport().get_texture().get_image().save_png(String(_args.screenshot))
		get_tree().quit()
	if _args.has("quit-after") and Time.get_ticks_msec() / 1000.0 > float(_args["quit-after"]):
		get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		manual_flip()


# ------------------------------------------------------------------ UI

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.10, 0.11, 0.14)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	margin.add_child(row)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 8)
	row.add_child(left)
	_plot = Control.new()
	_plot.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_plot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_plot.custom_minimum_size = Vector2(700, 420)
	_plot.draw.connect(_draw_plot)
	left.add_child(_plot)
	_readout = RichTextLabel.new()
	_readout.bbcode_enabled = true
	_readout.fit_content = true
	_readout.scroll_active = false
	_readout.custom_minimum_size = Vector2(0, 118)
	left.add_child(_readout)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(350, 0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	row.add_child(scroll)
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(330, 0)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 6)
	scroll.add_child(right)
	_slider(right, "frequency", "Natural frequency", 0.2, 12.0, 0.05, frequency, "Hz", func(v: float) -> void: set_frequency(v))
	_slider(right, "damping", "Damping ratio", 0.0, 4.0, 0.01, damping, "", func(v: float) -> void: set_damping(v))
	var presets := HBoxContainer.new()
	right.add_child(presets)
	presets.add_child(_button("Underdamped 0.25", func() -> void: _apply_preset(0.25)))
	presets.add_child(_button("Critical 1.0", func() -> void: _apply_preset(1.0)))
	presets.add_child(_button("Over 3.0", func() -> void: _apply_preset(3.0)))
	_slider(right, "amplitude", "Response amplitude", 0.0, 2.0, 0.05, amplitude, "x", func(v: float) -> void:
		amplitude = v
		_configure())
	right.add_child(_label("Target"))
	_mode_opt = OptionButton.new()
	for m in MODES:
		_mode_opt.add_item(m)
	_mode_opt.item_selected.connect(func(i: int) -> void:
		mode = i
		_next_change = 0.0
		_set_target(1.0 if i != 3 else spring.target, 0.0))
	right.add_child(_mode_opt)
	_slider(right, "period", "Period / hold time", 0.5, 6.0, 0.1, period, "s", func(v: float) -> void: period = v)
	_check(right, "ff", "Feed target velocity forward", feed_forward, func(on: bool) -> void: feed_forward = on)
	right.add_child(_label("Tick rate (springs are exact at every rate)"))
	_tick_opt = OptionButton.new()
	for t in TICKS:
		_tick_opt.add_item(t[0])
	_tick_opt.select(tick_index)
	_tick_opt.item_selected.connect(func(i: int) -> void: tick_index = i)
	right.add_child(_tick_opt)
	_check(right, "regimes", "Compare under / critical / over", show_regimes, func(on: bool) -> void: show_regimes = on)
	_check(right, "naive", "Show naive Euler spring (red)", show_naive, func(on: bool) -> void: show_naive = on)
	_check(right, "limits", "Output limits +-0.6", use_limits, func(on: bool) -> void:
		use_limits = on
		_configure())
	var btns := HBoxContainer.new()
	right.add_child(btns)
	btns.add_child(_button("Pause", func() -> void: paused = not paused))
	btns.add_child(_button("Clear", func() -> void: clear()))
	btns.add_child(_button("Teleport x -> 0", func() -> void: teleport()))
	var dial_title := _label("Rotation spring: the actual arrow always takes the short way round the goal arrow")
	dial_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(dial_title)
	_dial = Control.new()
	_dial.custom_minimum_size = Vector2(330, 150)
	_dial.draw.connect(_draw_dial)
	right.add_child(_dial)


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.modulate = Color(0.75, 0.78, 0.88)
	return l


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	return b


func _slider(parent: Control, key: String, text: String, lo: float, hi: float, step: float, value: float, unit: String, cb: Callable) -> void:
	var l := _label("")
	parent.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(0, 22)
	var update := func(v: float) -> void: l.text = "%s: %s %s" % [text, str(snappedf(v, step)), unit]
	s.value_changed.connect(func(v: float) -> void:
		update.call(v)
		cb.call(v))
	update.call(value)
	parent.add_child(s)
	_sliders[key] = s
	_updaters[key] = update


func _check(parent: Control, key: String, text: String, value: bool, cb: Callable) -> void:
	var c := CheckBox.new()
	c.text = text
	c.button_pressed = value
	c.toggled.connect(cb)
	parent.add_child(c)
	_checks[key] = c


func clear() -> void:
	samples.clear()
	measure = {}
	last_measure = {}


func teleport() -> void:
	spring.teleport(0.0)
	naive.x = 0.0
	naive.v = 0.0
	for key in regimes:
		regimes[key].teleport(0.0)
	rot_spring.teleport(Quaternion.IDENTITY)


# ------------------------------------------------------------------ readout

func _update_readout() -> void:
	if _readout == null:
		return
	var w := TAU * frequency
	var regime := Math.regime_name(damping)
	var col: String = {"underdamped": "#d98cff", "critically damped": "#66f27a", "overdamped": "#ffe65a"}[regime]
	var text := "[b][color=%s]%s[/color][/b]   f = %.2f Hz   w = %.2f rad/s   zeta = %.2f   amplitude x%.2f\n" % [col, regime.to_upper(), frequency, w, damping, amplitude]
	text += "Theory (step from rest): overshoot [b]%.1f %%[/b]" % theory_overshoot_pct()
	var pk := Math.peak_time(frequency, damping)
	text += "   first peak at [b]%s[/b]\n" % ("%.3f s" % pk if is_finite(pk) else "- (no overshoot)")
	var m := shown_measure()
	if m.is_empty():
		text += "Measured: waiting for a target step ..."
	else:
		var span: float = m.to - m.from
		var overshot: bool = (m.peak - m.to) * signf(span) > 1e-9
		text += "Measured (%s step): overshoot [b]%.1f %%[/b]   peak at %s   settled to 2 %% after [b]%.3f s[/b]" % ["last completed" if m.get("done", false) else "current, still moving", measured_overshoot_pct(), ("%.3f s" % m.peak_t) if overshot else "-", measured_settle_time()]
	text += "\nx = %+.4f   v = %+.3f   error = %+.4f   energy = %.4f   rejected inputs: %d" % [spring.x, spring.v, spring.displacement(), spring.energy(), spring.rejected_inputs]
	if show_naive:
		var bad := absf(naive.x) > 50.0 or is_nan(naive.x) or is_inf(naive.x)
		text += "\n[color=#ff6666]naive Euler x = %s %s[/color]" % [("%.3f" % naive.x) if not bad else "EXPLODED", "(unstable at this tick rate)" if bad else ""]
	_readout.text = text


# ------------------------------------------------------------------ drawing

func _draw_plot() -> void:
	var size := _plot.size
	var pad := Vector4(46.0, 10.0, 10.0, 24.0)   # left, top, right, bottom
	var area := Rect2(pad.x, pad.y, size.x - pad.x - pad.z, size.y - pad.y - pad.w)
	_plot.draw_rect(Rect2(Vector2.ZERO, size), Color(0.06, 0.07, 0.09), true)
	if samples.is_empty():
		return
	var t1 := time
	var t0 := t1 - WINDOW_SEC
	var lo := -1.2
	var hi := 1.2
	for s in samples:
		if s.t >= t0:
			for key in ["target", "x"]:
				lo = minf(lo, float(s[key]) - 0.1)
				hi = maxf(hi, float(s[key]) + 0.1)
			if show_regimes:
				for key in ["under", "crit", "over"]:
					lo = minf(lo, float(s[key]) - 0.1)
					hi = maxf(hi, float(s[key]) + 0.1)
	lo = maxf(lo, -6.0)
	hi = minf(hi, 6.0)
	var font := ThemeDB.fallback_font
	# grid
	for i in range(-6, 7):
		var gy := float(i) * 0.5
		if gy < lo or gy > hi:
			continue
		var y := area.end.y - (gy - lo) / (hi - lo) * area.size.y
		_plot.draw_line(Vector2(area.position.x, y), Vector2(area.end.x, y), Color(1, 1, 1, 0.18 if i == 0 else 0.06), 1.0)
		_plot.draw_string(font, Vector2(4, y + 4), "%+.1f" % gy, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.6, 0.62, 0.7))
	for sec in range(int(ceil(t0)), int(floor(t1)) + 1):
		var x := area.position.x + (float(sec) - t0) / WINDOW_SEC * area.size.x
		_plot.draw_line(Vector2(x, area.position.y), Vector2(x, area.end.y), Color(1, 1, 1, 0.06), 1.0)
		_plot.draw_string(font, Vector2(x - 8, size.y - 6), "%ds" % sec, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.6, 0.62, 0.7))
	var map := func(s: Dictionary, key: String) -> Vector2:
		return Vector2(area.position.x + (float(s.t) - t0) / WINDOW_SEC * area.size.x, area.end.y - (clampf(float(s[key]), lo - 5.0, hi + 5.0) - lo) / (hi - lo) * area.size.y)
	var lines: Array = []
	if show_regimes:
		lines.append(["under", C_UNDER, 1.6])
		lines.append(["crit", C_CRIT, 1.6])
		lines.append(["over", C_OVER, 1.6])
	if show_naive:
		lines.append(["naive", C_NAIVE, 1.6])
	lines.append(["target", C_TARGET, 1.6])
	lines.append(["x", C_RESPONSE, 2.6])
	for l in lines:
		var pts := PackedVector2Array()
		for s in samples:
			if s.t >= t0 - 0.2:
				pts.append(map.call(s, l[0]))
		if pts.size() >= 2:
			_plot.draw_polyline(pts, l[1], l[2], true)
	# velocity on its own scale: +-1 on the plot = +-vscale
	var vscale := 0.0
	for s in samples:
		if s.t >= t0:
			vscale = maxf(vscale, absf(float(s.v)))
	vscale = maxf(vscale, 1.0)
	var mid := area.end.y - (0.0 - lo) / (hi - lo) * area.size.y
	var vp := PackedVector2Array()
	for s in samples:
		if s.t >= t0 - 0.2:
			vp.append(Vector2(area.position.x + (float(s.t) - t0) / WINDOW_SEC * area.size.x, mid - float(s.v) / vscale * area.size.y * 0.22))
	if vp.size() >= 2:
		_plot.draw_polyline(vp, C_VELOCITY, 1.4, true)
	# legend
	var legend := [["target", C_TARGET], ["response x", C_RESPONSE], ["velocity (own scale +-%.1f)" % vscale, C_VELOCITY]]
	if show_regimes:
		legend += [["underdamped 0.25", C_UNDER], ["critical 1.0", C_CRIT], ["overdamped 3.0", C_OVER]]
	if show_naive:
		legend.append(["naive Euler", C_NAIVE])
	var lx := area.position.x + 8.0
	for l in legend:
		_plot.draw_rect(Rect2(lx, area.position.y + 6, 12, 4), l[1], true)
		_plot.draw_string(font, Vector2(lx + 16, area.position.y + 12), l[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.85, 0.87, 0.95))
		lx += 24.0 + font.get_string_size(l[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 10.0
	# overshoot marker on the last measured step
	var shown := shown_measure()
	if not shown.is_empty() and absf(shown.to - shown.from) > 1e-9:
		var pt := Vector2(area.position.x + (shown.t0 + shown.peak_t - t0) / WINDOW_SEC * area.size.x, area.end.y - (shown.peak - lo) / (hi - lo) * area.size.y)
		if pt.x > area.position.x and pt.x < area.end.x and measured_overshoot_pct() > 0.5:
			_plot.draw_circle(pt, 4.0, C_RESPONSE)
			_plot.draw_string(font, pt + Vector2(6, -6), "peak +%.1f %%" % measured_overshoot_pct(), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, C_RESPONSE)


func _draw_dial() -> void:
	var c := Vector2(_dial.size.x * 0.5, _dial.size.y * 0.5)
	var r := minf(_dial.size.x, _dial.size.y) * 0.42
	_dial.draw_arc(c, r, 0.0, TAU, 64, Color(1, 1, 1, 0.25), 1.5)
	var font := ThemeDB.fallback_font
	for deg in [0, 90, 180, -90]:
		var a := deg_to_rad(float(deg)) - PI / 2.0
		_dial.draw_string(font, c + Vector2(cos(a), sin(a)) * (r + 12.0) - Vector2(10, -4), "%d" % deg, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.55, 0.58, 0.68))
	var goal_a := deg_to_rad(rotation_goal_deg) - PI / 2.0
	_dial.draw_line(c, c + Vector2(cos(goal_a), sin(goal_a)) * r, C_TARGET, 2.0)
	var yaw := Math.rotation_vector(rot_spring.q).y
	var a := -yaw - PI / 2.0 + 2.0 * yaw   # draw yaw increasing clockwise, the same as the degree labels
	_dial.draw_line(c, c + Vector2(cos(a), sin(a)) * r * 0.92, C_RESPONSE, 4.0)
	_dial.draw_string(font, Vector2(4, 14), "goal %+.0f deg   actual %+.1f deg   error %.1f deg" % [rotation_goal_deg, rad_to_deg(yaw), rad_to_deg(rot_spring.angle_to_goal())], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.85, 0.87, 0.95))
