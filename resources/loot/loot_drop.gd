extends Resource
class_name LootDrop

## 描述掉落表中的单个物品及其数量范围。
##
## 物品选择限定为 ItemData 及其派生资源；掉落随机和物品堆叠创建由 LootTableData 负责。
## 条目自身只保存配置，避免在数据资源中复制掉落结算规则。

## 掉落的物品；拖入已有 ItemData 或派生的材料、技能卡、装备、工具资产。
@export_custom(PROPERTY_HINT_RESOURCE_TYPE, "ItemData") var Item: Resource

## 物品被抽中的概率，范围为 0 到 100。
@export_range(0.0, 100.0, 0.1) var DropChance: float = 100.0

## 一次掉落的最少数量。
@export var MinAmount: int = 1

## 一次掉落的最多数量。
@export var MaxAmount: int = 1
