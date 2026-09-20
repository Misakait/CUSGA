extends "res://resources/item/base_card_data.gd"

## 可堆叠物品的基础 Resource 契约。
##
## 普通生产物品、ResourceCardData、SkillCardData、EquipmentData 与 ToolData 使用该脚本；
## 迁移期兼容输入仍可由保留的 C# 派生类型提供。消费者通过稳定 Resource 字段协议读取两种实现。

## 单格最大堆叠数量；普通物品沿用旧实现的 99 默认值。
@export var MaxStackSize: int = 99

## 物品行为标签，使用 StringName 保持稳定标识和旧资源序列化格式。
@export var ItemTags: Array[StringName] = []

## 商店买入价；小于等于 0 表示物品没有自身定价。
@export var BuyPrice: int = 0

## 商店卖出价；小于等于 0 时由商店服务按买入价推导。
@export var SellPrice: int = 0

## 返回当前物品可用的最大堆叠数量。
var ActualMaxStackSize: int:
	get:
		return _resolve_actual_max_stack_size()

## 解析实际堆叠上限；派生物品可覆盖该钩子保留 C# 虚属性语义。
func _resolve_actual_max_stack_size() -> int:
	return MaxStackSize
