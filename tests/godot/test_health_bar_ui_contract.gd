@tool
extends McpTestSuite

## HealthBarUI GDScript 生产迁移的行为契约套件。

## 待验证的生命条脚本。
const HEALTH_BAR_UI_SCRIPT: GDScript = preload("res://core/ui/hud/health_bar_ui.gd")


## 返回 GodotAI 使用的稳定套件名称。
## 返回值：生命条 UI 契约套件名。
func suite_name() -> String:
	return "health_bar_ui_contract"


## 提供 HealthBarUI 所需稳定信号与属性的最小生命组件。
class FakeHealthComponent extends Node:
	## 当前值或上限变化时发出最新快照。
	signal ValueChanged(current_value, max_value)

	## 当前生命值。
	var CurrentValue: int = 0
	## 当前生命上限。
	var MaxValue: int = 100

	## 写入新的生命快照并通知视图。
	## 参数 current_value：新的当前生命值。
	## 参数 max_value：新的生命上限。
	## 返回值：无。
	func set_values(current_value: int, max_value: int) -> void:
		CurrentValue = current_value
		MaxValue = max_value
		ValueChanged.emit(CurrentValue, MaxValue)


## 提供 HealthBarUI 读取的 GameplayPort 玩家生命属性。
class FakeGameplayPort extends Node:
	## 当前玩家的生命组件。
	var PlayerHealth: Node = null


## 验证初始刷新、信号刷新、重绑与退出清理。
## 返回值：无。
func test_health_bar_preserves_binding_visual_and_cleanup_contract() -> void:
	var first := FakeHealthComponent.new()
	first.CurrentValue = 73
	first.MaxValue = 120
	var fixture: Dictionary = _new_health_bar_ui(first)
	var ui := fixture["ui"] as Control
	var health_bar := ui.get_node("%HealthBar") as ProgressBar
	var health_label := ui.get_node("%HealthLabel") as Label
	var callback := Callable(ui, "_on_health_changed")
	assert_eq(int(health_bar.max_value), 120, "初始进度条上限必须读取生命组件 MaxValue。")
	assert_eq(int(health_bar.value), 73, "初始进度条数值必须读取生命组件 CurrentValue。")
	assert_eq(health_label.text, "73 / 120", "初始生命文本必须保持旧格式。")
	assert_true(first.ValueChanged.is_connected(callback), "Bind 必须连接 ValueChanged。")

	first.set_values(41, 90)
	assert_eq(int(health_bar.max_value), 90, "ValueChanged 必须更新进度条上限。")
	assert_eq(int(health_bar.value), 41, "ValueChanged 必须更新当前生命值。")
	assert_eq(health_label.text, "41 / 90", "ValueChanged 必须更新生命文本。")

	var second := FakeHealthComponent.new()
	second.CurrentValue = 8
	second.MaxValue = 50
	ui.call("Bind", second)
	assert_false(first.ValueChanged.is_connected(callback), "切换组件时必须解除旧 ValueChanged。")
	assert_true(second.ValueChanged.is_connected(callback), "切换组件时必须连接新 ValueChanged。")
	assert_eq(health_label.text, "8 / 50", "重绑后必须立即显示新组件快照。")

	var scene_tree := Engine.get_main_loop() as SceneTree
	scene_tree.root.remove_child(ui)
	assert_false(second.ValueChanged.is_connected(callback), "退出场景树时必须解除 ValueChanged。")
	ui.free()


## 构造与 Main 节点协议一致的轻量生命条视图。
## 参数 health：GameplayPort 应暴露的玩家生命组件。
## 返回值：包含生命条 UI 与 GameplayPort 的夹具字典。
func _new_health_bar_ui(health: Node) -> Dictionary:
	var ui := HEALTH_BAR_UI_SCRIPT.new() as Control
	ui.name = "HealthBarUIContractProbe"
	var health_bar := ProgressBar.new()
	health_bar.name = "HealthBar"
	health_bar.unique_name_in_owner = true
	ui.add_child(health_bar)
	health_bar.owner = ui
	var health_label := Label.new()
	health_label.name = "HealthLabel"
	health_label.unique_name_in_owner = true
	ui.add_child(health_label)
	health_label.owner = ui
	var gameplay_port := FakeGameplayPort.new()
	gameplay_port.name = "GameplayPort"
	gameplay_port.PlayerHealth = health
	ui.add_child(gameplay_port)
	gameplay_port.owner = ui
	ui.set("GameplayPortPath", NodePath("GameplayPort"))
	var scene_tree := Engine.get_main_loop() as SceneTree
	scene_tree.root.add_child(ui)
	ui.call("_ready")
	return {"ui": ui, "gameplay_port": gameplay_port}
