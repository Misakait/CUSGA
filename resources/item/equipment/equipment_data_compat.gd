extends RefCounted

## 装备与工具 Resource 的跨语言只读边界。
## 正式 GDScript 资源使用强类型数组；旧 C# 资源仍可通过此处的历史形状读取。

const ITEM_DATA_COMPAT: GDScript = preload("res://resources/item/item_data_compat.gd")

## 判断输入是否具备完整装备字段。
## 参数 value：待检查资源。返回值：具备全部装备字段时为 true。
static func is_equipment_resource(value: Variant) -> bool:
	return bool(ITEM_DATA_COMPAT.call("is_item_resource", value)) \
		and _has_property(value, &"ValidSlots") \
		and _has_property(value, &"SetType") \
		and _has_property(value, &"AttributeBonuses") \
		and _has_property(value, &"GrantedTags")

## 判断输入是否还具备工具采集字段。
## 参数 value：待检查资源。返回值：具备全部工具字段时为 true。
static func is_tool_resource(value: Variant) -> bool:
	return is_equipment_resource(value) \
		and _has_property(value, &"TargetGatheringTag") \
		and _has_property(value, &"YieldGrowth") \
		and _has_property(value, &"GatheringTimeReduction")

## 读取槽位，兼容旧数组并去掉越界值和重复值。
## 参数 value：装备资源。返回值：合法且去重的槽位整数数组。
static func get_valid_slots(value: Variant) -> Array[int]:
	var slots: Array[int] = []
	var raw_slots: Variant = _get_property(value, &"ValidSlots")
	if not (raw_slots is Array):
		return slots
	for raw_slot in raw_slots:
		var slot := int(raw_slot)
		if slot >= 0 and slot <= 15 and not slots.has(slot):
			slots.append(slot)
	return slots

## 读取套装标识数组；旧数字只在历史输入中映射为稳定字符串。
## 参数 value：装备或套装定义资源。返回值：去重的非空套装标识数组。
static func get_set_types(value: Variant) -> PackedStringArray:
	var result := PackedStringArray()
	var raw_set_type: Variant = _get_property(value, &"SetType")
	if raw_set_type is PackedStringArray or raw_set_type is Array:
		for raw_type in raw_set_type:
			var set_type := String(raw_type).strip_edges()
			if not set_type.is_empty() and not result.has(set_type):
				result.append(set_type)
		return result
	if raw_set_type is String or raw_set_type is StringName:
		var text := String(raw_set_type).strip_edges()
		if not text.is_empty():
			result.append(text)
		return result
	if raw_set_type is int:
		var legacy: Variant = {1: "wooden_set", 2: "stone_set", 3: "iron_set"}.get(int(raw_set_type), "")
		if not String(legacy).is_empty():
			result.append(String(legacy))
	return result

## 兼容旧调用方：返回第一个套装标识的稳定字符串。
## 参数 value：资源；fallback：没有套装时的默认标识。返回值：第一个标识或默认值。
static func get_set_type(value: Variant, fallback: String = "") -> String:
	var types := get_set_types(value)
	return String(types[0]) if not types.is_empty() else fallback

## 读取装备属性范围并合并同属性条目；旧字典直接转换。
## 参数 value：装备资源。返回值：属性编号到合并后 Vector2i 范围的独立字典。
static func get_attribute_bonuses(value: Variant) -> Dictionary:
	var merged: Dictionary = {}
	for entry in _get_attribute_entries(value):
		var attribute := int(entry.get("attribute", -1))
		if attribute < 0 or attribute > 14:
			continue
		var minimum := int(entry.get("minimum", 0))
		var maximum := int(entry.get("maximum", 0))
		var range := Vector2i(mini(minimum, maximum), maxi(minimum, maximum))
		if merged.has(attribute):
			var previous: Vector2i = merged[attribute]
			range = Vector2i(previous.x + range.x, previous.y + range.y)
		merged[attribute] = range
	return merged

## 返回标准化的属性范围条目，供 ItemStack 首次生成和存档白名单使用。
## 参数 value：装备资源。返回值：独立条目数组，每项含 attribute、minimum、maximum。
static func get_attribute_entries(value: Variant) -> Array[Dictionary]:
	return _get_attribute_entries(value)

## 读取装备赋予的标签。
## 参数 value：装备或套装阶级资源。返回值：赋予的非空 StringName 标签数组。
static func get_granted_tags(value: Variant) -> Array[StringName]:
	var tags: Array[StringName] = []
	var raw_tags: Variant = _get_property(value, &"GrantedTags")
	if raw_tags is Array:
		for raw_tag in raw_tags:
			if raw_tag != null and not String(raw_tag).is_empty():
				tags.append(StringName(raw_tag))
	return tags

## 读取工具目标标签。
## 参数 value：工具资源；fallback：缺失时的标签。返回值：目标采集标签。
static func get_target_gathering_tag(value: Variant, fallback: StringName = &"") -> StringName:
	var raw_tag: Variant = _get_property(value, &"TargetGatheringTag")
	return fallback if raw_tag == null else StringName(raw_tag)

## 读取工具额外产量。
## 参数 value：工具资源；fallback：缺失时的数量。返回值：配置的额外产量。
static func get_yield_growth(value: Variant, fallback: int = 0) -> int:
	var raw_growth: Variant = _get_property(value, &"YieldGrowth")
	return fallback if raw_growth == null else int(raw_growth)

## 读取工具耗时减免。
## 参数 value：工具资源；fallback：缺失时的减免。返回值：配置的时间点数。
static func get_gathering_time_reduction(value: Variant, fallback: int = 0) -> int:
	var raw_reduction: Variant = _get_property(value, &"GatheringTimeReduction")
	return fallback if raw_reduction == null else int(raw_reduction)

static func _get_attribute_entries(value: Variant) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var raw_bonuses: Variant = _get_property(value, &"AttributeBonuses")
	if raw_bonuses is Dictionary:
		for raw_attribute in raw_bonuses:
			var raw_range: Variant = raw_bonuses[raw_attribute]
			if raw_range is Vector2i:
				entries.append({"attribute": int(raw_attribute), "minimum": int(raw_range.x), "maximum": int(raw_range.y)})
			elif raw_range is Vector2:
				entries.append({"attribute": int(raw_attribute), "minimum": int(raw_range.x), "maximum": int(raw_range.y)})
		return entries
	if raw_bonuses is Array:
		for bonus in raw_bonuses:
			if not (bonus is Resource):
				continue
			var attribute := int(bonus.get("Attribute"))
			entries.append({"attribute": attribute, "minimum": int(bonus.get("MinValue")), "maximum": int(bonus.get("MaxValue"))})
	return entries

static func _get_property(value: Variant, property_name: StringName) -> Variant:
	if not (value is Object):
		return null
	return (value as Object).get(String(property_name))

static func _has_property(value: Variant, property_name: StringName) -> bool:
	if not (value is Object):
		return false
	for property_info in (value as Object).get_property_list():
		if property_info is Dictionary and StringName(property_info.get("name", "")) == property_name:
			return true
	return false
