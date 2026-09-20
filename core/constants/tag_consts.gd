extends RefCounted

## 跨语言标签常量的 GDScript 等价实现，等价迁移自 core/constants/TagConsts.cs。
##
## 标签有两类用途：拖拽来源系统标识（SystemInventory / SystemWarehouse /
## SystemBattleDeck / SystemEquipment）与玩法判定标签（WoodDamageUp / HealAfterAction /
## MagicItem）。它们会被写进物品资源与存档，因此取值必须逐字一致。
## 生产 GDScript 继续使用同名 StringName 字面量，本载体负责单一来源与契约锁定。

## 系统背包拖拽来源；等价旧 C# TagConsts.SystemInventory。
const SystemInventory: StringName = &"SystemInventory"
## 仓库拖拽来源；等价旧 C# TagConsts.SystemWarehouse。
const SystemWarehouse: StringName = &"SystemWarehouse"
## 战斗牌组拖拽来源；等价旧 C# TagConsts.SystemBattleDeck。
const SystemBattleDeck: StringName = &"SystemBattleDeck"
## 装备栏拖拽来源；等价旧 C# TagConsts.SystemEquipment。
const SystemEquipment: StringName = &"SystemEquipment"
## 木系伤害提升标签；等价旧 C# TagConsts.WoodDamageUp。
const WoodDamageUp: StringName = &"WoodDamageUp"
## 行动后治疗标签；等价旧 C# TagConsts.HealAfterAction。
const HealAfterAction: StringName = &"HealAfterAction"
## 魔法物品分类标签；等价旧 C# TagConsts.MagicItem。
## 旧实现用显式分类标签，避免按物品名称片段误判为可装备。
const MagicItem: StringName = &"MagicItem"
