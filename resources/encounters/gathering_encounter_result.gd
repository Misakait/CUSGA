extends RefCounted

## 采集遭遇结算结果的 GDScript 生产实现。
##
## 字段名与旧 C# GatheringEncounterResult 完全一致，因此 C# 兼容适配层、
## 后续迁移的 GDScript 交互操作和聚焦测试都能按同一组属性名读取结果。
## 该对象只承担数据搬运，不持有随机数、遭遇规则或任何玩法副作用。

## 本次采集是否触发遭遇。
var Triggered: bool = false
## 触发时需要生成的怪物资源数组；未触发时保持为空。
## 使用通用 Resource 数组，才能同时容纳旧 C# MonsterData 与 GDScript monster_data.gd。
var MonsterToSpawn: Array[Resource] = []
## 触发时显示的遭遇提示文本；未触发时保持为空字符串。
var SpawnMessage: String = ""

## 怪物数据的跨语言字段协议：C# MonsterData 为 [Export]，GDScript monster_data.gd 为 @export。
## 判定只看字段面，不看类型名或脚本路径，避免把语言身份写进生产逻辑。
const MONSTER_DATA_REQUIRED_FIELDS: Array[StringName] = [
	&"MonsterName",
	&"ElementalProperty",
	&"SkillSet",
]


## 按旧 C# None() / Create() 的字段赋值顺序初始化本实例。
##
## 未触发时清空怪物数组和提示文本，避免复用实例残留上一次遭遇的数据。
##
## @param triggered 本次采集是否触发遭遇。
## @param monsters 触发时需要生成的怪物资源数组，可混入无效元素以便过滤。
## @param message 触发时显示的提示文本。
## @return 无；该方法只写入本实例字段，不返回新对象。
func Setup(triggered: bool, monsters: Array, message: String) -> void:
	Triggered = triggered
	MonsterToSpawn.clear()
	if triggered:
		for raw_monster: Variant in monsters:
			if _is_monster_data(raw_monster):
				MonsterToSpawn.append(raw_monster as Resource)
	SpawnMessage = message if triggered else ""


## 判断资源是否为旧 C# MonsterData 或迁移后的 GDScript 怪物数据。
##
## 两侧实现共用同一组导出字段，因此判定只扫字段面（属性表）。
##
## @param value 待判断的动态值。
## @return 属于两种怪物数据实现之一时返回 true。
func _is_monster_data(value: Variant) -> bool:
	if not (value is Resource):
		return false

	var resource: Resource = value
	var present: Dictionary = {}
	for property: Dictionary in resource.get_property_list():
		present[StringName(property.get("name", ""))] = true

	for field: StringName in MONSTER_DATA_REQUIRED_FIELDS:
		if not present.has(field):
			return false

	return true
