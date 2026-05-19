extends  Node

signal fade_complete()
signal fade_in_complete()

@onready var fade_to_black: ColorRect = $CanvasLayer/FadeToBlack
@onready var animation_player: AnimationPlayer = $AnimationPlayer

func _ready() -> void:
	fade_to_black.hide()

func fade_in() -> void:
	fade_to_black.show()
	animation_player.play("screen_transition")
	
	await animation_player.animation_finished
	fade_to_black.hide()
	fade_in_complete.emit()
	
func fade_out() -> void:
	fade_to_black.show()
	animation_player.play_backwards("screen_transition")
	
	await animation_player.animation_finished
	fade_to_black.hide()
	
	fade_complete.emit()
