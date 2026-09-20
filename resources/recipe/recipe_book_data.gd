extends Resource

## 保存玩家可用的合成配方列表。
##
## 该资源只承担配置与序列化；配方过滤、库存检查和合成副作用仍由现有
## CraftingComponent/CraftingService 处理，因此可以与旧 C# 组件并行使用。

## 配方列表，使用通用 Resource 保留旧 C# CraftingRecipe 的兼容输入。
@export var Recipes: Array[Resource] = []
