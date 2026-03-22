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

func use(target = null):
	if target:
		print(name,"被使用，目标为",target)
	else:
		print(name,"被使用，没有目标")

func init_card_data(card_data):
	data = card_data
	$CardName.text = data.name
	$CardDescription.text = data.description
	$CardCost.text = str(data.cost)

func _on_area_2d_mouse_entered() -> void:
	emit_signal("hovered", self)

func _on_area_2d_mouse_exited() -> void:
	emit_signal("hovered_off", self)
