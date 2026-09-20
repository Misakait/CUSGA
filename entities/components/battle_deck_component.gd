extends "res://entities/components/inventory_component.gd"

## 玩家出战卡组的 GDScript 生产实现。
##
## 组件保留技能卡过滤、自动扩容、尾部空槽和按数量展开行为；战斗入口仍接收同一
## SkillCardData Resource 身份，不在这里迁移技能效果或战斗规则。

## 出战卡组始终保留一个空槽，给拖拽入口提供稳定落点。
func _init() -> void:
	DragSourceSystem = &"SystemBattleDeck"
	KeepsTrailingEmptySlot = true


## 只接受暴露 Skill 字段的物品资源（旧 C# SkillCardData 与 GDScript 技能卡都满足该协议）。
##
## 这里刻意不按脚本路径判定：生产物品已全部使用 GDScript，而「脚本是不是 SkillCardData.cs」
## 这类分支会把语言绑定留在生产代码里；旧 C# 类型的 Skill 同样是导出属性，字段协议已完全覆盖。
func _can_store_item(item: Resource) -> bool:
	if item == null:
		return false
	for property_info in item.get_property_list():
		if property_info is Dictionary and StringName(property_info.get("name", "")) == &"Skill":
			return true
	return false


## 出战卡组只要剩余物品属于技能卡，就允许继续扩容。
func _can_provide_additional_capacity(item: Resource, amount: int) -> bool:
	return amount > 0 and _can_store_item(item)


## 按剩余数量提前扩容，并由通知阶段再补一个尾部空槽。
func _prepare_capacity_for_add(item: Resource, amount: int) -> void:
	if item == null or amount <= 0 or ITEM_DATA_COMPAT.call("get_max_stack_size", item, 0) <= 0 or not _can_store_item(item):
		return
	var remaining: int = _count_remaining_after_available_slots(item, amount)
	var max_stack_size: int = int(ITEM_DATA_COMPAT.call("get_max_stack_size", item, 1))
	var additional_slots: int = maxi(0, int(ceil(float(remaining) / float(max_stack_size))))
	EnsureCapacityAtLeast(Capacity + additional_slots)


## 返回按堆叠数量展开后的技能卡资源列表。
func GetSkillCards() -> Array:
	var cards: Array = []
	for slot in Slots:
		if _stack_is_empty(slot) or not _can_store_item(_stack_item(slot)):
			continue
		for _index in _stack_amount(slot):
			cards.append(_stack_item(slot))
	return cards
