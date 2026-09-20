extends Resource

## 一次性采集地形交互的 GDScript 数据资源。
##
## 资源只负责读取采集配置并生成有序操作描述；时间流逝、地形状态、
## 掉落卡生成、遭遇请求和源卡移除继续由 TerrainInteractionExecutor 执行。

## 完成采集消耗的游戏时间点数。
@export var TimeCost: int = 20

## 用于装备额外产量和采集遭遇匹配的资源标签。
@export var GatheringTag: StringName = &""

## 完成采集时滚动的掉落表；生产使用 GDScript，并继续接受旧 C# LootTable。
@export var DropTable: Resource


## 构建与旧 GatheringInteraction 相同顺序的操作描述。
##
## 参数 player：触发采集的玩家节点，用于读取装备额外产量。
## 参数 terrain：被交互的 TerrainInstance，用于判断是否已经采集。
## 参数 effective_time_cost_override：统一长按入口传入的耗时快照；一次性采集保持旧行为并忽略它。
## 返回值：依次包含时间、采集标记、可选掉落、遭遇检查和源卡移除的操作数组。
func build_ops(
	player: Object,
	terrain: Object,
	_effective_time_cost_override: Variant = null
) -> Array[Dictionary]:
	var ops: Array[Dictionary] = [
		{"type": "pass_time", "amount": TimeCost},
		{"type": "mark_harvested"},
	]

	# 旧实现只在构建操作时尚未采集的地形上滚动掉落，但仍会执行后续遭遇与移除。
	if terrain != null and not bool(terrain.get("IsHarvested")):
		var extra_yield := 0
		var equipment: Object = null
		if player != null:
			var equipment_value: Variant = player.get("Equipment")
			if equipment_value is Object:
				equipment = equipment_value
		if equipment != null and equipment.has_method("GetGatheringYieldBonus"):
			var yield_value: Variant = equipment.call("GetGatheringYieldBonus", GatheringTag)
			if yield_value is int or yield_value is float:
				extra_yield = int(yield_value)

		var loots: Array = []
		if DropTable != null and DropTable.has_method("RollLoot"):
			var loot_value: Variant = DropTable.call("RollLoot", extra_yield)
			if loot_value is Array:
				loots = loot_value
		if not loots.is_empty():
			ops.append({"type": "spawn_loot", "drops": loots})

	ops.append({"type": "check_gathering_encounter", "gathering_tag": GatheringTag})
	ops.append({"type": "remove_source_card"})
	return ops
