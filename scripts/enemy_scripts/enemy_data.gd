extends Resource
class_name EnemyData

enum Element { NONE, METAL, WOOD, WATER, FIRE, EARTH }

@export var name: String = "敌人基类"
@export var element: Element = Element.NONE
@export var description: String = "这是一张敌人基类，并且这里是敌人的描述。"
@export var hp:int = 100
