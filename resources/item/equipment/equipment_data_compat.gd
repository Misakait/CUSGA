extends RefCounted

## 装备与工具 Resource 的跨语言只读边界。
##
## 生产资产由 GDScript EquipmentData/ToolData 提供，旧 C# Resource 继续作为兼容输入。
## 本工具只按稳定字段读取，不包装、不复制 Resource 对象，避免改变物品身份和堆叠语义。

const ITEM_DATA_COMPAT: GDScript = preload("res://resources/item/item_data_compat.gd")


## 判断输入是否具备装备数据的完整稳定字段集合。
static func is_equipment_resource(value: Variant) -> bool:
	if not bool(ITEM_DATA_COMPAT.call("is_item_resource", value)):
		return false
	return _has_property(value, &"ValidSlots") \
		and _has_property(value, &"SetType") \
		and _has_property(value, &"AttributeBonuses") \
		and _has_property(value, &"GrantedTags")


## 判断输入是否在装备字段之上还具备工具采集字段。
static func is_tool_resource(value: Variant) -> bool:
	return is_equipment_resource(value) \
		and _has_property(value, &"TargetGatheringTag") \
		and _has_property(value, &"YieldGrowth") \
		and _has_property(value, &"GatheringTimeReduction")


## 读取允许装备的槽位，并统一成旧 EquipmentSlot 的整数值数组。
static func get_valid_slots(value: Variant) -> Array[int]:
	var slots: Array[int] = []
	var raw_slots: Variant = _get_property(value, &"ValidSlots")
	if not (raw_slots is Array):
		return slots
	for raw_slot in raw_slots:
		slots.append(int(raw_slot))
	return slots


## 读取套装类型整数值；缺失时回退到 None=0。
static func get_set_type(value: Variant, fallback: int = 0) -> int:
	var raw_set_type: Variant = _get_property(value, &"SetType")
	return fallback if raw_set_type == null else int(raw_set_type)


## 读取装备属性加成并返回独立字典，防止消费者误改 Resource 配置。
static func get_attribute_bonuses(value: Variant) -> Dictionary:
	var raw_bonuses: Variant = _get_property(value, &"AttributeBonuses")
	return (raw_bonuses as Dictionary).duplicate(true) if raw_bonuses is Dictionary else {}


## 读取装备赋予的标签，并统一成 StringName 数组。
static func get_granted_tags(value: Variant) -> Array[StringName]:
	var tags: Array[StringName] = []
	var raw_tags: Variant = _get_property(value, &"GrantedTags")
	if not (raw_tags is Array):
		return tags
	for raw_tag in raw_tags:
		if raw_tag != null:
			tags.append(StringName(raw_tag))
	return tags


## 读取工具生效的采集标签；缺失时返回空标签。
static func get_target_gathering_tag(value: Variant, fallback: StringName = &"") -> StringName:
	var raw_tag: Variant = _get_property(value, &"TargetGatheringTag")
	return fallback if raw_tag == null else StringName(raw_tag)


## 读取工具额外产量；缺失时返回 0，不在数据边界改写负值。
static func get_yield_growth(value: Variant, fallback: int = 0) -> int:
	var raw_growth: Variant = _get_property(value, &"YieldGrowth")
	return fallback if raw_growth == null else int(raw_growth)


## 读取工具采集时间减免；缺失时返回 0，由运行时调用方决定是否限制为非负数。
static func get_gathering_time_reduction(value: Variant, fallback: int = 0) -> int:
	var raw_reduction: Variant = _get_property(value, &"GatheringTimeReduction")
	return fallback if raw_reduction == null else int(raw_reduction)


## 按属性名读取 C# 或 GDScript 对象的导出值。
static func _get_property(value: Variant, property_name: StringName) -> Variant:
	if not (value is Object):
		return null
	return (value as Object).get(String(property_name))


## 检查对象属性表，避免普通 ItemData 被误判为装备或工具。
static func _has_property(value: Variant, property_name: StringName) -> bool:
	if not (value is Object):
		return false
	for property_info in (value as Object).get_property_list():
		if not (property_info is Dictionary):
			continue
		var name_value: Variant = property_info.get("name")
		if name_value != null and StringName(name_value) == property_name:
			return true
	return false
