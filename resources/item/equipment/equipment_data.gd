extends "res://resources/item/item_data.gd"

## 装备数据的生产 GDScript Resource 实现。
##
## 该资源只保存装备字段，不负责装备槽位分配或属性结算；这些运行时职责仍由
## EquipmentComponent 持有。字段名和整数枚举值保持旧资源序列化协议。

## 允许装备的槽位整数列表，顺序和值对应 EquipmentSlot 枚举 0..15。
@export var ValidSlots: Array[int] = []

## 所属套装整数值，None/Wooden/Stone/Iron 对应 0..3。
@export var SetType: int = 0

## 装备提供的属性加成，键和值保持旧 Resource 的 Variant 结构。
@export var AttributeBonuses: Dictionary = {}

## 装备赋予的行为标签列表。
@export var GrantedTags: Array[StringName] = []


## 装备不可堆叠；在构造阶段覆盖 ItemData 的通用默认值。
func _init() -> void:
	MaxStackSize = 1
