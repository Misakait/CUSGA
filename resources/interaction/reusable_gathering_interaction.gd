extends Resource

## 可重复采集地形交互的 GDScript 数据资源（运行时桥接版本）。
##
## 资源本身只负责采集规则、工具减免和操作顺序；实际时间流逝、掉落生成
## 与遭遇请求仍由 TerrainInteractionExecutor 通过操作描述执行，避免资源直
## 接依赖场景节点或棋盘端口。

## 每次采集基础消耗的游戏时间点数。
@export var TimeCost: int = 20

## 用于掉落加成和采集遭遇匹配的资源标签。
@export var GatheringTag: StringName = &""

## 采集完成时滚动的掉落表资源。
@export var DropTable: Resource

## 每轮刷新后可完成的最大采集次数。
@export_range(1, 999, 1, "or_greater") var MaxHarvestCount: int = 1

## 采集次数耗尽后恢复所需的游戏时间点数。
@export_range(0, 9999, 1, "or_greater") var RefreshTimeCost: int = 100

## 工具减免后允许保留的最短游戏时间点数。
@export_range(1, 999, 1, "or_greater") var MinimumTimeCost: int = 1

## 唯一允许提供采集时间减免的装备槽位，数值与 EquipmentSlot 枚举保持一致。
@export var EffectiveToolSlot: int = 5


## 根据装备快照计算本次采集实际消耗的游戏时间点数。
##
## 参数 equipment：玩家的装备组件；为空时不应用工具减免。
## 返回值：不低于 MinimumTimeCost 的有效采集耗时。
func get_effective_time_cost(equipment: Object) -> int:
	var reduction := 0
	if equipment != null and not _has_empty_gathering_tag():
		var value: Variant = equipment.call("GetGatheringTimeReduction", GatheringTag, EffectiveToolSlot)
		if value is int or value is float:
			reduction = maxi(int(value), 0)
	return maxi(get_minimum_time_cost(), maxi(TimeCost, 0) - reduction)


## 根据装备快照计算长按所需的真实秒数。
##
## 参数 equipment：玩家的装备组件；为空时不应用工具减免。
## 返回值：按每 10 点游戏时间折算的长按秒数。
func get_required_hold_seconds(equipment: Object) -> float:
	return WorldInteractionTiming.get_hold_duration_seconds(get_effective_time_cost(equipment))


## 初始化地形实例的可重复采集运行时状态。
##
## 参数 terrain：需要初始化的 TerrainInstance。
## 返回值：无；重复调用不会覆盖已经存在的状态。
func ensure_state(terrain: Object) -> void:
	if terrain == null:
		return
	if int(terrain.get("RemainingGatheringCount")) < 0:
		terrain.set("RemainingGatheringCount", get_max_harvest_count())
		terrain.set("RefreshReadyTotalTime", 0)


## 在冷却到期时恢复地形实例的采集次数。
##
## 参数 terrain：要检查的 TerrainInstance。
## 参数 total_time_passed：当前游戏总时间点数。
## 返回值：无；只有到期且次数耗尽时才会恢复次数。
func refresh_if_ready(terrain: Object, total_time_passed: int) -> void:
	ensure_state(terrain)
	if terrain == null:
		return
	if int(terrain.get("RemainingGatheringCount")) > 0:
		return
	var ready_time := int(terrain.get("RefreshReadyTotalTime"))
	if ready_time <= 0 or total_time_passed < ready_time:
		return
	terrain.set("RemainingGatheringCount", get_max_harvest_count())
	terrain.set("RefreshReadyTotalTime", 0)


## 判断地形当前是否仍可采集，并先处理到期冷却。
##
## 参数 terrain：要检查的 TerrainInstance。
## 参数 total_time_passed：当前游戏总时间点数。
## 返回值：有剩余采集次数时返回 true。
func can_harvest(terrain: Object, total_time_passed: int) -> bool:
	refresh_if_ready(terrain, total_time_passed)
	return terrain != null and int(terrain.get("RemainingGatheringCount")) > 0


## 记录一次已经完成的采集，并在耗尽时安排刷新时间。
##
## 参数 terrain：被采集的 TerrainInstance。
## 参数 total_time_passed：完成采集后的游戏总时间点数。
## 返回值：无；没有剩余次数时不会重复扣减。
func record_successful_harvest(terrain: Object, total_time_passed: int) -> void:
	ensure_state(terrain)
	if terrain == null:
		return
	var remaining := int(terrain.get("RemainingGatheringCount"))
	if remaining <= 0:
		return
	remaining -= 1
	terrain.set("RemainingGatheringCount", remaining)
	if remaining == 0:
		terrain.set("RefreshReadyTotalTime", total_time_passed + maxi(RefreshTimeCost, 0))


## 构建有序的地形操作描述，供 C# 执行器转换为现有 TerrainOp。
##
## 参数 player：触发采集的玩家节点。
## 参数 terrain：被交互的 TerrainInstance。
## 参数 effective_time_cost_override：输入开始时快照的耗时；为空时现场计算。
## 返回值：按执行顺序排列的操作字典数组。
func build_ops(player: Object, terrain: Object, effective_time_cost_override: Variant = null) -> Array[Dictionary]:
	if terrain == null:
		return []
	if not can_harvest(terrain, _get_current_total_time()):
		return []

	var equipment: Object = null
	if player != null:
		var equipment_value: Variant = player.get("Equipment")
		if equipment_value is Object:
			equipment = equipment_value

	var effective_time_cost := get_effective_time_cost(equipment)
	if effective_time_cost_override != null:
		effective_time_cost = maxi(int(effective_time_cost_override), 1)

	var extra_yield := 0
	if equipment != null and not _has_empty_gathering_tag():
		var yield_value: Variant = equipment.call("GetGatheringYieldBonus", GatheringTag)
		if yield_value is int or yield_value is float:
			extra_yield = int(yield_value)

	var loots: Array = []
	if DropTable != null and DropTable.has_method("RollLoot"):
		var loot_value: Variant = DropTable.call("RollLoot", extra_yield)
		if loot_value is Array:
			loots = loot_value

	var ops: Array[Dictionary] = [{"type": "pass_time", "amount": effective_time_cost}]
	if not loots.is_empty():
		ops.append({"type": "spawn_loot", "drops": loots})
	if not _has_empty_gathering_tag():
		ops.append({"type": "check_gathering_encounter", "gathering_tag": GatheringTag})
	ops.append({"type": "record_reusable_gathering"})
	return ops


## 获取配置允许的最小采集耗时，防止错误资源配置产生零耗时。
## 返回值：至少为 1 的最小游戏时间点数。
func get_minimum_time_cost() -> int:
	return maxi(MinimumTimeCost, 1)


## 获取每轮刷新后的最大采集次数，防止次数配置为零导致资源永久不可用。
## 返回值：至少为 1 的最大采集次数。
func get_max_harvest_count() -> int:
	return maxi(MaxHarvestCount, 1)


## 判断采集标签是否为空，兼容旧资源可能反序列化出的空值。
## 返回值：标签为空或未设置时返回 true。
func _has_empty_gathering_tag() -> bool:
	return GatheringTag == null or StringName(GatheringTag).is_empty()


## 读取当前 TimeSystem 的游戏总时间；编辑器或单元测试缺少单例时回退为零。
## 返回值：当前游戏总时间点数。
func _get_current_total_time() -> int:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return 0
	var scene_root: Node = tree.get_root()
	if scene_root == null:
		return 0
	var time_system: Node = scene_root.get_node_or_null("TimeSystem")
	if time_system == null:
		return 0
	var value: Variant = time_system.get("TotalTimePassed")
	return int(value) if value is int or value is float else 0
