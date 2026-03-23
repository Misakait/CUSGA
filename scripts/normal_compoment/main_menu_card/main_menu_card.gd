extends Node2D

signal hovered
signal hovered_off


@export var sprite_texture: Texture2D

func _ready():
	if sprite_texture:
		$Sprite2D.texture = sprite_texture


func _on_area_2d_mouse_entered() -> void:
	emit_signal("hovered", self)

func _on_area_2d_mouse_exited() -> void:
	emit_signal("hovered_off", self)
