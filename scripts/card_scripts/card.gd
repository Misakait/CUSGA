extends Node2D

signal hovered
signal hovered_off

var hand_position #手牌位置
var card_data:SkillCardData

#该节点必须挂载在CardManager下！
func _ready() -> void:
	get_parent().connect_card_signals(self)

func _process(delta: float) -> void:
	pass

func init_card_data(the_card_data):
	card_data = the_card_data
	$CardName.text = card_data.card_name
	$CardDescription.text = card_data.description
	$CardCost.text = str(card_data.energy_cost)

func _on_area_2d_mouse_entered() -> void:
	emit_signal("hovered", self)

func _on_area_2d_mouse_exited() -> void:
	emit_signal("hovered_off", self)
