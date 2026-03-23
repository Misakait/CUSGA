@tool
extends Node2D

@export_group("放大效果")
@export var normal_scale_offeset: Vector2 = Vector2(0, 0)
@export var hover_scale_offeset: Vector2 = Vector2(0.2, 0.2)
@export var drag_scale_offeset: Vector2 = Vector2(0.3, 0.3)
## 动画时长（秒）
@export var tween_duration: float = 0.2 

@export var sprite_texture: Texture2D

var normal_scale: Vector2 = Vector2(0, 0)
var hover_scale: Vector2 = Vector2(0, 0)
var drag_scale: Vector2 = Vector2(0, 0)

var hovering := true
var dragging := false
var tween: Tween

func _ready():
	if sprite_texture:
		$Sprite2D.texture = sprite_texture
	
	var sprite2d = $Sprite2D
	normal_scale = sprite2d.scale + normal_scale_offeset
	hover_scale = sprite2d.scale + hover_scale_offeset
	drag_scale = sprite2d.scale + drag_scale_offeset
	
func _on_area_2d_mouse_entered():
	if not dragging:
		hovering = true
		animate_scale(hover_scale)

func _on_area_2d_mouse_exited():
	if not dragging:
		hovering = false
		animate_scale(normal_scale)

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
	tween.tween_property($Sprite2D, "scale", target, tween_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
