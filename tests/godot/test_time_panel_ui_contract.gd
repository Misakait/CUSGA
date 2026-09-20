@tool
extends McpTestSuite

## TimePanelUI GDScript 生产迁移的行为契约套件。

## 待验证的时间面板脚本。
const TIME_PANEL_UI_SCRIPT: GDScript = preload("res://core/ui/hud/time_panel_ui.gd")


## 返回 GodotAI 使用的稳定套件名称。
## 返回值：时间面板 UI 契约套件名。
func suite_name() -> String:
	return "time_panel_ui_contract"


## 提供 TimePanelUI 所需稳定信号与属性的最小 TimeSystem 协议。
class FakeTimeSystem extends Node:
	## 时间快照变化时发出全部旧参数。
	signal TimeChanged(total_time_passed, current_day, is_night, phase_progress, phase_length)

	## 开局以来累计的总时间。
	var TotalTimePassed: int = 25
	## 当前天数。
	var CurrentDay: int = 1
	## 当前是否为夜晚。
	var IsNight: bool = false
	## 当前阶段内的进度。
	var PhaseProgress: int = 25

	## 发出指定时间快照，模拟权威 TimeSystem 更新。
	## 参数 total_time_passed：新的累计总时间。
	## 参数 current_day：新的当前天数。
	## 参数 is_night：新的昼夜状态。
	## 参数 phase_progress：新的阶段进度。
	## 参数 phase_length：新的阶段长度。
	## 返回值：无。
	func emit_snapshot(
		total_time_passed: int,
		current_day: int,
		is_night: bool,
		phase_progress: int,
		phase_length: int
	) -> void:
		TotalTimePassed = total_time_passed
		CurrentDay = current_day
		IsNight = is_night
		PhaseProgress = phase_progress
		TimeChanged.emit(total_time_passed, current_day, is_night, phase_progress, phase_length)


## 验证初始快照、昼夜文本、信号刷新、阶段长度参数和退出清理。
## 返回值：无。
func test_time_panel_preserves_snapshot_signal_and_cleanup_contract() -> void:
	var scene_tree := Engine.get_main_loop() as SceneTree
	var existing_time_system := scene_tree.root.get_node_or_null("TimeSystem")
	assert_eq(existing_time_system, null, "编辑器测试根节点不应已有 TimeSystem，以免覆盖真实 Autoload。")
	if existing_time_system != null:
		return
	var time_system := FakeTimeSystem.new()
	time_system.name = "TimeSystem"
	scene_tree.root.add_child(time_system)
	var ui := _new_time_panel_ui()
	var day_label := ui.get_node("%DayLabel") as Label
	var phase_label := ui.get_node("%PhaseLabel") as Label
	var time_label := ui.get_node("%TimeLabel") as Label
	var progress := ui.get_node("%PhaseProgress") as ProgressBar
	var callback := Callable(ui, "_on_time_changed")
	assert_eq(day_label.text, "第 1 天", "初始天数文本必须保持旧格式。")
	assert_eq(phase_label.text, "白天", "初始昼夜文本必须保持白天。")
	assert_eq(time_label.text, "25 / 100", "初始进度文本必须使用旧 PhaseLength=100。")
	assert_eq(int(progress.min_value), 0, "进度条最小值必须保持 0。")
	assert_eq(int(progress.max_value), 100, "初始进度条上限必须保持 100。")
	assert_eq(int(progress.value), 25, "初始进度条数值必须读取 PhaseProgress。")
	assert_true(time_system.TimeChanged.is_connected(callback), "视图必须连接 TimeChanged。")

	time_system.emit_snapshot(250, 3, true, 50, 120)
	assert_eq(day_label.text, "第 3 天", "TimeChanged 必须更新天数。")
	assert_eq(phase_label.text, "夜晚", "TimeChanged 必须更新昼夜文本。")
	assert_eq(time_label.text, "50 / 120", "TimeChanged 必须使用信号携带的阶段长度。")
	assert_eq(int(progress.max_value), 120, "TimeChanged 必须更新进度条上限。")
	assert_eq(int(progress.value), 50, "TimeChanged 必须更新阶段进度。")

	scene_tree.root.remove_child(ui)
	assert_false(time_system.TimeChanged.is_connected(callback), "退出场景树时必须解除 TimeChanged。")
	ui.free()
	scene_tree.root.remove_child(time_system)
	time_system.free()


## 构造与 Main 节点协议一致的轻量时间面板。
## 返回值：已进入场景树并完成初始刷新的时间面板。
func _new_time_panel_ui() -> Control:
	var ui := TIME_PANEL_UI_SCRIPT.new() as Control
	ui.name = "TimePanelUIContractProbe"
	var day_label := Label.new()
	day_label.name = "DayLabel"
	day_label.unique_name_in_owner = true
	ui.add_child(day_label)
	day_label.owner = ui
	var phase_label := Label.new()
	phase_label.name = "PhaseLabel"
	phase_label.unique_name_in_owner = true
	ui.add_child(phase_label)
	phase_label.owner = ui
	var progress := ProgressBar.new()
	progress.name = "PhaseProgress"
	progress.unique_name_in_owner = true
	ui.add_child(progress)
	progress.owner = ui
	var time_label := Label.new()
	time_label.name = "TimeLabel"
	time_label.unique_name_in_owner = true
	ui.add_child(time_label)
	time_label.owner = ui
	var scene_tree := Engine.get_main_loop() as SceneTree
	scene_tree.root.add_child(ui)
	return ui
