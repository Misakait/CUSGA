extends Node

## 固定槽位库存的 GDScript 生产实现。
##
## 所有物品仍保存原始 Resource 引用，借此保持旧系统的对象身份和堆叠规则；公开
## PascalCase 方法继续兼容 C# ItemStack/ItemData 和迁移后的 GDScript 对象。

const ITEM_STACK_SCRIPT: GDScript = preload("res://resources/item/item_stack.gd")
const ITEM_DATA_COMPAT: GDScript = preload("res://resources/item/item_data_compat.gd")

## 库存内容发生结构性变化时发出；参数契约保持无参数。
signal InventoryChanged

## 固定槽位数量；升级只允许增加，不允许缩减已有物品的落脚点。
@export var Capacity: int = 27

## 拖拽数据使用的库存来源标识。
var DragSourceSystem: StringName = &"SystemInventory"

## 是否在通知前确保末尾仍有一个空槽，供出战卡组派生实现覆盖。
var KeepsTrailingEmptySlot: bool = false

## 由 ItemStack 实例组成的固定槽位数组。
var _slots: Array = []

## 标记槽位数组是否已经按 Capacity 初始化。
var _initialized: bool = false


## 节点进入场景树时建立空槽位，保持 C# _Ready 的初始化时机。
func _ready() -> void:
	_initialize_slots()


## 创建指定容量的空堆叠数组。
func _initialize_slots() -> void:
	_slots.clear()
	for _index in maxi(Capacity, 0):
		_slots.append(ITEM_STACK_SCRIPT.new())
	_initialized = true


## 确保测试或外部调用在节点尚未进树时也能得到稳定的槽位对象。
func _ensure_initialized() -> void:
	if not _initialized:
		_initialize_slots()


## 向外暴露当前槽位数组；返回原数组以保持槽位对象身份。
var Slots: Array:
	get:
		_ensure_initialized()
		return _slots


## 判断物品是否可以放入普通库存；派生库存可覆盖该内部策略。
func _can_store_item(item: Resource) -> bool:
	return item != null


## 在加入物品前预留派生库存需要的容量。
func _prepare_capacity_for_add(_item: Resource, _amount: int) -> void:
	pass


## 判断槽位不足时派生库存是否可以继续扩容。
func _can_provide_additional_capacity(_item: Resource, _amount: int) -> bool:
	return false


## 读取一个堆叠的空状态，兼容并行 GDScript 与旧 C# ItemStack。
func _stack_is_empty(stack: Variant) -> bool:
	return stack == null or bool(stack.get("IsEmpty"))


## 读取堆叠中的原始物品 Resource 引用。
func _stack_item(stack: Variant) -> Resource:
	return null if stack == null else stack.get("Item") as Resource


## 读取堆叠数量，避免跨语言属性被静态类型绑定。
func _stack_amount(stack: Variant) -> int:
	return 0 if stack == null else int(stack.get("Amount"))


## 读取物品实际最大堆叠值，统一复用已有兼容桥。
func _max_stack_size(item: Resource) -> int:
	return int(ITEM_DATA_COMPAT.call("get_max_stack_size", item, 99))


## 比较物品 Resource 的对象身份，不能以 CardId 替代引用相等。
func _same_item(left: Resource, right: Resource) -> bool:
	return bool(ITEM_DATA_COMPAT.call("same_item", left, right))


## 根据索引读取槽位，越界时返回 null 并保留可诊断错误。
func _stack_at(inventory: Variant, index: int) -> Variant:
	if inventory == null:
		return null
	if inventory == self:
		return _slots[index] if index >= 0 and index < _slots.size() else null
	if inventory.has_method("GetStackAt"):
		return inventory.call("GetStackAt", index)
	return null


## 读取任意库存容量，作为跨语言移动的最小边界。
func _inventory_capacity(inventory: Variant) -> int:
	if inventory == null:
		return 0
	var capacity: Variant = inventory.get("Capacity")
	return 0 if capacity == null else int(capacity)


## 查询另一个库存是否接受某个物品。
func _inventory_can_store(inventory: Variant, item: Resource) -> bool:
	if inventory == null:
		return false
	if inventory == self:
		return _can_store_item(item)
	if inventory.has_method("CanStore"):
		return bool(inventory.call("CanStore", item))
	return item != null


## 在批量加入前计算现有槽位还能承接的数量。
func _count_remaining_after_available_slots(item: Resource, amount: int) -> int:
	var remaining: int = amount
	for slot in _slots:
		if _stack_is_empty(slot):
			remaining -= _max_stack_size(item)
		elif _same_item(_stack_item(slot), item) and not bool(slot.get("IsFull")):
			remaining -= int(slot.get("AvailableSpace"))
		if remaining <= 0:
			return 0
	return remaining


## 把容量提升到至少指定值，只增不减并为新槽位创建独立 ItemStack。
func EnsureCapacityAtLeast(minimum_capacity: int) -> void:
	_ensure_initialized()
	if minimum_capacity <= Capacity:
		return
	var old_capacity: int = Capacity
	for _index in range(old_capacity, minimum_capacity):
		_slots.append(ITEM_STACK_SCRIPT.new())
	Capacity = minimum_capacity


## 供升级系统调用的公开容量入口；未初始化时先建立槽位。
func SetCapacity(capacity: int) -> void:
	EnsureCapacityAtLeast(capacity)


## 在通知前为出战卡组确保末尾空槽。
func _ensure_trailing_empty_slot() -> void:
	for slot in _slots:
		if _stack_is_empty(slot):
			return
	EnsureCapacityAtLeast(Capacity + 1)


## 统一发出库存变化信号，避免每个调用方自行维护尾槽规则。
func _notify_inventory_changed() -> void:
	if KeepsTrailingEmptySlot:
		_ensure_trailing_empty_slot()
	InventoryChanged.emit()


## 判断槽位索引是否有效。
func IsValidSlotIndex(index: int) -> bool:
	_ensure_initialized()
	return index >= 0 and index < Capacity


## 判断物品是否被当前库存接受。
func CanStore(item: Resource) -> bool:
	return _can_store_item(item)


## 读取指定槽位的 ItemStack。
func GetStackAt(index: int):
	_ensure_initialized()
	if not IsValidSlotIndex(index):
		push_error("InventoryComponent: 槽位索引越界：%d" % index)
		return null
	return _slots[index]


## 用另一个堆叠复制覆盖指定槽位，并保留当前槽位对象身份。
func TrySetStackAt(index: int, stack: Variant) -> bool:
	if not IsValidSlotIndex(index):
		return false
	if stack != null and not _stack_is_empty(stack) and not _can_store_item(_stack_item(stack)):
		return false
	_slots[index].call("CopyFrom", stack)
	_notify_inventory_changed()
	return true


## 清空指定槽位并通知观察者。
func TryClearStackAt(index: int) -> bool:
	if not IsValidSlotIndex(index):
		return false
	_slots[index].call("Clear")
	_notify_inventory_changed()
	return true


## 从另一个库存复制槽位内容，不共享 ItemStack 实例。
func CopySlotsFrom(source: Variant) -> bool:
	if source == null:
		return false
	var copy_count: int = mini(Capacity, _inventory_capacity(source))
	for index in copy_count:
		var source_stack: Variant = _stack_at(source, index)
		_slots[index].call("CopyFrom", source_stack)
	for index in range(copy_count, Capacity):
		_slots[index].call("Clear")
	_notify_inventory_changed()
	return true


## 按显示名称升序、数量降序排序，空槽统一放到末尾。
func SortByCardName() -> void:
	_ensure_initialized()
	var occupied: Array = []
	var empty: Array = []
	for slot in _slots:
		if _stack_is_empty(slot):
			empty.append(slot)
		else:
			occupied.append(slot)
	occupied.sort_custom(Callable(self, "_compare_stacks"))
	_slots = occupied + empty
	_notify_inventory_changed()


## 为 SortByCardName 提供稳定的名称/数量比较器。
func _compare_stacks(left: Variant, right: Variant) -> bool:
	var left_name: String = String(ITEM_DATA_COMPAT.call("get_display_name", _stack_item(left), ""))
	var right_name: String = String(ITEM_DATA_COMPAT.call("get_display_name", _stack_item(right), ""))
	if left_name == right_name:
		return _stack_amount(left) > _stack_amount(right)
	return left_name < right_name


## 按旧实现的先合并后占空槽顺序加入物品，返回未放入数量。
func AddItem(item: Resource, amount: int) -> int:
	_ensure_initialized()
	if item == null or amount <= 0 or _max_stack_size(item) <= 0 or not _can_store_item(item):
		return amount
	var remaining: int = amount
	_prepare_capacity_for_add(item, amount)

	for slot in _slots:
		if not _stack_is_empty(slot) and _same_item(_stack_item(slot), item) and not bool(slot.get("IsFull")):
			remaining = int(slot.call("Add", remaining))
			if remaining <= 0:
				_notify_inventory_changed()
				return 0

	for slot in _slots:
		if _stack_is_empty(slot):
			var amount_to_add: int = mini(remaining, _max_stack_size(item))
			slot.call("SetItem", item, amount_to_add)
			remaining -= amount_to_add
			if remaining <= 0:
				_notify_inventory_changed()
				return 0

	if remaining < amount:
		_notify_inventory_changed()
	return remaining


## 预检查指定数量能否完全放入库存。
func CanAddItem(item: Resource, amount: int) -> bool:
	_ensure_initialized()
	if item == null or amount <= 0 or _max_stack_size(item) <= 0 or not _can_store_item(item):
		return false
	var remaining: int = _count_remaining_after_available_slots(item, amount)
	return remaining <= 0 or _can_provide_additional_capacity(item, remaining)


## 判断某个物品的总数量是否达到要求。
func HasItem(item: Resource, required_amount: int) -> bool:
	return item != null and required_amount > 0 and ItemCnt(item) >= required_amount


## 按引用身份筛选物品并累加数量。
func CountWhere(predicate: Callable) -> int:
	_ensure_initialized()
	if not predicate.is_valid():
		return 0
	var total: int = 0
	for slot in _slots:
		if not _stack_is_empty(slot) and bool(predicate.call(_stack_item(slot))):
			total += _stack_amount(slot)
	return total


## 查询某个物品的总数量。
func ItemCnt(item: Resource) -> int:
	if item == null:
		return 0
	return CountWhere(func(candidate: Resource) -> bool: return _same_item(candidate, item))


## 清空一个槽位；保持旧调用方的无返回值语义。
func ClearItem(index: int) -> void:
	if IsValidSlotIndex(index):
		_slots[index].call("Clear")


## 替换指定槽位并返回无法放入的溢出数量。
func ReplaceItem(index: int, item: Resource, amount: int) -> int:
	if not IsValidSlotIndex(index):
		return amount
	if item != null and not _can_store_item(item):
		return amount
	_slots[index].call("Clear")
	if item == null or amount <= 0:
		return amount
	var amount_to_add: int = mini(amount, _max_stack_size(item))
	_slots[index].call("SetItem", item, amount_to_add)
	return amount - amount_to_add


## 按物品标签查询总数量，用于模糊合成材料匹配。
func GetTotalAmountByTag(tag: StringName) -> int:
	if tag == null or tag.is_empty():
		return 0
	return CountWhere(func(item: Resource) -> bool:
		for item_tag in ITEM_DATA_COMPAT.call("get_item_tags", item):
			if StringName(item_tag) == tag:
				return true
		return false
	)


## 尝试移除一个物品数量。
func TryRemoveItem(item: Resource, amount_to_remove: int) -> bool:
	if item == null or amount_to_remove <= 0:
		return false
	return TryRemoveItems({item: amount_to_remove})


## 原子校验多个物品需求后再从后往前扣除，失败时不改变任何槽位。
func TryRemoveItems(items_to_remove: Dictionary) -> bool:
	_ensure_initialized()
	if items_to_remove.is_empty():
		return false
	for item in items_to_remove:
		var required: int = int(items_to_remove[item])
		if item == null or required <= 0 or not HasItem(item, required):
			return false
	var changed: bool = false
	for item in items_to_remove:
		_remove_item_without_signal(item, int(items_to_remove[item]), changed)
		changed = true
	if changed:
		_notify_inventory_changed()
	return true


## 从后往前扣除指定物品，保持 C# 库存的槽位消耗顺序。
func _remove_item_without_signal(item: Resource, amount_to_remove: int, _changed: bool) -> void:
	var remaining: int = amount_to_remove
	for index in range(_slots.size() - 1, -1, -1):
		var slot = _slots[index]
		if _stack_is_empty(slot) or not _same_item(_stack_item(slot), item):
			continue
		if _stack_amount(slot) >= remaining:
			slot.call("SetItem", _stack_item(slot), _stack_amount(slot) - remaining)
			return
		remaining -= _stack_amount(slot)
		slot.call("Clear")


## 兼容旧的无返回值移除入口。
func RemoveItem(item: Resource, amount_to_remove: int) -> void:
	TryRemoveItem(item, amount_to_remove)


## 在同一库存内合并相同物品，或交换不同物品槽位。
func MoveItem(from_index: int, to_index: int) -> void:
	if from_index == to_index or not IsValidSlotIndex(from_index) or not IsValidSlotIndex(to_index):
		return
	var source_slot = _slots[from_index]
	var target_slot = _slots[to_index]
	if _stack_is_empty(source_slot):
		return
	if not _stack_is_empty(target_slot) and _same_item(_stack_item(target_slot), _stack_item(source_slot)):
		var remaining: int = int(target_slot.call("Add", _stack_amount(source_slot)))
		if remaining <= 0:
			source_slot.call("Clear")
		else:
			source_slot.call("SetItem", _stack_item(source_slot), remaining)
	else:
		var temp_stack = target_slot.call("Duplicate")
		target_slot.call("CopyFrom", source_slot)
		source_slot.call("CopyFrom", temp_stack)
	_notify_inventory_changed()


## 判断目标槽位是否能接收来源库存的堆叠。
func CanReceiveItemFrom(source_inventory: Variant, from_index: int, to_index: int) -> bool:
	if source_inventory == null:
		return false
	if from_index < 0 or from_index >= _inventory_capacity(source_inventory) or not IsValidSlotIndex(to_index):
		return false
	if source_inventory == self and from_index == to_index:
		return false
	var source_slot: Variant = _stack_at(source_inventory, from_index)
	if _stack_is_empty(source_slot) or not _can_store_item(_stack_item(source_slot)):
		return false
	var target_slot = _slots[to_index]
	if source_inventory == self or _stack_is_empty(target_slot) or _same_item(_stack_item(target_slot), _stack_item(source_slot)):
		return true
	return _inventory_can_store(source_inventory, _stack_item(target_slot))


## 把指定槽位的堆叠移动到目标库存第一个可合并或空槽。
func TryMoveStackToFirstAvailableSlot(target_inventory: Variant, from_index: int) -> bool:
	if target_inventory == null or target_inventory == self or not IsValidSlotIndex(from_index):
		return false
	var source_slot = _slots[from_index]
	if _stack_is_empty(source_slot):
		return false
	if target_inventory.has_method("_prepare_capacity_for_add"):
		target_inventory.call("_prepare_capacity_for_add", _stack_item(source_slot), _stack_amount(source_slot))
	for to_index in _inventory_capacity(target_inventory):
		if not bool(target_inventory.call("_can_receive_without_replacing_different_item", self, from_index, to_index)):
			continue
		var before_amount: int = _stack_amount(source_slot)
		if target_inventory.has_method("MoveItemFromDeferred"):
			target_inventory.call("MoveItemFromDeferred", self, from_index, to_index)
		else:
			target_inventory.call("MoveItemFrom", self, from_index, to_index)
		return _stack_is_empty(source_slot) or _stack_amount(source_slot) < before_amount
	return false


## 批量移动符合条件的堆叠，并把库存通知延迟到整批完成。
func MoveAllMatchingStacksTo(target_inventory: Variant, predicate: Callable) -> int:
	_ensure_initialized()
	if target_inventory == null or target_inventory == self or not predicate.is_valid():
		return 0
	var matching_indices: Array[int] = []
	for index in Capacity:
		var source_slot = _slots[index]
		if not _stack_is_empty(source_slot) and bool(predicate.call(_stack_item(source_slot))):
			matching_indices.append(index)
	var moved_amount: int = 0
	for index in matching_indices:
		var source_slot = _slots[index]
		var before_amount: int = _stack_amount(source_slot)
		if TryMoveStackToFirstAvailableSlot(target_inventory, index):
			moved_amount += before_amount - (0 if _stack_is_empty(source_slot) else _stack_amount(source_slot))
	if moved_amount > 0:
		_notify_inventory_changed()
		if target_inventory.has_method("_notify_inventory_changed"):
			target_inventory.call("_notify_inventory_changed")
	return moved_amount


## 允许目标库存检查一个槽位，而不发生不同物品的交换。
func _can_receive_without_replacing_different_item(source_inventory: Variant, from_index: int, to_index: int) -> bool:
	if not CanReceiveItemFrom(source_inventory, from_index, to_index):
		return false
	var source_slot: Variant = _stack_at(source_inventory, from_index)
	var target_slot = _slots[to_index]
	return _stack_is_empty(target_slot) or (_same_item(_stack_item(target_slot), _stack_item(source_slot)) and not bool(target_slot.get("IsFull")))


## 接收另一个库存指定槽位的堆叠，支持合并或交换。
func MoveItemFrom(source_inventory: Variant, from_index: int, to_index: int) -> void:
	_move_item_from_internal(source_inventory, from_index, to_index, true)


## 供批量移动调用的公开无通知入口，避免依赖带下划线方法的反射行为。
func MoveItemFromDeferred(source_inventory: Variant, from_index: int, to_index: int) -> void:
	_move_item_from_internal(source_inventory, from_index, to_index, false)


## 执行跨库存移动；批量调用可关闭单次通知，避免重复刷新 UI。
func _move_item_from_internal(
	source_inventory: Variant,
	from_index: int,
	to_index: int,
	notify_inventories: bool
) -> void:
	if not CanReceiveItemFrom(source_inventory, from_index, to_index):
		return
	if source_inventory == self:
		MoveItem(from_index, to_index)
		return
	var source_slot: Variant = _stack_at(source_inventory, from_index)
	var target_slot = _slots[to_index]
	if not _stack_is_empty(target_slot) and _same_item(_stack_item(target_slot), _stack_item(source_slot)):
		var remaining: int = int(target_slot.call("Add", _stack_amount(source_slot)))
		if remaining <= 0:
			source_slot.call("Clear")
		else:
			source_slot.call("SetItem", _stack_item(source_slot), remaining)
	else:
		var temp_stack = target_slot.call("Duplicate")
		target_slot.call("CopyFrom", source_slot)
		source_slot.call("CopyFrom", temp_stack)
	if notify_inventories:
		if source_inventory.has_method("_notify_inventory_changed"):
			source_inventory.call("_notify_inventory_changed")
		_notify_inventory_changed()


## 兼容旧实现的“先合并再交换”入口。
func MEItem(from_index: int, to_index: int) -> void:
	if from_index == to_index or not IsValidSlotIndex(from_index) or not IsValidSlotIndex(to_index):
		return
	var source_slot = _slots[from_index]
	var target_slot = _slots[to_index]
	if not _stack_is_empty(target_slot) and _same_item(_stack_item(target_slot), _stack_item(source_slot)):
		var remaining: int = int(target_slot.call("Add", _stack_amount(source_slot)))
		if remaining <= 0:
			source_slot.call("Clear")
		else:
			source_slot.call("SetItem", _stack_item(source_slot), remaining)
	var temp_stack = target_slot.call("Duplicate")
	target_slot.call("CopyFrom", source_slot)
	source_slot.call("CopyFrom", temp_stack)
