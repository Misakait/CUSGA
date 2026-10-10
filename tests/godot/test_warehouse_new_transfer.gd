@tool
extends McpTestSuite

## 仓库拖放的权威状态契约：跨区交换、堆叠溢出、失效来源和解锁边界。
const TRANSFER: GDScript = preload("res://core/ui/warehouse/warehouse_transfer.gd")
const INVENTORY: GDScript = preload("res://entities/components/inventory_component.gd")
const CARRY: GDScript = preload("res://core/autoloads/ItemsControl.gd")
const ITEM: GDScript = preload("res://resources/item/item_data.gd")

## 返回稳定测试套件名称；返回 warehouse_new_transfer。
func suite_name() -> String:
	return "warehouse_new_transfer"

## 验证双向转移及跨区交换不复制或丢失数量；返回无。
func test_cross_section_moves_and_swap_conserve_items() -> void:
	var fixture: Dictionary = _fixture()
	var warehouse: Node = fixture["warehouse"]
	var carry: Node = fixture["carry"]
	var transfer: RefCounted = fixture["transfer"]
	var apple: Resource = _item("苹果", 99)
	var wood: Resource = _item("木材", 99)
	warehouse.call("AddItem", apple, 12)
	carry.call("SetCarryEntry", 0, wood, 7)
	assert_true(bool(transfer.call("move", _drag(transfer, &"warehouse", 0), &"carry", 0)))
	assert_eq(warehouse.call("ItemCnt", wood), 7)
	assert_eq(warehouse.call("ItemCnt", apple), 0)
	var entry: Dictionary = carry.call("GetCarryEntry", 0)
	assert_eq(entry.get("item"), apple)
	assert_eq(entry.get("count"), 12)
	assert_true(bool(transfer.call("move", _drag(transfer, &"carry", 0), &"warehouse", 2)))
	assert_eq(warehouse.call("ItemCnt", apple), 12)
	entry = carry.call("GetCarryEntry", 0)
	assert_eq(entry.get("count"), 0)

## 验证合并溢出仍留在原位置，而且满堆叠拒绝无效投放；返回无。
func test_partial_merge_keeps_remainder_and_full_target_rejects() -> void:
	var fixture: Dictionary = _fixture()
	var warehouse: Node = fixture["warehouse"]
	var carry: Node = fixture["carry"]
	var transfer: RefCounted = fixture["transfer"]
	var item: Resource = _item("石块", 10)
	warehouse.call("AddItem", item, 8)
	carry.call("SetCarryEntry", 0, item, 7)
	assert_true(bool(transfer.call("move", _drag(transfer, &"warehouse", 0), &"carry", 0)))
	assert_eq(warehouse.call("ItemCnt", item), 5)
	var entry: Dictionary = carry.call("GetCarryEntry", 0)
	assert_eq(entry.get("count"), 10)
	assert_false(bool(transfer.call("move", _drag(transfer, &"warehouse", 0), &"carry", 0)))
	assert_eq(warehouse.call("ItemCnt", item), 5)
	assert_true(bool(transfer.call("move", _drag(transfer, &"carry", 0), &"warehouse", 0)))
	assert_eq(warehouse.call("ItemCnt", item), 10)
	entry = carry.call("GetCarryEntry", 0)
	assert_eq(entry.get("count"), 5)

## 验证同区移动与交换保持行囊权威，保留仓库独立属性；返回无。
func test_same_section_moves_and_warehouse_attributes() -> void:
	var fixture: Dictionary = _fixture()
	var warehouse: Node = fixture["warehouse"]
	var carry: Node = fixture["carry"]
	var transfer: RefCounted = fixture["transfer"]
	var item: Resource = _item("独立工具", 1)
	var other: Resource = _item("木头", 99)
	warehouse.call("AddItem", item, 1)
	var stack: Variant = warehouse.call("GetStackAt", 0)
	var original_slot: Object = stack
	stack.set("RolledAttributes", {"power": 13})
	assert_true(bool(transfer.call("move", _drag(transfer, &"warehouse", 0), &"warehouse", 2)))
	assert_eq(warehouse.call("GetStackAt", 0), original_slot)
	stack = warehouse.call("GetStackAt", 2)
	assert_eq(stack.get("RolledAttributes"), {"power": 13})
	carry.call("SetCarryEntry", 0, other, 7)
	carry.call("SetCarryEntry", 1, item, 1)
	assert_true(bool(transfer.call("move", _drag(transfer, &"carry", 0), &"carry", 1)))
	var entry: Dictionary = carry.call("GetCarryEntry", 1)
	assert_eq(entry.get("item"), other)
	assert_eq(entry.get("count"), 7)
	entry = carry.call("GetCarryEntry", 0)
	assert_eq(entry.get("item"), item)
	carry.call("SetCarryEntry", 2, other, 3)
	assert_true(bool(transfer.call("move", _drag(transfer, &"carry", 2), &"carry", 1)))
	entry = carry.call("GetCarryEntry", 1)
	assert_eq(entry.get("count"), 10)

## 验证过期快照、未知区域、越界及未解锁目标无副作用；返回无。
func test_stale_sources_and_locked_slots_are_rejected() -> void:
	var fixture: Dictionary = _fixture()
	var warehouse: Node = fixture["warehouse"]
	var carry: Node = fixture["carry"]
	var transfer: RefCounted = fixture["transfer"]
	var item: Resource = _item("石块", 99)
	warehouse.call("AddItem", item, 5)
	var stale: Dictionary = _drag(transfer, &"warehouse", 0)
	warehouse.call("AddItem", item, 1)
	assert_false(bool(transfer.call("move", stale, &"carry", 0)))
	var current: Dictionary = _drag(transfer, &"warehouse", 0)
	for side: StringName in [&"carry", &"unknown"]:
		assert_false(bool(transfer.call("move", current, side, 5)))
	assert_false(bool(transfer.call("move", current, &"warehouse", -1)))
	assert_false(bool(transfer.call("move", current, &"warehouse", 0)))
	assert_eq(warehouse.call("ItemCnt", item), 6)
	assert_false(bool(carry.call("HasCarryItems")))
	assert_false(bool(transfer.call("can_move", {}, &"carry", 0)))
	assert_false(bool(transfer.call("can_move", {"side": 12, "index": null}, &"carry", 0)))
	current["amount"] = "six"
	assert_false(bool(transfer.call("can_move", current, &"carry", 0)))

## 验证相同 CardId 的不同资源仍交换，不能把独立资源按名称合并；返回无。
func test_same_card_id_keeps_resource_identity() -> void:
	var fixture: Dictionary = _fixture()
	var warehouse: Node = fixture["warehouse"]
	var carry: Node = fixture["carry"]
	var transfer: RefCounted = fixture["transfer"]
	var left: Resource = _item("相同名称", 10)
	var right: Resource = _item("相同名称", 10)
	left.set("CardId", &"same_id")
	right.set("CardId", &"same_id")
	warehouse.call("AddItem", left, 5)
	carry.call("SetCarryEntry", 0, right, 10)
	assert_true(bool(transfer.call("move", _drag(transfer, &"warehouse", 0), &"carry", 0)))
	assert_eq(warehouse.call("ItemCnt", right), 10)
	var entry: Dictionary = carry.call("GetCarryEntry", 0)
	assert_eq(entry.get("item"), left)
	assert_eq(entry.get("count"), 5)

func _fixture() -> Dictionary:
	var warehouse: Node = track(INVENTORY.new()) as Node
	warehouse.set("Capacity", 6)
	var carry: Node = track(CARRY.new()) as Node
	var transfer: RefCounted = TRANSFER.new()
	transfer.call("bind", warehouse, carry, 5)
	return {"warehouse": warehouse, "carry": carry, "transfer": transfer}

func _item(display_name: String, maximum: int) -> Resource:
	var item: Resource = ITEM.new()
	item.set("CardName", display_name)
	item.set("MaxStackSize", maximum)
	return item

func _drag(transfer: RefCounted, side: StringName, index: int) -> Dictionary:
	var data: Dictionary = transfer.call("snapshot", side, index)
	data.merge({"side": side, "index": index})
	return data
