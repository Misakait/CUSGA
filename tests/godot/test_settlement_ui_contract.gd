@tool
extends McpTestSuite

## 结算界面的公开契约与场景结构回归。
## 原生点击、提示动画与暂停交互需要真实运行期冒烟，不能由编辑器占位实例证明。

const PANEL_SCRIPT: GDScript = preload("res://core/ui/settlement/settlement_controller.gd")
const PANEL_SCENE: PackedScene = preload("res://scenes/GameProcess/Settlement.tscn")

## 返回稳定的测试套件名称。
## 返回值：结算界面契约套件名。
func suite_name() -> String:
	return "settlement_ui_contract"

## 验证文案可在入树前设置和追加，空追加不制造空行。
## 返回值：无。
func test_description_api_preserves_order_and_replacement_before_ready() -> void:
	var panel: Node = PANEL_SCRIPT.new() as Node
	panel.call("add_description", "击败了小怪1")
	panel.call("add_description", "")
	panel.call("add_description", "击败了boss1")
	var result: Dictionary = panel.get("_result")
	assert_eq(result.get("description"), "击败了小怪1\n击败了boss1", "追加必须保留原文和调用顺序。")
	panel.call("set_description", "新的描述")
	result = panel.get("_result")
	assert_eq(result.get("description"), "新的描述", "替换接口必须覆盖原文。")
	panel.free()

## 验证容量与收获数量独立，缩容不能隐藏已经存在的收获。
## 返回值：无。
func test_capacity_defaults_to_five_and_rejects_hidden_harvest() -> void:
	var panel: Node = PANEL_SCRIPT.new() as Node
	assert_eq(panel.call("get_harvest_capacity"), 5, "空结果也必须保留 5 格。")
	assert_true(bool(panel.call("refresh_harvest_capacity", 8)), "未来升级可通过接口增加格子。")
	assert_eq(panel.call("get_harvest_capacity"), 8, "查询必须返回接口设置后的容量。")
	panel.call("set_result", {"capacity": 5, "harvest": [null, null]})
	assert_false(bool(panel.call("refresh_harvest_capacity", 1)), "缩容不能隐藏已经占用的格子。")
	assert_eq(panel.call("get_harvest_capacity"), 5, "失败不能部分更新容量。")
	panel.free()

## 验证结算结果中的保存错误阻止导航，非法去向也不会触发事件。
## 返回值：无。
func test_navigation_rejects_save_error_and_invalid_destination() -> void:
	var panel: Node = PANEL_SCRIPT.new() as Node
	panel.call("set_result", {"error": "无法写入测试存档"})
	assert_false(bool(panel.call("request_navigation", "menu")), "保存失败必须先重试。")
	assert_false(bool(panel.call("request_navigation", "next_run")), "保存失败不能开始下一局。")
	panel.call("set_result", {})
	assert_false(bool(panel.call("request_navigation", "unknown")), "非法导航必须拒绝。")
	panel.free()

## 验证场景按钮独立挂脚本，覆盖层与标签不会误放行或截断点击。
## 返回值：无。
func test_scene_keeps_button_scripts_and_pause_input_contract() -> void:
	var panel: Node = PANEL_SCENE.instantiate()
	assert_eq(panel.process_mode, Node.PROCESS_MODE_ALWAYS, "结算界面必须在暂停时操作。")
	var blocker: Control = panel.get_node("InputBlocker") as Control
	assert_eq(blocker.mouse_filter, Control.MOUSE_FILTER_STOP, "空白点击必须由覆盖层阻止。")
	var menu: Button = panel.get_node("ButtonSection/BackToMenu/Button") as Button
	var next_run: Button = panel.get_node("ButtonSection/BackToMenu2/Button") as Button
	assert_ne(menu.get_script(), next_run.get_script(), "两个按钮分别挂载自己的脚本。")
	for path: String in ["ButtonSection/BackToMenu/Label", "ButtonSection/BackToMenu2/Label"]:
		assert_eq((panel.get_node(path) as Label).mouse_filter, Control.MOUSE_FILTER_IGNORE, "文字不能拦截按钮点击。")
	assert_true(panel.get_node("Data/bg/PlayerChar") is Node2D, "保留原头像区域。")
	assert_false(panel.get_node("Data/bg/PlayerChar") is CharacterBody2D, "结算头像不能成为第二个游戏角色。")
	panel.free()
