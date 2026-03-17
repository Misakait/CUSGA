extends Resource
class_name SkillCardData

enum CardType { SKILL, TALENT, SUMMON, EQUIPMENT, ITEM }
enum Element { NONE, METAL, WOOD, WATER, FIRE, EARTH }

@export var card_name: String = "卡牌基类"
@export var type: CardType = CardType.SKILL
@export var element: Element = Element.NONE
@export var energy_cost: int = 10
@export var damage_amount: int = 10
@export var description: String = "这是一张卡牌基类，并且这里是卡牌的效果描述。"

# 执行卡牌效果的方法
func apply_effect(target):
	print("打出了一张卡牌："+card_name)
	if damage_amount > 0:
		target.take_damage(damage_amount)
		print("对目标造成了 ", damage_amount, " 点伤害")
