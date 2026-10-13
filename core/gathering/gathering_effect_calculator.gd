extends RefCounted
class_name GatheringEffectCalculator

## 采集规则共享计算器。
##
## 该类只读取装备组件公开的查询协议，不保存玩家或资源点状态。
## 一次性采集和可重复采集必须通过同一公式计算耗时，避免长按显示值与实际扣除值分叉。

## 计算工具减免后的实际采集耗时。
##
## 参数 equipment：实现 GetGatheringTimeReduction 的装备组件，可为空。
## 参数 gathering_tag：采集资源标签；空标签不会触发工具效果。
## 参数 effective_tool_slot：允许生效的工具槽位整数值。
## 参数 base_time_cost：资源基础耗时，负数按 0 处理。
## 参数 minimum_time_cost：减免后的最低耗时，最低按 1 处理。
## 返回值：至少为 1 的实际游戏时间点数。
static func get_effective_time_cost(
	equipment: Object,
	gathering_tag: StringName,
	effective_tool_slot: int,
	base_time_cost: int,
	minimum_time_cost: int
) -> int:
	var reduction := get_time_reduction(equipment, gathering_tag, effective_tool_slot)
	var base := maxi(base_time_cost, 0)
	return maxi(maxi(minimum_time_cost, 1), base - reduction)


## 读取装备组件对指定采集标签和槽位的耗时减免。
##
## 参数 equipment：实现查询协议的装备组件，可为空。
## 参数 gathering_tag：采集资源标签；空标签直接返回 0。
## 参数 effective_tool_slot：允许生效的工具槽位整数值。
## 返回值：非负耗时减免；查询协议缺失或类型无效时返回 0。
static func get_time_reduction(
	equipment: Object,
	gathering_tag: StringName,
	effective_tool_slot: int
) -> int:
	if equipment == null or gathering_tag == null or StringName(gathering_tag).is_empty():
		return 0
	if not equipment.has_method("GetGatheringTimeReduction"):
		return 0
	var value: Variant = equipment.call("GetGatheringTimeReduction", gathering_tag, effective_tool_slot)
	if value is int or value is float:
		return maxi(int(value), 0)
	return 0


## 读取所有匹配工具提供的额外产量。
##
## 参数 equipment：实现 GetGatheringYieldBonus 的装备组件，可为空。
## 参数 gathering_tag：采集资源标签；空标签不会触发工具效果。
## 返回值：非负额外产量；查询协议缺失或类型无效时返回 0。
static func get_yield_bonus(equipment: Object, gathering_tag: StringName) -> int:
	if equipment == null or gathering_tag == null or StringName(gathering_tag).is_empty():
		return 0
	if not equipment.has_method("GetGatheringYieldBonus"):
		return 0
	var value: Variant = equipment.call("GetGatheringYieldBonus", gathering_tag)
	if value is int or value is float:
		return maxi(int(value), 0)
	return 0


## 把传入的长按耗时限制为有效的采集时间。
##
## 参数 snapshot：长按开始时记录的耗时，可为空。
## 参数 fallback：没有快照时现场计算的耗时。
## 返回值：有效的实际耗时，至少为 1。
static func resolve_time_cost(snapshot: Variant, fallback: int) -> int:
	if snapshot is int or snapshot is float:
		return maxi(int(snapshot), 1)
	return maxi(fallback, 1)
