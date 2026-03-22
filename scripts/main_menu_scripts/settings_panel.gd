extends Control
signal open_settings

func _ready():
	$SettingsButton.pressed.connect(_on_settings_pressed)

func _on_settings_pressed():
	emit_signal("open_settings")
