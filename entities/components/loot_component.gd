extends Node

## 怪物掉落组件的并行 GDScript 实现。
##
## 组件只把掉落表结果广播到全局事件总线，不负责概率、背包写入或怪物死亡流程。

## 生产 GDScript 或旧 C# 兼容 LootTable；组件只依赖稳定 RollLoot 方法。
@export var DropTable: Resource = null


## 生成掉落结果并广播实体掉落事件。
## 参数 global_position：掉落实体死亡时的全局位置。
## 参数 yiled_growth：额外掉落数量；保留旧方法参数语义和拼写边界。
## 返回值：无。
func TriggerDrop(global_position: Vector2, yiled_growth: int) -> void:
	if DropTable == null:
		return
	## LootTable 返回的新旧 ItemStack 数组。
	var rolled_loots: Variant = DropTable.call("RollLoot", yiled_growth)
	if not (rolled_loots is Array):
		push_error("LootComponent.DropTable.RollLoot 必须返回 Array。")
		return
	## 负责把掉落结果交给拾取表现和库存流程的全局事件总线。
	var global_event_bus := get_node("/root/GlobalEventBus") as Node
	global_event_bus.emit_signal(&"on_entity_dropped", global_position, rolled_loots)
