extends RefCounted

## 五行技能卡素材目录；只负责选择贴图，不修改技能、星级或库存数据。
## 数字键沿用 CombatSkillData 的 None / Wood / Metal / Water / Earth / Fire 枚举。
const FRONTS: Dictionary = {
	0: preload("res://res/skillcard/elemental/universal_front.svg"),
	1: preload("res://res/skillcard/elemental/wood_front.svg"),
	2: preload("res://res/skillcard/elemental/metal_front.svg"),
	3: preload("res://res/skillcard/elemental/water_front.svg"),
	4: preload("res://res/skillcard/elemental/earth_front.svg"),
	5: preload("res://res/skillcard/elemental/fire_front.svg"),
}
## 卡背只标识五行，不提前暴露卡名、类别或星级。
const BACKS: Dictionary = {
	0: preload("res://res/skillcard/elemental/universal_back.svg"),
	1: preload("res://res/skillcard/elemental/wood_back.svg"),
	2: preload("res://res/skillcard/elemental/metal_back.svg"),
	3: preload("res://res/skillcard/elemental/water_back.svg"),
	4: preload("res://res/skillcard/elemental/earth_back.svg"),
	5: preload("res://res/skillcard/elemental/fire_back.svg"),
}
## 图标名称兼容旧资源和分页传入的五行文字。
const ELEMENT_IDS: Dictionary = {
	"None": 0, "Wood": 1, "Metal": 2, "Water": 3, "Earth": 4, "Fire": 5,
	"无": 0, "通用": 0, "木": 1, "金": 2, "水": 3, "土": 4, "火": 5,
}

## 统一五行输入；value 可以是枚举整数或名称，返回有效枚举，未知值返回 0。
static func element_id(value: Variant) -> int:
	if value is int:
		return int(value) if FRONTS.has(value) else 0
	return int(ELEMENT_IDS.get(str(value), 0))

## 根据五行返回正面底板；element 为枚举或名称，返回非空 Texture2D。
static func front_for(element: Variant) -> Texture2D:
	return FRONTS[element_id(element)] as Texture2D

## 根据五行返回卡背；element 为枚举或名称，返回非空 Texture2D。
static func back_for(element: Variant) -> Texture2D:
	return BACKS[element_id(element)] as Texture2D
