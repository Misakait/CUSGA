extends Resource
class_name GatheringInteraction

## 一次性采集地形交互的 GDScript 数据资源。
##
## 资源只负责读取采集配置并生成有序操作描述；时间流逝、地形状态、
## 掉落卡生成、遭遇请求和源卡移除继续由 TerrainInteractionExecutor 执行。

const EQUIPMENT_TYPES: GDScript = preload("res://core/constants/equipment_types.gd")

## 完成采集消耗的游戏时间点数。
@export var TimeCost: int = 20

## 工具减免后允许保留的最短游戏时间点数。
@export_range(1, 999, 1, "or_greater") var MinimumTimeCost: int = 1

## 唯一允许提供采集时间减免的装备槽位。
@export var EffectiveToolSlot: EQUIPMENT_TYPES.EquipmentSlot = EQUIPMENT_TYPES.EquipmentSlot.Axe

## 用于装备额外产量和采集遭遇匹配的资源标签。
@export var GatheringTag: StringName = &""

## 完成采集时使用的掉落表；创建 LootTableData 后在 Drops 中添加 LootDrop。
@export var DropTable: LootTableData


## 构建与旧 GatheringInteraction 相同顺序的操作描述。
##
## 参数 player：触发采集的玩家节点，用于读取装备额外产量。
## 参数 terrain：被交互的 TerrainInstance，用于判断是否已经采集。
## 参数 effective_time_cost_override：统一长按入口传入的耗时快照；非空时优先使用该快照。
## 返回值：依次包含时间、采集标记、可选掉落、遭遇检查和源卡移除的操作数组。
func build_ops(
	player: Object,
	terrain: Object,
	effective_time_cost_override: Variant = null
) -> Array[Dictionary]:
	var equipment := _get_equipment(player)
	var effective_time_cost := get_effective_time_cost(equipment)
	effective_time_cost = GatheringEffectCalculator.resolve_time_cost(
		effective_time_cost_override,
		effective_time_cost
	)
	var ops: Array[Dictionary] = [
		{"type": "pass_time", "amount": effective_time_cost},
		{"type": "mark_harvested"},
	]

	# 旧实现只在构建操作时尚未采集的地形上滚动掉落，但仍会执行后续遭遇与移除。
	if terrain != null and not bool(terrain.get("IsHarvested")):
		var extra_yield := GatheringEffectCalculator.get_yield_bonus(equipment, GatheringTag)

		var loots: Array = []
		if DropTable != null and DropTable.has_method("RollLoot"):
			var loot_value: Variant = DropTable.call("RollLoot", extra_yield)
			if loot_value is Array:
				loots = loot_value
		if not loots.is_empty():
			ops.append({"type": "spawn_loot", "drops": loots})

	if not GatheringTag.is_empty():
		ops.append({"type": "check_gathering_encounter", "gathering_tag": GatheringTag})
	ops.append({"type": "remove_source_card"})
	return ops


## 根据当前装备计算一次性采集的实际耗时。
##
## 参数 equipment：玩家装备组件，可为空。
## 返回值：应用匹配工具减免后的耗时，至少为 MinimumTimeCost 或 1。
func get_effective_time_cost(equipment: Object) -> int:
	return GatheringEffectCalculator.get_effective_time_cost(
		equipment,
		GatheringTag,
		EffectiveToolSlot,
		TimeCost,
		get_minimum_time_cost()
	)


## 根据当前装备计算长按所需的真实秒数。
##
## 参数 equipment：玩家装备组件，可为空。
## 返回值：按统一时间换算规则得到的长按秒数。
func get_required_hold_seconds(equipment: Object) -> float:
	return WorldInteractionTiming.get_hold_duration_seconds(get_effective_time_cost(equipment))


## 读取配置允许的最低采集耗时，避免错误配置产生零耗时。
## 返回值：至少为 1 的最小游戏时间点数。
func get_minimum_time_cost() -> int:
	return maxi(MinimumTimeCost, 1)


## 读取玩家上的装备组件，隔离资源规则与玩家节点协议。
## 参数 player：触发采集的玩家对象，可为空。
## 返回值：装备组件对象；缺失或类型不符时返回 null。
func _get_equipment(player: Object) -> Object:
	if player == null:
		return null
	var value: Variant = player.get("Equipment")
	return value as Object if value is Object else null
