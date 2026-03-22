extends Resource
class_name SkillCardData

enum Element { NONE, METAL, WOOD, WATER, FIRE, EARTH }

@export var name: String = "卡牌基类"
@export var element: Element = Element.NONE
@export var cost: int = 10
@export var damage: int = 10
@export var description: String = "这是一张卡牌基类，并且这里是卡牌的效果描述。"

# 执行卡牌效果的方法
func apply_effect(target):
	print("打出了一张卡牌："+name)
	if damage > 0:
		target.take_damage(damage)
		print("对目标造成了 ", damage, " 点伤害")
