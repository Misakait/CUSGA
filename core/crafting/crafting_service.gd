extends RefCounted

## 合成规则服务的并行 GDScript 实现。
##
## 该服务只计算需求、检查材料/空间并执行库存协议，不拥有 UI、信号或配方资产。
## inventory 通过 CanStore、ItemCnt、TryRemoveItems、AddItem 与 Slots 提供稳定边界，
## 因而同一份规则可以在迁移期间接收并行 GDScript Inventory 或旧 C# 兼容节点。

const ITEM_DATA_COMPAT: GDScript = preload("res://resources/item/item_data_compat.gd")

## 与 C# CraftingFailureReason 保持相同整数顺序，供跨语言桥接返回原因码。
enum CraftingFailureReason {
	None,
	InvalidRecipe,
	InvalidQuantity,
	MissingMaterials,
	NotEnoughSpace,
}

## 最近一次 TryCraftWithReason 的失败原因；成功时为 None。
var LastFailureReason: int = CraftingFailureReason.None


## 判断指定数量的配方是否可以完成，不产生库存副作用。
##
## @param inventory 实现库存稳定方法协议的节点或测试夹具。
## @param recipe 具有 Inputs、OutputItem 和 OutputAmount 字段的配方资源。
## @param quantity 本次合成数量，默认值为 1。
## @return 材料与消耗后产物空间均满足时返回 true。
func CanCraft(inventory: Variant, recipe: Variant, quantity: int = 1) -> bool:
	var requirements: Dictionary = TryBuildRequirements(recipe, quantity)
	return not requirements.is_empty() \
		and HasRequiredMaterials(inventory, requirements) \
		and CanReceiveOutputAfterConsuming(inventory, recipe, quantity, requirements)


## 计算当前材料和空间允许的最大合成数量。
##
## @param inventory 实现库存稳定方法协议的节点或测试夹具。
## @param recipe 需要计算的配方资源。
## @return 能够完整执行的最大数量；输入无效或材料不足时返回 0。
func MaxCraftableQuantity(inventory: Variant, recipe: Variant) -> int:
	if inventory == null:
		return 0
	var single_requirements: Dictionary = TryBuildRequirements(recipe, 1)
	if single_requirements.is_empty():
		return 0

	var max_by_materials: int = 2147483647
	for item: Variant in single_requirements:
		var owned: int = _inventory_item_count(inventory, item)
		max_by_materials = mini(max_by_materials, owned / int(single_requirements[item]))
	if max_by_materials <= 0 or max_by_materials == 2147483647:
		return 0

	var low: int = 0
	var high: int = max_by_materials
	while low < high:
		var middle: int = low + ((high - low + 1) / 2)
		if CanCraft(inventory, recipe, middle):
			low = middle
		else:
			high = middle - 1
	return low


## 执行一次合成，并把失败原因写入 LastFailureReason。
##
## @param inventory 实际接收材料与产物的库存节点。
## @param recipe 要执行的配方资源。
## @param quantity 本次合成数量。
## @return 成功完成扣除和产出时返回 true。
func TryCraft(inventory: Variant, recipe: Variant, quantity: int = 1) -> bool:
	return TryCraftWithReason(inventory, recipe, quantity) == CraftingFailureReason.None


## 执行一次合成并返回与 C# 枚举一致的失败原因码。
##
## @param inventory 实际接收材料与产物的库存节点。
## @param recipe 要执行的配方资源。
## @param quantity 本次合成数量。
## @return CraftingFailureReason 的整数值；0 表示成功。
func TryCraftWithReason(inventory: Variant, recipe: Variant, quantity: int = 1) -> int:
	LastFailureReason = CraftingFailureReason.None
	if inventory == null or not _is_recipe_valid(recipe):
		LastFailureReason = CraftingFailureReason.InvalidRecipe
		return LastFailureReason
	if quantity <= 0:
		LastFailureReason = CraftingFailureReason.InvalidQuantity
		return LastFailureReason

	var requirements: Dictionary = TryBuildRequirements(recipe, quantity)
	if requirements.is_empty():
		LastFailureReason = CraftingFailureReason.InvalidQuantity
		return LastFailureReason
	if not HasRequiredMaterials(inventory, requirements):
		LastFailureReason = CraftingFailureReason.MissingMaterials
		return LastFailureReason
	if not CanReceiveOutputAfterConsuming(inventory, recipe, quantity, requirements):
		LastFailureReason = CraftingFailureReason.NotEnoughSpace
		return LastFailureReason
	if not inventory.has_method("TryRemoveItems") or not bool(inventory.call("TryRemoveItems", requirements)):
		LastFailureReason = CraftingFailureReason.MissingMaterials
		return LastFailureReason

	var output_item: Resource = _get_resource(recipe, "OutputItem")
	var output_amount: int = int(_get_property(recipe, "OutputAmount", 0)) * quantity
	if not inventory.has_method("AddItem"):
		LastFailureReason = CraftingFailureReason.NotEnoughSpace
		return LastFailureReason
	var remaining: int = int(inventory.call("AddItem", output_item, output_amount))
	if remaining > 0:
		LastFailureReason = CraftingFailureReason.NotEnoughSpace
		return LastFailureReason
	return LastFailureReason


## 根据配方和数量汇总每种材料的需求量。
##
## @param recipe 配方资源。
## @param quantity 本次合成数量。
## @return 以物品 Resource 为键、需求数量为值的 Dictionary；无效输入返回空字典。
func TryBuildRequirements(recipe: Variant, quantity: int) -> Dictionary:
	var requirements: Dictionary = {}
	if not _is_recipe_valid(recipe) or quantity <= 0:
		return requirements
	for ingredient: Variant in _get_array(recipe, "Inputs"):
		var item: Resource = _get_resource(ingredient, "RequiredItem")
		var amount: int = int(_get_property(ingredient, "Amount", 0))
		var required_amount: int = amount * quantity
		if required_amount > 2147483647:
			return {}
		if requirements.has(item):
			required_amount += int(requirements[item])
			if required_amount > 2147483647:
				return {}
		requirements[item] = required_amount
	return requirements


## 判断库存是否拥有需求字典中的全部材料。
##
## @param inventory 实现 ItemCnt 或 CountWhere 的库存节点。
## @param requirements 物品到数量的需求字典。
## @return 每种物品数量都满足且需求非空时返回 true。
func HasRequiredMaterials(inventory: Variant, requirements: Dictionary) -> bool:
	if inventory == null or requirements.is_empty():
		return false
	for item: Variant in requirements:
		var required_amount: int = int(requirements[item])
		if item == null or required_amount <= 0 or _inventory_item_count(inventory, item) < required_amount:
			return false
	return true


## 在模拟扣除材料后判断库存是否可以容纳产物。
##
## @param inventory 当前库存节点。
## @param recipe 需要检查的配方资源。
## @param quantity 本次合成数量。
## @param requirements 已构建的材料需求。
## @return 消耗材料后可完整加入产物时返回 true。
func CanReceiveOutputAfterConsuming(
	inventory: Variant,
	recipe: Variant,
	quantity: int,
	requirements: Dictionary
) -> bool:
	if inventory == null or not _is_recipe_valid(recipe) or requirements.is_empty():
		return false
	var output_item: Resource = _get_resource(recipe, "OutputItem")
	if output_item == null or not inventory.has_method("CanStore") or not bool(inventory.call("CanStore", output_item)):
		return false
	var output_amount: int = int(_get_property(recipe, "OutputAmount", 0)) * quantity
	if output_amount <= 0 or output_amount > 2147483647 or _max_stack_size(output_item) <= 0:
		return false
	var virtual_slots: Array = _copy_virtual_slots(inventory)
	return _virtual_remove(virtual_slots, requirements) and _virtual_can_add(virtual_slots, output_item, output_amount)


## 判断配方是否包含有效输出与正数材料。
##
## @param recipe 待检查的配方资源。
## @return 配方结构完整且所有材料数量为正时返回 true。
func IsRecipeValid(recipe: Variant) -> bool:
	return _is_recipe_valid(recipe)


## 读取 Resource 或 Node 的属性，隔离旧 C# 与新 GDScript 实现差异。
## @param value 待读取对象。
## @param property_name 字段名。
## @param fallback 字段不存在时的回退值。
## @return 字段值或回退值。
func _get_property(value: Variant, property_name: StringName, fallback: Variant = null) -> Variant:
	if not (value is Object):
		return fallback
	var result: Variant = (value as Object).get(String(property_name))
	return fallback if result == null else result


## 读取 Resource 数组字段，并过滤掉无效元素。
func _get_array(value: Variant, property_name: StringName) -> Array:
	var raw: Variant = _get_property(value, property_name, [])
	return raw as Array if raw is Array else []


## 读取 Resource 字段并在类型不匹配时返回 null。
func _get_resource(value: Variant, property_name: StringName) -> Resource:
	var raw: Variant = _get_property(value, property_name, null)
	return raw as Resource if raw is Resource else null


## 判断配方所有字段是否满足 CraftingService 原有效性规则。
func _is_recipe_valid(recipe: Variant) -> bool:
	if not (recipe is Resource):
		return false
	var output_item: Resource = _get_resource(recipe, "OutputItem")
	var output_amount: int = int(_get_property(recipe, "OutputAmount", 0))
	var inputs: Array = _get_array(recipe, "Inputs")
	if output_item == null or output_amount <= 0 or inputs.is_empty():
		return false
	for ingredient: Variant in inputs:
		var required_item: Resource = _get_resource(ingredient, "RequiredItem")
		if required_item == null or int(_get_property(ingredient, "Amount", 0)) <= 0:
			return false
	return true


## 从库存读取某个物品数量，优先使用跨语言稳定的 ItemCnt。
func _inventory_item_count(inventory: Variant, item: Variant) -> int:
	if inventory == null or item == null:
		return 0
	if inventory.has_method("ItemCnt"):
		return int(inventory.call("ItemCnt", item))
	if inventory.has_method("CountWhere"):
		return int(inventory.call("CountWhere", func(candidate: Variant) -> bool: return _same_item(candidate, item)))
	return 0


## 读取物品最大堆叠值，兼容旧 C# ItemData 的计算属性。
func _max_stack_size(item: Variant) -> int:
	return int(ITEM_DATA_COMPAT.call("get_max_stack_size", item, 99))


## 按 Resource 身份比较物品，不用 CardId 合并不同实例。
func _same_item(left: Variant, right: Variant) -> bool:
	return bool(ITEM_DATA_COMPAT.call("same_item", left, right))


## 复制库存槽位为可变的轻量虚拟槽位。
func _copy_virtual_slots(inventory: Variant) -> Array:
	var result: Array = []
	var raw_slots: Variant = inventory.get("Slots") if inventory is Object else []
	if not (raw_slots is Array):
		return result
	for stack: Variant in raw_slots:
		var item: Resource = null if stack == null else stack.get("Item") as Resource
		var amount: int = 0 if stack == null else int(stack.get("Amount"))
		result.append({"Item": item if amount > 0 else null, "Amount": amount if amount > 0 else 0})
	return result


## 从后往前模拟扣除材料，保持 C# VirtualInventory 的槽位顺序。
func _virtual_remove(slots: Array, requirements: Dictionary) -> bool:
	for item: Variant in requirements:
		var remaining: int = int(requirements[item])
		for index in range(slots.size() - 1, -1, -1):
			if remaining <= 0:
				break
			var slot: Dictionary = slots[index]
			if slot["Item"] == null or not _same_item(slot["Item"], item):
				continue
			var removed: int = mini(int(slot["Amount"]), remaining)
			slot["Amount"] = int(slot["Amount"]) - removed
			if int(slot["Amount"]) <= 0:
				slot["Item"] = null
			remaining -= removed
		if remaining > 0:
			return false
	return true


## 在虚拟槽位中先填同物品堆叠，再填空槽位。
func _virtual_can_add(slots: Array, item: Resource, amount: int) -> bool:
	var remaining: int = amount
	var max_stack: int = _max_stack_size(item)
	if item == null or remaining <= 0 or max_stack <= 0:
		return false
	for slot: Dictionary in slots:
		if slot["Item"] == null or not _same_item(slot["Item"], item):
			continue
		var available: int = max_stack - int(slot["Amount"])
		if available <= 0:
			continue
		var added: int = mini(available, remaining)
		slot["Amount"] = int(slot["Amount"]) + added
		remaining -= added
		if remaining <= 0:
			return true
	for slot: Dictionary in slots:
		if slot["Item"] != null:
			continue
		var added: int = mini(max_stack, remaining)
		slot["Item"] = item
		slot["Amount"] = added
		remaining -= added
		if remaining <= 0:
			return true
	return remaining <= 0
