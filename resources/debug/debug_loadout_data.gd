extends Resource

## 调试开局配置的数据容器。
##
## 字段名保持旧 C# Resource 的 PascalCase 形式；数组暂时使用通用 Resource，
## 使迁移后的条目与仍保留的 C# 兼容条目都能被 Seeder 读取。

## 玩家属性组件尚未初始化时使用的初始属性资源。
@export var PlayerStartingStats: Resource

## 按顺序加入玩家背包的固定物品条目。
@export var InventoryItems: Array[Resource] = []

## 按顺序加入出战卡组的固定物品条目。
@export var BattleDeckItems: Array[Resource] = []

## 动态生成后放入玩家背包的装备条目。
@export var InventoryEquipment: Array[Resource] = []

## 动态生成并直接装备到玩家身上的装备条目。
@export var EquippedEquipment: Array[Resource] = []
