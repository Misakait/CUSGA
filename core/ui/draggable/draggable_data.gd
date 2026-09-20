extends RefCounted

## 库存与装备 UI 共用的拖拽载荷。
##
## 该对象只传递来源、槽位和堆叠引用，不执行移动规则。来源组件继续负责 Can* 校验与实际
## 状态修改，因此 GDScript UI 不会复制 InventoryComponent 或 EquipmentComponent 的规则。

## 拖拽来源系统标识；默认保持 TagConsts.SystemInventory。
var SourceSystem: StringName = &"SystemInventory"

## 来源库存槽位索引；非库存来源保持默认 0。
var FromIndex: int = 0

## 来源库存组件；允许旧 C# 或并行 GDScript Node。
var SourceInventory: Node = null

## 来源装备组件；允许旧 C# 或并行 GDScript Node。
var SourceEquipment: Node = null

## 来源装备槽的稳定整数值；默认保持 EquipmentSlot.Helmet=0。
var FromEquipmentSlot: int = 0

## 当前拖拽的 ItemStack；C# 与 GDScript 实现都继承 RefCounted。
var HeldStack: RefCounted = null
