extends RefCounted

## 新仓库的短期行囊适配器。参数通过 bind 注入，结果仍写回既有权威。
const INVENTORY: GDScript = preload("res://entities/components/inventory_component.gd")
const ITEM_COMPAT: GDScript = preload("res://resources/item/item_data_compat.gd")

var _warehouse: Node
var _carry: Node
var _capacity: int = 0

## 绑定物品权威。参数 warehouse 为仓库，carry 为行囊，capacity 为已解锁容量；返回无。
func bind(warehouse: Node, carry: Node, capacity: int) -> void:
	_warehouse = warehouse
	_carry = carry
	_capacity = clampi(capacity, 0, 10)

## 获取槽位快照。参数 side 为 warehouse/carry，index 为位置；返回物品、数量、洗炼属性。
func snapshot(side: StringName, index: int) -> Dictionary:
	if not _valid_index(side, index):
		return {}
	if side == &"carry":
		var entry: Dictionary = _carry.call("GetCarryEntry", index)
		return {"item": entry.get("item"), "amount": int(entry.get("count", 0)), "rolled": {}}
	var stack: Variant = _warehouse.call("GetStackAt", index)
	return {"item": stack.get("Item"), "amount": int(stack.get("Amount")), "rolled": stack.get("RolledAttributes").duplicate(true)}

## 检查拖放。参数 data 为来源快照，side/index 为目标；返回来源仍有效且目标允许接收。
func can_move(data: Dictionary, side: StringName, index: int) -> bool:
	# 其它控件也可能提供字典拖动载荷，先验证形状，再转换索引和区域。
	if not (data.get("side") is String or data.get("side") is StringName) or not data.get("index") is int:
		return false
	if not data.get("amount") is int or not data.get("rolled") is Dictionary or not data.get("item") is Resource:
		return false
	var source_side: StringName = StringName(data.get("side", ""))
	var source_index: int = int(data.get("index", -1))
	if not _valid_index(source_side, source_index) or not _valid_index(side, index):
		return false
	if source_side == side and source_index == index:
		return false
	var current: Dictionary = snapshot(source_side, source_index)
	if current.get("item") == null or int(current.get("amount", 0)) <= 0:
		return false
	if current.get("item") != data.get("item") or current.get("amount") != data.get("amount") or current.get("rolled") != data.get("rolled"):
		return false
	var bridge: Node = _carry_inventory()
	var source: Node = bridge if source_side == &"carry" else _warehouse
	var target: Node = bridge if side == &"carry" else _warehouse
	var accepted: bool = bool(target.call("CanReceiveItemFrom", source, source_index, index))
	var target_stack: Variant = target.call("GetStackAt", index)
	# 满堆叠不发生变化，因此不显示成可投放目标。
	if bool(ITEM_COMPAT.call("same_item", target_stack.get("Item"), current.get("item"))) and bool(target_stack.get("IsFull")):
		accepted = false
	bridge.free()
	return accepted

## 提交拖放。参数 data 为来源快照，side/index 为目标；返回成功与否，失败无副作用。
func move(data: Dictionary, side: StringName, index: int) -> bool:
	if not can_move(data, side, index):
		return false
	var source_side: StringName = StringName(data["side"])
	var source_index: int = int(data["index"])
	if source_side == &"warehouse" and side == &"warehouse":
		_warehouse.call("MoveItem", source_index, index)
		return true
	var bridge: Node = _carry_inventory()
	var source: Node = bridge if source_side == &"carry" else _warehouse
	var target: Node = bridge if side == &"carry" else _warehouse
	# 暂存仅活到这次提交结束；先完成合并/交换，再写回行囊，避免信号回调重建中间快照。
	target.call("MoveItemFromDeferred", source, source_index, index)
	for position: int in _capacity:
		var stack: Variant = bridge.call("GetStackAt", position)
		var old: Dictionary = _carry.call("GetCarryEntry", position)
		if old.get("item") != stack.get("Item") or int(old.get("count", 0)) != int(stack.get("Amount")):
			_carry.call("SetCarryEntry", position, stack.get("Item"), int(stack.get("Amount")))
	bridge.free()
	# 目标和来源槽位都落定之后才广播仓库变化，存档采集不会看到未提交的物品副本。
	if source_side == &"warehouse" or side == &"warehouse":
		_warehouse.emit_signal("InventoryChanged")
	return true

func _valid_index(side: StringName, index: int) -> bool:
	if index < 0:
		return false
	if side == &"warehouse":
		return is_instance_valid(_warehouse) and index < int(_warehouse.get("Capacity"))
	if side == &"carry":
		return is_instance_valid(_carry) and index < _capacity
	return false

func _carry_inventory() -> Node:
	var bridge: Node = INVENTORY.new()
	bridge.set("Capacity", _capacity)
	for index: int in _capacity:
		var entry: Dictionary = _carry.call("GetCarryEntry", index)
		var stack: Variant = bridge.call("GetStackAt", index)
		stack.call("SetItem", entry.get("item"), int(entry.get("count", 0)))
	return bridge
