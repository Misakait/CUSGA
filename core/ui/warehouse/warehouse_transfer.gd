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

## 判断目标能否按数量接收来源物品：只接受空格或同类未满格。
## 参数 data 为来源快照、side/index 为目标、amount 为希望接收的数量；返回布尔，无副作用。
func can_receive_amount(data: Dictionary, side: StringName, index: int, amount: int) -> bool:
	# 形状校验与 can_move 同源：其它控件传来的字典载荷在这一层被统一筛掉。
	if amount <= 0 or not _valid_index(side, index):
		return false
	if not (data.get("side") is String or data.get("side") is StringName) or not data.get("index") is int:
		return false
	if not data.get("amount") is int or not data.get("rolled") is Dictionary or not data.get("item") is Resource:
		return false
	var source_side: StringName = StringName(data.get("side", ""))
	var source_index: int = int(data.get("index", -1))
	if not _valid_index(source_side, source_index):
		return false
	if source_side == side and source_index == index:
		return false
	var current: Dictionary = snapshot(source_side, source_index)
	var source_item: Resource = current.get("item") as Resource
	if source_item == null or int(current.get("amount", 0)) <= 0:
		return false
	# 快照必须与权威逐项相等，否则来源已被外部改动，本次提交按过期处理。
	if source_item != data.get("item") or current.get("amount") != data.get("amount") or current.get("rolled") != data.get("rolled"):
		return false
	var bridge: Node = _carry_inventory()
	var source: Node = bridge if source_side == &"carry" else _warehouse
	var target: Node = bridge if side == &"carry" else _warehouse
	var accepted: bool = bool(target.call("CanReceiveItemFrom", source, source_index, index))
	# 按数量搬运不做交换：已占用但不是「同类未满格」的格子一律拒绝。
	var target_stack: Variant = target.call("GetStackAt", index)
	if not bool(target_stack.get("IsEmpty")):
		var same: bool = bool(ITEM_COMPAT.call("same_item", target_stack.get("Item"), source_item))
		accepted = accepted and same and not bool(target_stack.get("IsFull"))
	bridge.free()
	return accepted

## 按数量把物品从来源搬到目标；只接受空格或同类未满格。
## 参数 data 为来源快照、side/index 为目标、amount 为希望移动的数量；
## 返回实际移动数量（0 表示未移动），失败时权威不变。
func move_amount(data: Dictionary, side: StringName, index: int, amount: int) -> int:
	if not can_receive_amount(data, side, index, amount):
		return 0
	var source_side: StringName = StringName(data["side"])
	var source_index: int = int(data["index"])
	var source_item: Resource = data["item"] as Resource
	var bridge: Node = _carry_inventory()
	var source: Node = bridge if source_side == &"carry" else _warehouse
	var target: Node = bridge if side == &"carry" else _warehouse
	var source_stack: Variant = source.call("GetStackAt", source_index)
	var target_stack: Variant = target.call("GetStackAt", index)
	# 真正搬走的数量同时受「请求量」「来源现有量」「目标剩余空间」三重限制。
	# 只按请求量扣来源，会在目标空间不足时凭空丢掉物品，所以先把上限算出来再动权威。
	var available: int = _receivable_space(target_stack, source_item)
	var moved: int = mini(mini(amount, int(data["amount"])), available)
	if moved <= 0:
		bridge.free()
		return 0
	# SetItem 会清空 RolledAttributes，先备份、剩余为正时再写回，保证洗炼属性不丢。
	var rolled: Dictionary = _rolled_attributes(source_stack)
	if bool(target_stack.get("IsEmpty")):
		target_stack.call("SetItem", source_item, moved)
		_restore_rolled_attributes(target_stack, rolled)
	else:
		target_stack.call("Add", moved)
	var left: int = int(source_stack.get("Amount")) - moved
	source_stack.call("SetItem", source_item, left)
	if left > 0:
		_restore_rolled_attributes(source_stack, rolled)
	# 行囊暂存只活到本次提交结束：两侧堆叠改完再写回权威，信号回调不会读到中间状态。
	if source_side == &"carry" or side == &"carry":
		_write_back_carry(bridge)
	bridge.free()
	if source_side == &"warehouse" or side == &"warehouse":
		# 与 move() 一致：仓库侧提交完成后才广播，行囊侧由 SetCarryEntry 自行广播。
		_warehouse.call("_notify_inventory_changed")
	return moved

## 计算目标堆叠还能接收多少来源物品；空槽按最大堆叠计算，不同物品返回 0。
func _receivable_space(stack: Variant, item: Resource) -> int:
	if bool(stack.get("IsEmpty")):
		return int(ITEM_COMPAT.call("get_max_stack_size", item, 99))
	if not bool(ITEM_COMPAT.call("same_item", stack.get("Item"), item)):
		return 0
	return int(stack.get("AvailableSpace"))

## 读取堆叠的洗炼属性副本；缺字段时返回空字典，避免把 null 当成有效属性表。
func _rolled_attributes(stack: Variant) -> Dictionary:
	var rolled: Variant = stack.get("RolledAttributes")
	return (rolled as Dictionary).duplicate(true) if rolled is Dictionary else {}

## 写回洗炼属性；空表不写入，保持 SetItem 清空后的干净状态。
func _restore_rolled_attributes(stack: Variant, rolled: Dictionary) -> void:
	if rolled.is_empty():
		return
	stack.set("RolledAttributes", rolled.duplicate(true))

## 把行囊暂存桥的结果写回权威，只写真正发生变化的栏位。
func _write_back_carry(bridge: Node) -> void:
	for position: int in _capacity:
		var stack: Variant = bridge.call("GetStackAt", position)
		var old: Dictionary = _carry.call("GetCarryEntry", position)
		if old.get("item") != stack.get("Item") or int(old.get("count", 0)) != int(stack.get("Amount")):
			_carry.call("SetCarryEntry", position, stack.get("Item"), int(stack.get("Amount")))

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
