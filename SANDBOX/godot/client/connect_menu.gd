## Minimal connect panel shown when the client starts without --connect or loses its connection.
extends CenterContainer

signal connect_requested(address: String, player_name: String)

var _name_edit: LineEdit
var _address_edit: LineEdit
var _status: Label


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	add_child(panel)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(360, 0)
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var title := Label.new()
	title.text = "STRUCTURE — sandbox"
	title.add_theme_font_size_override("font_size", 24)
	box.add_child(title)
	_name_edit = _field(box, "Player name")
	_address_edit = _field(box, "Server (host:port)")
	var button := Button.new()
	button.text = "Connect"
	button.pressed.connect(_submit)
	box.add_child(button)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)
	_address_edit.text_submitted.connect(func(_t: String) -> void: _submit())


func _field(parent: Control, label_text: String) -> LineEdit:
	var label := Label.new()
	label.text = label_text
	parent.add_child(label)
	var edit := LineEdit.new()
	parent.add_child(edit)
	return edit


func set_defaults(player_name: String, address: String) -> void:
	_name_edit.text = player_name
	_address_edit.text = address


func show_status(text: String) -> void:
	_status.text = text


func _submit() -> void:
	connect_requested.emit(_address_edit.text.strip_edges(), _name_edit.text.strip_edges())
