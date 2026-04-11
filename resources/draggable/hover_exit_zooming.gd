@tool
extends Node2D
class_name hover_exit_zoom

@export var sprite2d: Sprite2D

@export_group("放大效果")
@export var normal_scale_offeset: Vector2 = Vector2(0, 0)
@export var hover_scale_offeset: Vector2 = Vector2(0.1, 0.1)
@export var drag_scale_offeset: Vector2 = Vector2(0.3, 0.3)
## 动画时长（秒）
@export var tween_duration: float = 0.1

@export var sprite_texture: Texture2D

var normal_scale: Vector2 = Vector2(0, 0)
var hover_scale: Vector2 = Vector2(0, 0)
var drag_scale: Vector2 = Vector2(0, 0)

var other_card_using := false
var hovering := true
var dragging := false
var tween: Tween

func _ready():
	normal_scale = sprite2d.scale + normal_scale_offeset
	hover_scale = sprite2d.scale + hover_scale_offeset
	drag_scale = sprite2d.scale + drag_scale_offeset

func start_drag():
	dragging = true
	animate_scale(drag_scale)

func finish_drag():
	dragging = false
	if hovering:
		animate_scale(hover_scale)
	else:
		animate_scale(normal_scale)
	
func animate_scale(target: Vector2):
	# 停止之前的动画，重新创建
	if tween and tween.is_running():
		tween.kill()
	tween = create_tween()
	tween.tween_property(sprite2d, "scale", target, tween_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	
func is_other_card_hovering():
	return false
	
#自己连接需要的按钮

#func _on_up_button_mouse_entered() -> void:
	#if not dragging and not is_other_card_hovering():
		#hovering = true
		#z_index = 2
		#animate_scale(hover_scale)
#
#
#func _on_up_button_mouse_exited() -> void:
	#if not dragging :
		#hovering = false
		#z_index = 1
		#animate_scale(normal_scale)
