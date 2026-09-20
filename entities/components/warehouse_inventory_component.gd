extends "res://entities/components/inventory_component.gd"

## 全局仓库库存的并行 GDScript 来源标识。

## 仓库拖拽来源标识，保持 C# WarehouseInventoryComponent 的字符串值。
func _init() -> void:
	DragSourceSystem = &"SystemWarehouse"

