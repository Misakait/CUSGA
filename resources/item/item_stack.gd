extends RefCounted

## 物品堆叠的并行 GDScript 实现。
##
## 该对象是生产库存与掉落表使用的 ItemStack，并通过稳定属性、方法和信号协议兼容
## 仍保留的 C# 消费者。Item 只保存原始 Resource 引用，避免迁移期间改变堆叠身份。

const EQUIPMENT_DATA_COMPAT: GDScript = preload("res://resources/item/equipment/equipment_data_compat.gd")

const ITEM_DATA_COMPAT: GDScript = preload("res://resources/item/item_data_compat.gd")

## 堆叠变化信号；参数是发生变化的堆叠对象，保持旧 C# 事件的通知语义。
signal OnStackChanged(stack)

## 当前堆叠引用的物品资源；空堆叠时为 null。
var Item: Resource = null

## 当前堆叠数量；空堆叠时为 0。
var Amount: int = 0

## 装备洗炼出的属性值，键保持 AttributeType 或兼容 Variant，值为整数。
var RolledAttributes: Dictionary = {}

## 是否已经为当前物品完成过首次属性生成；即使结果为空也不能再次随机。
var _stats_initialized: bool = false

## 当前槽位是否没有可用物品。
var IsEmpty: bool:
	get:
		return Item == null or Amount <= 0

## 当前槽位是否已达到物品的实际最大堆叠数量。
var IsFull: bool:
	get:
		return not IsEmpty and Amount >= _get_max_stack_size()

## 当前堆叠还能容纳的数量；空槽位保持旧实现的 0 语义。
var AvailableSpace: int:
	get:
		return 0 if IsEmpty else _get_max_stack_size() - Amount


## 首次生成当前物品的装备属性；普通物品为空，重复调用保留已有结果。
## 参数：无。返回值：无；必须在 SetItem 后、正式交给库存或装备组件前调用。
func RollRandomStats() -> void:
	# 穿脱和复制没有权力重随机；已有非空实例结果也不能被重复调用覆盖。
	if _stats_initialized or not RolledAttributes.is_empty() or Item == null:
		return
	_stats_initialized = true
	var entries: Array[Dictionary] = EQUIPMENT_DATA_COMPAT.call("get_attribute_entries", Item)
	for entry: Dictionary in entries:
		var attribute: int = int(entry.get("attribute", -1))
		if attribute < 0 or attribute > 14:
			continue
		var first: int = int(entry.get("minimum", 0))
		var second: int = int(entry.get("maximum", 0))
		var minimum: int = mini(first, second)
		var maximum: int = maxi(first, second)
		var bonus: int = minimum if minimum == maximum else randi_range(minimum, maximum)
		RolledAttributes[attribute] = int(RolledAttributes.get(attribute, 0)) + bonus


## 清空槽位并通知观察者。
## 参数：无。返回值：无。
func Clear() -> void:
	Item = null
	Amount = 0
	RolledAttributes.clear()
	_stats_initialized = false
	OnStackChanged.emit(self)


## 设置槽位内容；非正数量按旧实现立即清空。
## 参数 item：原始物品资源；amount：数量。返回值：无，本方法不生成属性。
func SetItem(item: Resource, amount: int) -> void:
	RolledAttributes.clear()
	_stats_initialized = false
	Item = item
	Amount = amount
	if Amount <= 0:
		Clear()
	else:
		OnStackChanged.emit(self)


## 复制堆叠状态，但保留同一份 Item Resource 引用。
## 参数：无。返回值：独立堆叠副本，其实例结果禁止重新随机。
func Duplicate():
	var copy = get_script().new()
	copy.Item = Item
	copy.Amount = Amount
	copy.RolledAttributes = RolledAttributes.duplicate(true)
	copy._stats_initialized = true
	return copy


## 从另一个堆叠复制状态；空或无效源会清空当前槽位。
## 参数 stack：来源堆叠。返回值：无，复制内容并保留目标对象身份。
func CopyFrom(stack: Variant) -> void:
	if stack == null or bool(stack.get("IsEmpty")):
		Clear()
		return

	Item = stack.get("Item") as Resource
	Amount = int(stack.get("Amount"))
	RolledAttributes.clear()
	var source_attributes: Variant = stack.get("RolledAttributes")
	if source_attributes is Dictionary:
		RolledAttributes = (source_attributes as Dictionary).duplicate(true)
	_stats_initialized = true
	OnStackChanged.emit(self)


## 尝试增加数量并返回未能放入的溢出数量。
func Add(amount: int) -> int:
	var amount_to_add: int = mini(AvailableSpace, amount)
	Amount += amount_to_add
	OnStackChanged.emit(self)
	return amount - amount_to_add


## 读取指定洗炼属性；不存在时返回 0。
func GetBonus(attribute_type: Variant) -> int:
	return int(RolledAttributes.get(attribute_type, 0))


## 读取物品的实际最大堆叠数量，统一兼容 C# 与 GDScript ItemData。
func _get_max_stack_size() -> int:
	return int(ITEM_DATA_COMPAT.call("get_max_stack_size", Item, 99))
