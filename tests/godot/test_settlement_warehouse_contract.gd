@tool
extends McpTestSuite

## 轮回真实收获的仓库入库契约，验证数量守恒、属性隔离与满仓余量。
const WAREHOUSE: GDScript = preload("res://entities/components/warehouse_inventory_component.gd")
const ITEM: GDScript = preload("res://resources/item/item_data.gd")
const STACK: GDScript = preload("res://resources/item/item_stack.gd")

## 返回测试发现名称。
## @return 本套件稳定标识。
func suite_name() -> String:
	return "settlement_warehouse_contract"

## 验证批量入库遵守单格上限，不改写来源，且洗炼字典不共享。
## @return 无返回值。
func test_reward_preserves_quantity_identity_and_attributes() -> void:
	var warehouse: Node = _warehouse(2)
	var item: Resource = _item(3)
	var source: RefCounted = _stack(item, 5, {0: 11})
	assert_eq(warehouse.call("AddItemStack", source), 0)
	assert_eq(source.get("Amount"), 5)
	var first: RefCounted = warehouse.call("GetStackAt", 0)
	var second: RefCounted = warehouse.call("GetStackAt", 1)
	assert_eq(first.get("Item"), item)
	assert_eq(first.get("Amount"), 3)
	assert_eq(second.get("Amount"), 2)
	assert_eq(first.get("RolledAttributes"), {0: 11})
	var source_rolled: Dictionary = source.get("RolledAttributes")
	source_rolled[0] = 99
	assert_eq(first.get("RolledAttributes"), {0: 11})
	assert_eq(second.get("RolledAttributes"), {0: 11})

## 验证相同物品但不同属性不混合，部分入库余量准确。
## @return 无返回值。
func test_distinct_attributes_do_not_merge_and_overflow_is_exact() -> void:
	var warehouse: Node = _warehouse(2)
	var item: Resource = _item(3)
	warehouse.call("TrySetStackAt", 0, _stack(item, 2, {0: 11}))
	warehouse.call("TrySetStackAt", 1, _stack(item, 1, {0: 99}))
	var target: RefCounted = warehouse.call("GetStackAt", 0)
	var source: RefCounted = _stack(item, 2, {0: 11})
	assert_eq(warehouse.call("AddItemStack", source), 1)
	assert_eq(warehouse.call("GetStackAt", 0), target)
	assert_eq(target.get("Amount"), 3)
	assert_eq(warehouse.call("GetStackAt", 1).get("Amount"), 1)
	assert_eq(source.get("Amount"), 2)

## 验证满仓时返回全部余量，不消耗或更改真实奖励。
## @return 无返回值。
func test_full_warehouse_keeps_reward_unchanged() -> void:
	var warehouse: Node = _warehouse(1)
	var item: Resource = _item(3)
	warehouse.call("TrySetStackAt", 0, _stack(item, 3))
	var source: RefCounted = _stack(item, 2)
	assert_eq(warehouse.call("AddItemStack", source), 2)
	assert_eq(source.get("Amount"), 2)
	assert_eq(warehouse.call("GetStackAt", 0).get("Amount"), 3)

## 验证当前死亡测试物品可以作为普通真实物品入库。
## @return 无返回值。
func test_real_wheat_reward_uses_normal_warehouse() -> void:
	var warehouse: Node = _warehouse(1)
	var item: Resource = load("res://items/items/wheat.tres")
	assert_eq(warehouse.call("AddItemStack", _stack(item, 1)), 0)
	assert_eq(warehouse.call("GetStackAt", 0).get("Item"), item)
	assert_eq(warehouse.call("GetStackAt", 0).get("Amount"), 1)

func _warehouse(capacity: int) -> Node:
	var warehouse: Node = WAREHOUSE.new()
	warehouse.set("Capacity", capacity)
	track(warehouse)
	return warehouse

func _item(maximum: int) -> Resource:
	var item: Resource = ITEM.new()
	item.set("MaxStackSize", maximum)
	return item

func _stack(item: Resource, amount: int, rolled: Dictionary = {}) -> RefCounted:
	var stack: RefCounted = STACK.new()
	stack.call("SetItem", item, amount)
	stack.set("RolledAttributes", rolled.duplicate(true))
	return stack
