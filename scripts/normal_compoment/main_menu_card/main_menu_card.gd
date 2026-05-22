
extends Node2D

signal hovering_card(card)
signal not_hovering_card(card)

@export var anim: CardAnimator


@export_group("放大效果")
@export var normal_scale_offeset: Vector2 = Vector2(0, 0)
@export var hover_scale_offeset: Vector2 = Vector2(0.2, 0.2)
@export var drag_scale_offeset: Vector2 = Vector2(0.4, 0.4)
## 动画时长（秒）
@export var tween_duration: float = 0.1

@export_group("卡牌ui设置")
@export var sprite_texture: Texture2D
@export var sprite_icon: Texture2D
@export var sp2d: Sprite2D
@export var my_card_name: Label
@export var my_card_description: Label
@export var my_card_cost: Label
@export var card_name_text: String
@export var card_name_scale: Vector2 = Vector2(1,1)
@export var card_description_text: String
@export var card_description_scale: Vector2 = Vector2(1,1)
@export var card_cost_text: String
@export var card_cost_scale: Vector2 = Vector2(1,1)


var item_data: ItemData
var item_cnt: int

var normal_scale: Vector2 = Vector2(0, 0)
var hover_scale: Vector2 = Vector2(0, 0)
var drag_scale: Vector2 = Vector2(0, 0)

var other_card_using := false
var hovering := false
var dragging := false
var tween: Tween

var par
var be_inited: bool = false
var enter: bool = false
func _ready():

	#如果有parent，初始化parent
	init_parent()

	normal_scale = sp2d.scale + normal_scale_offeset
	hover_scale = sp2d.scale + hover_scale_offeset
	drag_scale = sp2d.scale + drag_scale_offeset

	#初始化自己的ui
	refresh_myself()


func refresh_myself():
	if sprite_texture:
		sp2d.texture = sprite_texture
		sp2d.get_child(0).texture = sprite_icon
	my_card_name.text = card_name_text
	my_card_name.scale = card_name_scale
	my_card_description.text = card_description_text
	my_card_description.scale = card_description_scale
	my_card_cost.text = card_cost_text
	my_card_cost.scale = card_cost_scale

func _on_area_2d_mouse_entered():
	enter = true
	
	emit_signal("hovering_card", self)

	# 如果自己不是正在拖拽的卡牌，且没有其他卡牌在拖拽，才放大
	if not dragging and not is_other_card_hovering():
		hovering = true
		z_index = 2
		animate_scale(hover_scale)

func _on_area_2d_mouse_exited():
	enter = false
	
	emit_signal("not_hovering_card", self)

	if not dragging :
		hovering = false
		z_index = 1
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

func init_parent() -> void:
	par = get_parent()
	if par.name == "root":
		par = null
	if par != null:
		par.original_position[self] = global_position
		hovering_card.connect(par._on_hovering_card)
		not_hovering_card.connect(par._on_not_hovering_card)

func animate_scale(target: Vector2):
	# 停止之前的动画，重新创建
	if tween and tween.is_running():
		tween.kill()
	tween = create_tween()
	tween.tween_property($Sprite2D, "scale", target, tween_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func is_other_card_hovering():
	if get_parent().name != "root":
		var cf = get_parent()
		return cf.hovering_card != null and cf.hovering_card != self
	return false

func init():
	if anim:	
		#print("animator!!")
		#if par != null:
			#global_position = par.original_position[self]
		anim.scale_bounce(Vector2(0.2, 0.2), Vector2(1.0, 1.0), 1.5)
		if be_inited:
			_on_area_2d_mouse_exited()
		be_inited = true
	else:
		print("animator doesnt exit!")
		print(anim)

#调试用
func _on_button_pressed() -> void:
	#print("dragging: ",dragging)
	pass
