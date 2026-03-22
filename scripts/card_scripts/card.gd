extends Node2D

signal hovered
signal hovered_off

var hand_position #手牌位置
var data:SkillCardData

#该节点必须挂载在CardManager下！
func _ready() -> void:
	get_parent().connect_card_signals(self)

func _process(delta: float) -> void:
	pass

func init_card_data(card_data):
	data = card_data
	$CardName.text = card_data.name
	$CardDescription.text = card_data.description
	$CardCost.text = str(card_data.cost)

func _on_area_2d_mouse_entered() -> void:
	emit_signal("hovered", self)

func _on_area_2d_mouse_exited() -> void:
	emit_signal("hovered_off", self)
