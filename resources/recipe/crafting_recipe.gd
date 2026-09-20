extends Resource

## 描述一张完整的合成配方图纸。
##
## Inputs 刻意使用通用 Resource 数组，避免在 C# 程序集刷新前绑定到某一种语言
## 的全局类型；每个条目仍需符合 crafting_ingredient.gd 的 RequiredItem/Amount 协议。

## 配方在 UI 中显示的名称。
@export var RecipeName: String = ""

## 单次合成所需的材料条目，顺序与原资源保持一致。
@export var Inputs: Array[Resource] = []

## 合成产出的物品资源，可继续接收旧 C# ItemData。
@export var OutputItem: Resource

## 单次合成产出数量，沿用旧 C# 默认值 1。
@export_range(1, 2147483647, 1, "or_greater") var OutputAmount: int = 1
