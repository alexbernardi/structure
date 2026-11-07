## Binding editor (F4): edit which parameter each strip's fader and knob drives in the current bank, what the buttons
## do, manage banks and presets. Changes apply immediately; "Save bindings" writes config/tuning_bindings.json.
## "Bind by moving a control" is the learn step for this layer: pick a parameter, arm, move a fader or knob.
extends PanelContainer

const Catalog = preload("res://midi/control_catalog.gd")
const Bindings = preload("res://tuning/tuning_bindings.gd")

var system
var _keys: Array[String] = []
var _fader_opts: Array[OptionButton] = []
var _knob_opts: Array[OptionButton] = []
var _bank_label: Label
var _bank_name: LineEdit
var _learn_param: OptionButton
var _learn_status: Label
var _strip_action_opts: Dictionary = {}
var _global_action_opts: Dictionary = {}
var _preset_list: OptionButton
var _preset_name: LineEdit
var _status: Label
var _confirm: ConfirmationDialog
var _building := false


func _init() -> void:
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2(12, 12)
	custom_minimum_size = Vector2(660, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.13, 1.0)
	style.set_border_width_all(1)
	style.border_color = Color(0.35, 0.40, 0.55)
	style.set_content_margin_all(12)
	add_theme_stylebox_override("panel", style)


func build(sys) -> void:
	system = sys
	_building = true
	_keys = system.registry.keys()
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	var title := Label.new()
	title.text = "Tuning bindings   (F4 closes; movement is paused while this is open)"
	title.add_theme_font_size_override("font_size", 16)
	root.add_child(title)
	var tabs := TabContainer.new()
	tabs.custom_minimum_size = Vector2(636, 480)
	root.add_child(tabs)
	tabs.add_child(_sliders_tab())
	tabs.add_child(_buttons_tab())
	tabs.add_child(_presets_tab())
	tabs.set_tab_title(0, "Faders & knobs")
	tabs.set_tab_title(1, "Buttons")
	tabs.set_tab_title(2, "Presets")

	var bottom := HBoxContainer.new()
	root.add_child(bottom)
	bottom.add_child(_button("Save bindings", func() -> void: system.save_bindings()))
	bottom.add_child(_button("Reload from file", func() -> void: system.reload_bindings(); refresh()))
	bottom.add_child(_button("Close (F4)", func() -> void: system.toggle_editor()))
	_status = Label.new()
	_status.modulate = Color(0.7, 0.85, 1.0)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(_status)
	system.toast.connect(func(text: String, _l: String) -> void: _status.text = text)

	_confirm = ConfirmationDialog.new()
	_confirm.confirmed.connect(_delete_selected_preset)
	add_child(_confirm)
	system.engine.state_changed.connect(_on_engine_state)
	system.engine.learn_finished.connect(func(_b: int, _s: int, _k: String, key: String) -> void:
		_learn_status.text = "Bound %s" % system.registry.label_of(key)
		refresh())
	_building = false
	refresh()


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	return b


func _param_options(include_none := true) -> OptionButton:
	var o := OptionButton.new()
	if include_none:
		o.add_item("(none)")
	for k in _keys:
		o.add_item("%s: %s (%s)" % [system.registry.target_label(k), system.registry.label_of(k), system.registry.unit_of(k)])
	o.custom_minimum_size = Vector2(250, 0)
	return o


func _sliders_tab() -> Control:
	var box := VBoxContainer.new()
	box.name = "Faders && knobs"
	var bank := HBoxContainer.new()
	box.add_child(bank)
	bank.add_child(_button("<", func() -> void: system.engine.run_action("bank_prev")))
	_bank_label = Label.new()
	_bank_label.custom_minimum_size = Vector2(110, 0)
	bank.add_child(_bank_label)
	bank.add_child(_button(">", func() -> void: system.engine.run_action("bank_next")))
	_bank_name = LineEdit.new()
	_bank_name.custom_minimum_size = Vector2(150, 0)
	_bank_name.max_length = Bindings.MAX_BANK_NAME
	bank.add_child(_bank_name)
	bank.add_child(_button("Rename", func() -> void:
		system.bindings.rename_bank(system.engine.bank, _bank_name.text)
		refresh()))
	bank.add_child(_button("Add bank", func() -> void:
		var i: int = system.bindings.add_bank("")
		system.engine.switch_bank(i)))
	bank.add_child(_button("Delete bank", func() -> void:
		if system.bindings.remove_bank(system.engine.bank):
			system.engine.switch_bank(clampi(system.engine.bank, 0, system.bindings.bank_count() - 1))
			system.engine.rearm_all()
		refresh()))

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	box.add_child(grid)
	for h in ["Strip", "Fader (coarse)", "Knob (fine / secondary)"]:
		var l := Label.new()
		l.text = h
		l.modulate = Color(0.6, 0.65, 0.8)
		grid.add_child(l)
	for strip in range(1, Catalog.STRIPS + 1):
		var l := Label.new()
		l.text = str(strip)
		grid.add_child(l)
		for kind in ["fader", "knob"]:
			var o := _param_options()
			o.item_selected.connect(_on_slot_selected.bind(strip, kind))
			grid.add_child(o)
			(_fader_opts if kind == "fader" else _knob_opts).append(o)

	box.add_child(HSeparator.new())
	var learn := HBoxContainer.new()
	box.add_child(learn)
	var l2 := Label.new()
	l2.text = "Bind by moving a control:"
	learn.add_child(l2)
	_learn_param = _param_options(false)
	learn.add_child(_learn_param)
	learn.add_child(_button("Arm", func() -> void:
		var k: String = _keys[_learn_param.selected]
		if system.engine.begin_learn(k):
			_learn_status.text = "Move a fader or knob on the controller to bind %s here..." % system.registry.label_of(k)))
	learn.add_child(_button("Cancel", func() -> void:
		system.engine.cancel_learn()
		_learn_status.text = ""))
	_learn_status = Label.new()
	_learn_status.modulate = Color(1.0, 0.75, 0.3)
	box.add_child(_learn_status)
	return box


func _buttons_tab() -> Control:
	var scroll := ScrollContainer.new()
	scroll.name = "Buttons"
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	scroll.add_child(grid)
	var head := Label.new()
	head.text = "Strip buttons (act on that strip's parameter)"
	head.modulate = Color(0.6, 0.65, 0.8)
	grid.add_child(head)
	grid.add_child(Control.new())
	for part in Bindings.STRIP_PARTS:
		var l := Label.new()
		l.text = "Strip button  %s" % {"mute": "M", "solo": "S", "rec": "R", "select": "Select"}[part]
		grid.add_child(l)
		var o := _action_options(true)
		o.item_selected.connect(_on_strip_action.bind(part))
		grid.add_child(o)
		_strip_action_opts[part] = o
	var head2 := Label.new()
	head2.text = "Global buttons"
	head2.modulate = Color(0.6, 0.65, 0.8)
	grid.add_child(head2)
	grid.add_child(Control.new())
	for c in Catalog.all():
		if c.strip != 0:
			continue
		var l2 := Label.new()
		l2.text = "%s%s" % [c.label, "  (optional key)" if c.optional else ""]
		grid.add_child(l2)
		var o2 := _action_options(false)
		o2.item_selected.connect(_on_global_action.bind(c.id))
		grid.add_child(o2)
		_global_action_opts[c.id] = o2
	return scroll


func _action_options(strip_scope: bool) -> OptionButton:
	var o := OptionButton.new()
	for a in Bindings.ACTIONS:
		if strip_scope or not Bindings.STRIP_ONLY.has(a):
			o.add_item(Bindings.ACTIONS[a])
			o.set_item_metadata(o.item_count - 1, a)
	o.custom_minimum_size = Vector2(280, 0)
	return o


func _presets_tab() -> Control:
	var box := VBoxContainer.new()
	box.name = "Presets"
	var save := HBoxContainer.new()
	box.add_child(save)
	var l := Label.new()
	l.text = "Save current values as:"
	save.add_child(l)
	_preset_name = LineEdit.new()
	_preset_name.placeholder_text = "preset_name"
	_preset_name.custom_minimum_size = Vector2(200, 0)
	save.add_child(_preset_name)
	save.add_child(_button("Save", func() -> void:
		system.save_preset_as(_preset_name.text)
		refresh()))
	var load := HBoxContainer.new()
	box.add_child(load)
	_preset_list = OptionButton.new()
	_preset_list.custom_minimum_size = Vector2(240, 0)
	load.add_child(_preset_list)
	load.add_child(_button("Load", func() -> void:
		if _preset_list.item_count > 0:
			system.load_preset(_preset_list.get_item_text(_preset_list.selected))))
	load.add_child(_button("Delete...", func() -> void:
		if _preset_list.item_count > 0:
			_confirm.dialog_text = "Delete preset '%s'? This removes its file." % _preset_list.get_item_text(_preset_list.selected)
			_confirm.popup_centered()))
	var note := Label.new()
	note.text = "Loading a preset arms pickup on every fader: nothing jumps until a fader reaches the value.\nThe factory 'default' preset is protected."
	note.modulate = Color(0.7, 0.72, 0.8)
	box.add_child(note)
	return box


# ------------------------------------------------------------------ state sync

func _on_engine_state() -> void:
	if visible:
		refresh()


func refresh() -> void:
	if system == null or _building:
		return
	_building = true
	var b: int = system.engine.bank
	_bank_label.text = "Bank %d / %d" % [b + 1, system.bindings.bank_count()]
	_bank_name.text = system.bindings.bank_name(b)
	for strip in range(1, Catalog.STRIPS + 1):
		_select_key(_fader_opts[strip - 1], system.bindings.slot_key(b, strip, "fader"))
		_select_key(_knob_opts[strip - 1], system.bindings.slot_key(b, strip, "knob"))
	for part in _strip_action_opts:
		_select_action(_strip_action_opts[part], system.bindings.strip_action(part))
	for id in _global_action_opts:
		_select_action(_global_action_opts[id], system.bindings.global_action(id))
	var current: String = _preset_list.get_item_text(_preset_list.selected) if _preset_list.item_count > 0 else ""
	_preset_list.clear()
	for n in system.presets.names():
		_preset_list.add_item(n)
	for i in _preset_list.item_count:
		if _preset_list.get_item_text(i) == (system.engine.preset_name if system.engine.preset_name != "" else current):
			_preset_list.select(i)
	_building = false


func _select_key(o: OptionButton, key: String) -> void:
	o.select(0 if key == "" or not _keys.has(key) else _keys.find(key) + 1)


func _select_action(o: OptionButton, action: String) -> void:
	for i in o.item_count:
		if o.get_item_metadata(i) == action:
			o.select(i)
			return
	o.select(0)


func _on_slot_selected(index: int, strip: int, kind: String) -> void:
	if _building:
		return
	system.bindings.assign(system.engine.bank, strip, kind, "" if index == 0 else _keys[index - 1])
	system.engine.rearm_all()
	system.engine.state_changed.emit()


func _on_strip_action(index: int, part: String) -> void:
	if not _building:
		system.bindings.set_strip_action(part, String(_strip_action_opts[part].get_item_metadata(index)))


func _on_global_action(index: int, control_id: String) -> void:
	if not _building:
		system.bindings.set_global_action(control_id, String(_global_action_opts[control_id].get_item_metadata(index)))


func _delete_selected_preset() -> void:
	if _preset_list.item_count > 0:
		system.delete_preset(_preset_list.get_item_text(_preset_list.selected))
		refresh()
