extends RefCounted

## 物品堆叠的并行 GDScript 实现。
##
## 该对象是生产库存与掉落表使用的 ItemStack，并通过稳定属性、方法和信号协议兼容
## 仍保留的 C# 消费者。Item 只保存原始 Resource 引用，避免迁移期间改变堆叠身份。

const ITEM_DATA_COMPAT: GDScript = preload("res://resources/item/item_data_compat.gd")

## 堆叠变化信号；参数是发生变化的堆叠对象，保持旧 C# 事件的通知语义。
signal OnStackChanged(stack)

## 当前堆叠引用的物品资源；空堆叠时为 null。
var Item: Resource = null

## 当前堆叠数量；空堆叠时为 0。
var Amount: int = 0

## 装备洗炼出的属性值，键保持 AttributeType 或兼容 Variant，值为整数。
var RolledAttributes: Dictionary = {}

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


## 根据物品的 AttributeBonuses 生成一次装备属性；普通物品保持空字典。
func RollRandomStats() -> void:
	RolledAttributes.clear()
	if Item == null or not (Item is Object):
		return

	var raw_bonuses: Variant = (Item as Object).get("AttributeBonuses")
	if not (raw_bonuses is Dictionary):
		return

	for attribute_type: Variant in raw_bonuses:
		var raw_range: Variant = raw_bonuses[attribute_type]
		var minimum: int
		var maximum: int
		if raw_range is Vector2i:
			minimum = int((raw_range as Vector2i).x)
			maximum = int((raw_range as Vector2i).y)
		elif raw_range is Vector2:
			minimum = int((raw_range as Vector2).x)
			maximum = int((raw_range as Vector2).y)
		else:
			continue

		RolledAttributes[attribute_type] = minimum if minimum == maximum else randi_range(minimum, maximum)


## 清空槽位并通知观察者。
func Clear() -> void:
	Item = null
	Amount = 0
	RolledAttributes.clear()
	OnStackChanged.emit(self)


## 设置槽位内容；非正数量按旧实现立即清空。
func SetItem(item: Resource, amount: int) -> void:
	RolledAttributes.clear()
	Item = item
	Amount = amount
	if Amount <= 0:
		Clear()
	else:
		OnStackChanged.emit(self)


## 复制堆叠状态，但保留同一份 Item Resource 引用。
func Duplicate():
	var copy = get_script().new()
	copy.Item = Item
	copy.Amount = Amount
	copy.RolledAttributes = RolledAttributes.duplicate(true)
	return copy


## 从另一个堆叠复制状态；空或无效源会清空当前槽位。
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
