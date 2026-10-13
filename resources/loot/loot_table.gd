extends Resource
class_name LootTableData

## 掉落表的生产 GDScript 实现。
##
## 每个 LootDrop 独立判定概率与数量，并生成物品堆叠；保留原始物品资源身份。

## 用于创建生产掉落结果的 GDScript 物品堆叠脚本。
const ITEM_STACK_SCRIPT: GDScript = preload("res://resources/item/item_stack.gd")
const EQUIPMENT_DATA_COMPAT: GDScript = preload("res://resources/item/equipment/equipment_data_compat.gd")

## 掉落条目列表；新增元素时创建 LootDrop，并配置物品、概率和数量。
@export var Drops: Array[LootDrop] = []


## 按掉落概率和数量范围生成物品堆叠。
## 参数 yield_growth：采集或遭遇规则提供的额外掉落数量，可为负数。
## 返回值：生成的 GDScript ItemStack 数组；无有效掉落时返回空数组。
func RollLoot(yield_growth: int) -> Array[RefCounted]:
	## 本次成功生成的全部物品堆叠。
	var generated_loot: Array[RefCounted] = []
	for drop: Resource in Drops:
		if drop == null:
			continue
		## 条目保存的原始物品 Resource 引用。
		var item_value: Variant = _read_property(drop, &"Item", null)
		if not (item_value is Resource):
			continue
		## 保留原始物品资源，避免生成掉落时复制共享配置。
		var item := item_value as Resource
		## 旧实现使用 0 到 100 的浮点随机数，并以小于等于判断命中。
		var roll: float = randf() * 100.0
		## 条目配置的掉落概率。
		var drop_chance: float = _read_float(drop, &"DropChance", 100.0)
		if roll > drop_chance:
			continue
		## 随机数量范围的下界。
		var minimum_amount: int = _read_int(drop, &"MinAmount", 1)
		## 随机数量范围的上界。
		var maximum_amount: int = _read_int(drop, &"MaxAmount", 1)
		## 旧实现使用包含两端的整数随机数量。
		var base_amount: int = randi_range(minimum_amount, maximum_amount)
		## 应用额外产量后的最终数量。
		var final_amount: int = base_amount + yield_growth
		if final_amount <= 0:
			continue
		## 不可堆叠装备必须每件独立生成；普通物品保留原有单堆掉落形状。
		if bool(EQUIPMENT_DATA_COMPAT.call("is_equipment_resource", item)):
			var remaining: int = final_amount
			while remaining > 0:
				var equipment_stack := ITEM_STACK_SCRIPT.new() as RefCounted
				equipment_stack.call("SetItem", item, 1)
				equipment_stack.call("RollRandomStats")
				generated_loot.append(equipment_stack)
				remaining -= 1
		else:
			var stack := ITEM_STACK_SCRIPT.new() as RefCounted
			stack.call("SetItem", item, final_amount)
			stack.call("RollRandomStats")
			generated_loot.append(stack)
	return generated_loot


## 读取条目的浮点字段，并在字段缺失或类型不符时使用默认值。
## 参数 drop：待读取的掉落条目。
## 参数 property_name：序列化字段名。
## 参数 fallback：无法读取时的默认值。
## 返回值：字段的浮点值或默认值。
static func _read_float(drop: Resource, property_name: StringName, fallback: float) -> float:
	## 尚未确定类型的字段值。
	var value: Variant = _read_property(drop, property_name, fallback)
	return float(value) if value is float or value is int else fallback


## 读取条目的整数字段，并在字段缺失或类型不符时使用默认值。
## 参数 drop：待读取的掉落条目。
## 参数 property_name：序列化字段名。
## 参数 fallback：无法读取时的默认值。
## 返回值：字段的整数值或默认值；浮点字段按旧实现截断。
static func _read_int(drop: Resource, property_name: StringName, fallback: int) -> int:
	## 尚未确定类型的字段值。
	var value: Variant = _read_property(drop, property_name, fallback)
	return int(value) if value is int or value is float else fallback


## 仅在条目真实声明字段时读取，避免兼容输入缺字段产生运行时错误。
## 参数 drop：待读取的掉落条目。
## 参数 property_name：序列化字段名。
## 参数 fallback：字段不存在时的默认值。
## 返回值：字段原值或默认值。
static func _read_property(drop: Resource, property_name: StringName, fallback: Variant) -> Variant:
	if drop == null:
		return fallback
	for property_info: Dictionary in drop.get_property_list():
		## 当前属性描述中的名称。
		var name_value: Variant = property_info.get("name")
		if name_value != null and StringName(name_value) == property_name:
			return drop.get(String(property_name))
	return fallback
