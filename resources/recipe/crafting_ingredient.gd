extends Resource

## 描述合成配方中的一种材料需求。
##
## 该资源只保存序列化数据，不负责库存扣除；CraftingService 继续负责数量校验
## 与实际扣除，迁移期间 RequiredItem 使用通用 Resource 以兼容旧 C# ItemData。

## 合成所需的物品资源，可指向旧 C# ItemData 或新的 GDScript ItemData。
@export var RequiredItem: Resource

## 单次合成所需数量，沿用旧 C# 默认值 1。
@export_range(1, 2147483647, 1, "or_greater") var Amount: int = 1
