extends Node

## 采集遭遇与怪物倍率的生产实现，等价迁移自旧 C# EncounterManager 与 EncounterMonsterScaler。
##
## 该节点保留原实现的导出字段名、概率公式、缩放公式、字段默认值和方法名，
## 跨语言调用方只依赖 ResolveGatheringEncounter / ScaleEncounterMonsters
## 两个稳定方法协议，因此 C# 与 GDScript 消费者都不需要编译期具体类型。
## 旧 EncounterManager.cs、EncounterMonsterScaler.cs 与 GatheringEncounterResult.cs
## 继续作为兼容垫片保留，直到全量迁移完成。

const GATHERING_ENCOUNTER_RESULT_SCRIPT: GDScript = preload("res://resources/encounters/gathering_encounter_result.gd")

## 怪物属性资源的生产脚本。
##
## 缩放结果统一构造 GDScript 实现，与怪物 .tres 里 InitialAttributes 的脚本保持一致；
## 旧 C# StartingStats.cs 仅作为兼容输入继续存在，跨语言只依赖同名字段协议。
const STARTING_STATS_SCRIPT: GDScript = preload("res://resources/stats/starting_stats.gd")

## 生产怪物数据的 GDScript 脚本；用于「按源实现新建副本」的回退构造。
const MONSTER_DATA_SCRIPT: GDScript = preload("res://resources/monster/monster_data.gd")
## 怪物数据的跨语言字段协议：C# MonsterData 为 [Export]，GDScript monster_data.gd 为 @export。
## 判定只看字段面，不看类型名或脚本路径，避免把语言身份写进生产逻辑。
const MONSTER_DATA_REQUIRED_FIELDS: Array[StringName] = [
	&"MonsterName",
	&"ElementalProperty",
	&"SkillSet",
]

## 怪物属性倍率的字段集合，保持旧 C# MonsterStatMultiplier 的字段顺序与名称。
const MULTIPLIER_FIELDS: Array[String] = [
	"MaxHealth", "PhysAtk", "PhysDef", "MagPower", "MagResist", "Speed",
]

## 采集遭遇规则资源列表；规则只需提供 TriggerTag、ExtraChanceMultiplier、
## MonsterToSpawn 与 SpawnMessage 这几个稳定字段，允许旧 C# 与 GDScript 规则并存。
@export var GatheringRules: Array[Resource] = []
## 单次采集的基础遭遇概率，沿用旧 C# 默认值 0.05。
@export var BaseGatheringSpawnChance: float = 0.05
## 夜晚遭遇概率倍率，沿用旧 C# 默认值 6.0。
@export var NightChanceMultiplier: float = 6.0

@export_group("Monster Daily Growth")
## 怪物生命上限的每日成长率，0 表示不随天数成长。
@export var MaxHealthDailyGrowth: float = 0.0
## 怪物物理攻击的每日成长率。
@export var PhysAtkDailyGrowth: float = 0.0
## 怪物物理抗性的每日成长率。
@export var PhysDefDailyGrowth: float = 0.0
## 怪物法术强度的每日成长率。
@export var MagPowerDailyGrowth: float = 0.0
## 怪物法术抗性的每日成长率。
@export var MagResistDailyGrowth: float = 0.0
## 怪物速度的每日成长率。
@export var SpeedDailyGrowth: float = 0.0

## 提供昼夜与天数属性的时间节点；运行时默认解析 /root/TimeSystem，
## 测试或特殊场景可在进入场景树前显式注入，避免依赖 C# 静态单例。
var TimeSystemNode: Node = null


## 解析时间 Autoload，并保留调用方显式注入的时间节点。
##
## @return 无；只在节点尚未绑定时间节点时按生产路径解析。
func _ready() -> void:
	if TimeSystemNode == null:
		TimeSystemNode = get_node_or_null("/root/TimeSystem")


## 结算采集遭遇。
##
## @param resourceTag 本次采集资源对应的标签。
## @param nightEncounterChanceMultiplier 夜晚装备提供的遭遇概率乘数，默认中性 1.0。
## @return 遭遇结果对象；未触发时返回 Triggered 为 false 的空结果。
func ResolveGatheringEncounter(
	resourceTag: StringName,
	nightEncounterChanceMultiplier: float = 1.0
) -> RefCounted:
	var tag: StringName = StringName(resourceTag)
	if String(tag).is_empty():
		return _none_result()

	# 昼夜只影响夜晚概率，白天统一回落到中性倍率，保持旧 C# 的分支顺序。
	var is_night: bool = _read_bool(TimeSystemNode, "IsNight", false)
	var time_modifier: float = NightChanceMultiplier if is_night else 1.0
	var equipment_modifier: float = maxf(nightEncounterChanceMultiplier, 0.0) if is_night else 1.0

	for rule: Resource in GatheringRules:
		if rule == null:
			continue
		if _read_string_name(rule, "TriggerTag") != tag:
			continue

		var final_chance: float = (
			BaseGatheringSpawnChance
			* time_modifier
			* equipment_modifier
			* maxf(_read_float(rule, "ExtraChanceMultiplier", 1.0), 0.0)
		)
		print("Resolving gathering encounter for tag: %s, finalChance: %s" % [tag, final_chance])
		if randf() <= final_chance:
			var monsters: Array = _read_monster_array(rule, "MonsterToSpawn")
			if monsters.is_empty():
				return _none_result()
			for monster: Resource in monsters:
				print("Gathering encounter triggered: %s" % _read_string(monster, "MonsterName", ""))
			return _create_result(monsters, _read_string(rule, "SpawnMessage", ""))

	return _none_result()


## 按地形浮动倍率与每日成长率缩放遭遇怪物。
##
## @param terrain 本次遭遇所在的地形实例，可为空；只要求提供稳定的倍率快照协议。
## @param monsters 调用方已完成过滤的怪物数组，可混入空值。
## @return 按原顺序返回缩放后的怪物数组，元素身份为新副本。
func ScaleEncounterMonsters(terrain: Variant, monsters: Array) -> Array:
	var terrain_variance: Dictionary = _read_terrain_variance(terrain)
	var per_day_growth: Dictionary = _build_per_day_growth_multiplier()
	var current_day: int = _read_int(TimeSystemNode, "CurrentDay", 1)
	return _scale_monsters(monsters, terrain_variance, per_day_growth, current_day)


## 构造已触发的遭遇结果。
##
## @param monsters 触发时需要生成的怪物资源数组。
## @param message 触发时显示的提示文本。
## @return Triggered 为 true 的结果实例。
func _create_result(monsters: Array, message: String) -> RefCounted:
	var result: RefCounted = GATHERING_ENCOUNTER_RESULT_SCRIPT.new()
	result.Setup(true, monsters, message)
	return result


## 构造未触发的空遭遇结果。
##
## @return Triggered 为 false、字段为默认值的结果实例。
func _none_result() -> RefCounted:
	var result: RefCounted = GATHERING_ENCOUNTER_RESULT_SCRIPT.new()
	result.Setup(false, [], "")
	return result


## 从任意对象读取布尔字段，兼容 GDScript 与旧 C# 节点。
##
## @param source 提供字段的对象，可为空。
## @param property_name 字段名称。
## @param fallback 字段缺失或类型不匹配时的默认值。
## @return 读取到的布尔值或默认值。
func _read_bool(source: Object, property_name: String, fallback: bool) -> bool:
	if source == null or not is_instance_valid(source):
		return fallback
	var value: Variant = source.get(property_name)
	return value if value is bool else fallback


## 从任意对象读取整数字段，兼容 int 与 float 两种数值 Variant。
##
## @param source 提供字段的对象，可为空。
## @param property_name 字段名称。
## @param fallback 字段缺失或类型不匹配时的默认值。
## @return 读取到的整数或默认值。
func _read_int(source: Object, property_name: String, fallback: int) -> int:
	if source == null or not is_instance_valid(source):
		return fallback
	var value: Variant = source.get(property_name)
	if value is int or value is float:
		return int(value)
	return fallback


## 从规则 Resource 读取浮点字段。
##
## @param rule 待读取的遭遇规则资源。
## @param property_name 字段名称。
## @param fallback 字段缺失或类型不匹配时的默认值。
## @return 读取到的浮点值或默认值。
func _read_float(rule: Resource, property_name: String, fallback: float) -> float:
	var value: Variant = rule.get(property_name)
	if value is float or value is int:
		return float(value)
	return fallback


## 从规则 Resource 读取文本字段。
##
## @param rule 待读取的遭遇规则资源。
## @param property_name 字段名称。
## @param fallback 字段缺失或类型不匹配时的默认文本。
## @return 读取到的文本或默认文本。
func _read_string(rule: Resource, property_name: String, fallback: String) -> String:
	var value: Variant = rule.get(property_name)
	return value if value is String else fallback


## 从规则 Resource 读取标签字段，兼容 StringName、String 与空值。
##
## @param rule 待读取的遭遇规则资源。
## @param property_name 字段名称。
## @return 规则标签；无法读取时返回空标签。
func _read_string_name(rule: Resource, property_name: String) -> StringName:
	var value: Variant = rule.get(property_name)
	if value is StringName:
		return value
	if value is String:
		return StringName(value)
	return StringName()


## 将规则中的动态怪物数组过滤为怪物资源数组。
##
## @param rule 待读取的遭遇规则资源。
## @param property_name 怪物数组字段名称。
## @return 过滤掉空值和非怪物数据元素后、保持原顺序的数组。
func _read_monster_array(rule: Resource, property_name: String) -> Array:
	var monsters: Array = []
	var value: Variant = rule.get(property_name)
	if not (value is Array):
		return monsters
	for raw_monster: Variant in value:
		if _is_monster_data(raw_monster):
			monsters.append(raw_monster)
	return monsters


## 判断资源是否为旧 C# MonsterData 或迁移后的 GDScript 怪物数据。
##
## GDScript 无法继承 C# 的 MonsterData，两侧实现共用同一组导出字段，
## 因此判定只扫字段面（属性表），不看类型名或脚本路径。
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


## 创建与源怪物同脚本的副本，供遭遇缩放写入缩放后的数值。
##
## 运行期优先用脚本自身实例化，保持旧 C# MonsterData 的“全新对象”语义；编辑器内非
## @tool 脚本不允许实例化，此时退化为浅拷贝，脚本与子资源引用依旧与源一致。
## 所有字段随后都会被 _scale_monster 显式覆写，因此两种路径的可观察结果相同。
##
## @param source 源怪物资源，允许旧 C# 或 GDScript 实现。
## @return 与源实现一致的怪物副本；脚本完全不可用时回退到生产 GDScript 怪物数据。
func _new_monster_like(source: Resource) -> Resource:
	var source_script: Script = source.get_script() as Script
	if source_script != null and source_script.can_instantiate():
		var instance: Resource = source_script.new() as Resource
		if instance != null:
			return instance
	var shallow_copy: Resource = source.duplicate(false) as Resource
	if shallow_copy != null:
		return shallow_copy
	return MONSTER_DATA_SCRIPT.new() as Resource


## 读取地形实例的浮动倍率快照。
##
## 普通 C# MonsterStatMultiplier 无法直接跨语言保存，因此生产 TerrainInstance 以
## GetEncounterVarianceSnapshot 提供 Dictionary 快照；缺失协议时按中性倍率处理。
##
## @param terrain 地形实例，可为空或为任意对象。
## @return 六个倍率字段的字典，缺省值为 1。
func _read_terrain_variance(terrain: Variant) -> Dictionary:
	if terrain == null or not (terrain is Object):
		return _identity_multiplier()
	var terrain_object: Object = terrain
	if not is_instance_valid(terrain_object):
		return _identity_multiplier()
	if not terrain_object.has_method("GetEncounterVarianceSnapshot"):
		return _identity_multiplier()
	return _normalize_multiplier(terrain_object.call("GetEncounterVarianceSnapshot"))


## 把任意倍率快照归一化为六个字段的字典。
##
## @param source 期望为包含倍率字段的 Dictionary。
## @return 补齐缺失字段为 1、保留既有数值的字典。
func _normalize_multiplier(source: Variant) -> Dictionary:
	var normalized: Dictionary = _identity_multiplier()
	if not (source is Dictionary):
		return normalized
	for field: String in MULTIPLIER_FIELDS:
		var value: Variant = source.get(field)
		if value is float or value is int:
			normalized[field] = float(value)
	return normalized


## 构造中性倍率字典，等价旧 C# MonsterStatMultiplier.Identity。
##
## @return 六个字段均为 1 的字典。
func _identity_multiplier() -> Dictionary:
	var identity: Dictionary = {}
	for field: String in MULTIPLIER_FIELDS:
		identity[field] = 1.0
	return identity


## 把导出字段组装成每日成长率字典。
##
## @return 六个字段来自 @export 的成长率字典，默认全部为 0。
func _build_per_day_growth_multiplier() -> Dictionary:
	return {
		"MaxHealth": MaxHealthDailyGrowth,
		"PhysAtk": PhysAtkDailyGrowth,
		"PhysDef": PhysDefDailyGrowth,
		"MagPower": MagPowerDailyGrowth,
		"MagResist": MagResistDailyGrowth,
		"Speed": SpeedDailyGrowth,
	}


## 把每日成长率按当前天数展开为乘数，等价旧 C# EncounterMonsterScaler.BuildDayMultiplier。
##
## @param per_day_growth 每日成长率字典。
## @param current_day 当前游戏天数，第 1 天为无成长基准。
## @return 六个字段的当日乘数字典。
func _build_day_multiplier(per_day_growth: Dictionary, current_day: int) -> Dictionary:
	var elapsed_days: int = maxi(current_day - 1, 0)
	var day_multiplier: Dictionary = {}
	for field: String in MULTIPLIER_FIELDS:
		day_multiplier[field] = 1.0 + elapsed_days * float(per_day_growth.get(field, 0.0))
	return day_multiplier


## 按地形与天数倍率缩放整组怪物。
##
## @param monsters 调用方传入的动态怪物数组，可混入空值或无效元素。
## @param terrain_variance 地形浮动倍率字典。
## @param per_day_growth 每日成长率字典。
## @param current_day 当前游戏天数。
## @return 保持原顺序、跳过空值的缩放怪物数组。
func _scale_monsters(
	monsters: Array,
	terrain_variance: Dictionary,
	per_day_growth: Dictionary,
	current_day: int
) -> Array:
	var scaled_monsters: Array = []
	var day_multiplier: Dictionary = _build_day_multiplier(per_day_growth, current_day)
	for raw_monster: Variant in monsters:
		if raw_monster == null:
			continue
		if not _is_monster_data(raw_monster):
			continue
		scaled_monsters.append(
			_scale_monster(raw_monster as Resource, terrain_variance, day_multiplier)
		)
	return scaled_monsters


## 复制单个怪物并写入缩放后的属性。
##
## @param source 原始怪物资源。
## @param terrain_variance 地形浮动倍率字典。
## @param day_multiplier 当日成长乘数字典。
## @return 保留外观、掉落、技能与阵营，但属性已缩放的新怪物副本。
func _scale_monster(
	source: Resource,
	terrain_variance: Dictionary,
	day_multiplier: Dictionary
) -> Resource:
	var scaled: Resource = _new_monster_like(source)
	# 使用 get/set 读取字段，保证旧 C# MonsterData 与后续 GDScript 实现都能被同一协议写入。
	scaled.set("MonsterName", source.get("MonsterName"))
	scaled.set("ElementalProperty", source.get("ElementalProperty"))
	scaled.set("ModelScene", source.get("ModelScene"))
	scaled.set("LootTable", source.get("LootTable"))
	scaled.set("BehaviorTreeScene", source.get("BehaviorTreeScene"))
	scaled.set("Faction", source.get("Faction"))
	scaled.set("SkillSet", source.get("SkillSet"))

	var initial_attributes: Variant = source.get("InitialAttributes")
	if initial_attributes != null:
		scaled.set(
			"InitialAttributes",
			_scale_stats(initial_attributes, terrain_variance, day_multiplier)
		)

	return scaled


## 按地形与天数倍率缩放初始属性资源。
##
## @param source 原始属性 Resource，允许旧 C# StartingStats 或 GDScript 等价资源。
## @param terrain_variance 地形浮动倍率字典。
## @param day_multiplier 当日成长乘数字典。
## @return 字段与旧 C# EncounterMonsterScaler.ScaleStats 完全一致的属性副本。
func _scale_stats(
	source: Resource,
	terrain_variance: Dictionary,
	day_multiplier: Dictionary
) -> Resource:
	var scaled: Resource = STARTING_STATS_SCRIPT.new()
	scaled.set("BasePhysAtk", _scale_float(
		_read_stat(source, "BasePhysAtk", 100.0),
		float(terrain_variance["PhysAtk"]),
		float(day_multiplier["PhysAtk"])
	))
	scaled.set("PhysAtkGrowth", _read_stat(source, "PhysAtkGrowth", 25.0))
	scaled.set("BasePhysDef", _scale_float(
		_read_stat(source, "BasePhysDef", 100.0),
		float(terrain_variance["PhysDef"]),
		float(day_multiplier["PhysDef"])
	))
	scaled.set("PhysDefGrowth", _read_stat(source, "PhysDefGrowth", 20.0))
	scaled.set("BaseMagPower", _scale_float(
		_read_stat(source, "BaseMagPower", 100.0),
		float(terrain_variance["MagPower"]),
		float(day_multiplier["MagPower"])
	))
	scaled.set("MagPowerGrowth", _read_stat(source, "MagPowerGrowth", 30.0))
	scaled.set("BaseMagResist", _scale_float(
		_read_stat(source, "BaseMagResist", 100.0),
		float(terrain_variance["MagResist"]),
		float(day_multiplier["MagResist"])
	))
	scaled.set("MagResistGrowth", _read_stat(source, "MagResistGrowth", 20.0))
	scaled.set("BaseSpeed", _scale_float(
		_read_stat(source, "BaseSpeed", 100.0),
		float(terrain_variance["Speed"]),
		float(day_multiplier["Speed"])
	))
	scaled.set("SpeedGrowth", _read_stat(source, "SpeedGrowth", 5.0))
	scaled.set("BaseMaxHealth", _scale_float(
		_read_stat(source, "BaseMaxHealth", 1000.0),
		float(terrain_variance["MaxHealth"]),
		float(day_multiplier["MaxHealth"])
	))
	scaled.set("MaxHealthGrowth", _read_stat(source, "MaxHealthGrowth"))
	scaled.set("BaseMaxEnergy", _read_stat(source, "BaseMaxEnergy", 100.0))
	scaled.set("MaxEnergyGrowth", _read_stat(source, "MaxEnergyGrowth"))
	scaled.set("BaseFixedPhysPenetration", _read_stat(source, "BaseFixedPhysPenetration"))
	scaled.set("FixedPhysPenetrationGrowth", _read_stat(source, "FixedPhysPenetrationGrowth"))
	scaled.set("BasePhysPenetrationRate", _read_stat(source, "BasePhysPenetrationRate"))
	scaled.set("PhysPenetrationRateGrowth", _read_stat(source, "PhysPenetrationRateGrowth"))
	scaled.set("BaseFixedMagicPenetration", _read_stat(source, "BaseFixedMagicPenetration"))
	scaled.set("FixedMagicPenetrationGrowth", _read_stat(source, "FixedMagicPenetrationGrowth"))
	scaled.set("BaseMagicPenetrationRate", _read_stat(source, "BaseMagicPenetrationRate"))
	scaled.set("MagicPenetrationRateGrowth", _read_stat(source, "MagicPenetrationRateGrowth"))
	scaled.set("BaseCritRate", _read_stat(source, "BaseCritRate"))
	scaled.set("CritRateGrowth", _read_stat(source, "CritRateGrowth"))
	scaled.set("BaseCritDamage", _read_stat(source, "BaseCritDamage", 1.5))
	scaled.set("CritDamageGrowth", _read_stat(source, "CritDamageGrowth"))
	scaled.set("BaseEvasionRate", _read_stat(source, "BaseEvasionRate"))
	scaled.set("EvasionRateGrowth", _read_stat(source, "EvasionRateGrowth"))
	scaled.set("BaseLifestealRate", _read_stat(source, "BaseLifestealRate"))
	scaled.set("LifestealRateGrowth", _read_stat(source, "LifestealRateGrowth"))
	return scaled


## 读取跨语言属性资源中的浮点字段。
##
## @param source 旧 C# 或新 GDScript 属性资源。
## @param property_name 字段名称。
## @param fallback 字段缺失时沿用的旧默认值。
## @return 可用于缩放计算的浮点值。
func _read_stat(source: Resource, property_name: String, fallback: float = 0.0) -> float:
	var value: Variant = source.get(property_name)
	if value is float or value is int:
		return float(value)
	return fallback


## 按地形与天数倍率缩放单个数值，等价旧 C# EncounterMonsterScaler.ScaleFloat。
##
## @param value 原始数值。
## @param terrain_multiplier 地形浮动倍率。
## @param day_multiplier 当日成长乘数。
## @return 两个倍率依次相乘后的结果。
func _scale_float(value: float, terrain_multiplier: float, day_multiplier: float) -> float:
	return value * terrain_multiplier * day_multiplier
