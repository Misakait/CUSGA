extends Control
signal exit_game

func _ready():
	$ExitButton.pressed.connect(_on_exit_pressed)

func _on_exit_pressed():
	emit_signal("exit_game")
