extends Resource

## 描述掉落表中的单个物品及其数量范围。
##
## Item 保持为通用 Resource，使 C# ItemData 能在 GDScript 数据资源中继续使用；
## 掉落随机和 ItemStack 创建由生产 GDScript LootTable 或旧 C# 兼容实现负责；
## 条目自身只保存配置，避免在数据资源中复制掉落结算规则。

## 掉落的物品资源。
@export var Item: Resource

## 物品被抽中的概率，范围为 0 到 100。
@export_range(0.0, 100.0, 0.1) var DropChance: float = 100.0

## 一次掉落的最少数量。
@export var MinAmount: int = 1

## 一次掉落的最多数量。
@export var MaxAmount: int = 1
