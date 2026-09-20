@tool
extends McpTestSuite

## LootComponent GDScript 并行迁移的行为契约套件。

## 待验证的掉落组件脚本。
const LOOT_COMPONENT_SCRIPT: GDScript = preload("res://entities/components/loot_component.gd")


## 返回 GodotAI 使用的稳定套件名称。
## 返回值：掉落组件契约套件名。
func suite_name() -> String:
	return "loot_component_contract"


## 记录产量参数并返回固定堆叠数组的最小掉落表。
class FakeLootTable extends Resource:
	## 最近一次收到的额外掉落数量。
	var last_yield_growth: int = 0
	## 作为掉落结果返回的固定数组。
	var rolled_loot: Array = []

	## 返回固定掉落，并记录组件转发的产量参数。
	## 参数 yield_growth：组件传入的额外掉落数量。
	## 返回值：预先配置的掉落数组。
	func RollLoot(yield_growth: int) -> Array:
		last_yield_growth = yield_growth
		return rolled_loot


## 提供生产 GlobalEventBus 掉落信号并保存最后一次广播。
class FakeGlobalEventBus extends Node:
	## 实体生成掉落时广播位置和堆叠数组。
	signal on_entity_dropped(global_position, stacks)

	## 已接收掉落事件的次数。
	var received_count: int = 0
	## 最近一次掉落位置。
	var received_position: Vector2 = Vector2.ZERO
	## 最近一次掉落堆叠数组。
	var received_stacks: Array = []

	## 保存最近一次掉落广播。
	## 参数 global_position：掉落实体的全局位置。
	## 参数 stacks：掉落表生成的堆叠数组。
	## 返回值：无。
	func capture(global_position: Vector2, stacks: Array) -> void:
		received_count += 1
		received_position = global_position
		received_stacks = stacks


## 验证空掉落表短路、产量转发及全局事件广播。
## 返回值：无。
func test_loot_component_preserves_roll_and_event_bus_contract() -> void:
	## Godot 编辑器测试使用的场景树。
	var scene_tree := Engine.get_main_loop() as SceneTree
	## 防止测试覆盖意外存在的同名根节点。
	var existing_bus := scene_tree.root.get_node_or_null("GlobalEventBus")
	assert_eq(existing_bus, null, "编辑器测试根节点不应已有 GlobalEventBus。")
	if existing_bus != null:
		return
	## 捕获掉落广播的假全局事件总线。
	var event_bus := FakeGlobalEventBus.new()
	event_bus.name = "GlobalEventBus"
	scene_tree.root.add_child(event_bus)
	event_bus.on_entity_dropped.connect(Callable(event_bus, "capture"))
	## 待验证的掉落组件。
	var component := LOOT_COMPONENT_SCRIPT.new() as Node
	scene_tree.root.add_child(component)
	component.call("TriggerDrop", Vector2(2.0, 3.0), 4)
	assert_eq(event_bus.received_count, 0, "DropTable 为空时不得广播掉落事件。")

	## 用于验证数组身份的固定堆叠对象。
	var stack := RefCounted.new()
	## 记录组件调用的假掉落表。
	var table := FakeLootTable.new()
	table.rolled_loot = [stack]
	component.set("DropTable", table)
	component.call("TriggerDrop", Vector2(12.0, 34.0), 7)
	assert_eq(table.last_yield_growth, 7, "组件必须把额外掉落数量原样传给 RollLoot。")
	assert_eq(event_bus.received_count, 1, "有效掉落必须只广播一次 on_entity_dropped。")
	assert_eq(event_bus.received_position, Vector2(12.0, 34.0), "掉落广播必须保留全局位置。")
	assert_eq(event_bus.received_stacks.size(), 1, "掉落广播必须保留堆叠数量。")
	assert_eq(event_bus.received_stacks[0], stack, "掉落广播必须保留堆叠对象身份。")

	scene_tree.root.remove_child(component)
	component.free()
	scene_tree.root.remove_child(event_bus)
	event_bus.free()
