extends Sprite2D

## 怪物卡面的独立展示组件，只根据五行选择 SVG，不持有战斗数值。

## 枚举顺序与怪物数据的无、木、金、水、土、火保持一致。
const FRAMES: Dictionary = {
	0: preload("res://res/monstercard/universal_monster.svg"),
	1: preload("res://res/monstercard/wood_monster.svg"),
	2: preload("res://res/monstercard/metal_monster.svg"),
	3: preload("res://res/monstercard/water_monster.svg"),
	4: preload("res://res/monstercard/earth_monster.svg"),
	5: preload("res://res/monstercard/fire_monster.svg"),
}


## 应用真实怪物五行对应的边框和信息底板。
## 参数 element：怪物五行枚举整数，未知取值使用通用紫色版本。
## 返回值：无。
func ApplyElement(element: int) -> void:
	texture = FRAMES.get(element, FRAMES[0]) as Texture2D
