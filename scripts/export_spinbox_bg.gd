@tool
extends SpinBox

@export var custom_bg: StyleBox:
	set(value):
		custom_bg = value
		_update_bg()

func _ready() -> void:
	_update_bg()

func _update_bg() -> void:
	var le := get_line_edit()
	if le and custom_bg:
		le.add_theme_stylebox_override("normal", custom_bg)
		le.add_theme_stylebox_override("focus", custom_bg)
