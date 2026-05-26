## 此文件由 SkillTargetingTypeCodegen 自动生成，请不要手动修改。
## 来源：res://core/combat/skills/SkillTargetingType.cs
extends RefCounted
class_name SkillTargetingType

enum Value {
	Self = 0,
	SingleEnemy = 1,
	AllEnemies = 2,
	AnySingleUnit = 3,
	AllUnits = 4,
	RandomEnemy = 5,
	SpreadFromEnemy = 6,
}

## 获取枚举名称到整型值的映射。
## 返回值：key 为枚举名（String），value 为枚举整型值（int）。
static func get_map() -> Dictionary:
	return {
		"Self": Value.Self,
		"SingleEnemy": Value.SingleEnemy,
		"AllEnemies": Value.AllEnemies,
		"AnySingleUnit": Value.AnySingleUnit,
		"AllUnits": Value.AllUnits,
		"RandomEnemy": Value.RandomEnemy,
		"SpreadFromEnemy": Value.SpreadFromEnemy,
	}

## 获取指定枚举名对应的整型值。
## 参数：
## - name：枚举名称。
## - fallback：当名称不存在时的兜底值。
## 返回值：目标枚举的整型值，或兜底值。
static func get_value(name: String, fallback: int = -1) -> int:
	return int(get_map().get(name, fallback))
