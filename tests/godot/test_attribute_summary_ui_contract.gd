@tool
extends McpTestSuite

## AttributeSummaryUI GDScript 生产实现的行为契约套件。
##
## 测试使用稳定信号和方法名模拟 AttributeComponent，并锁定生产场景脚本引用。

## 待验证的并行属性摘要脚本。
const ATTRIBUTE_SUMMARY_UI_SCRIPT: GDScript = preload("res://core/ui/attribute_summary_ui.gd")
## 生产属性摘要场景路径，用于锁定实际脚本引用。
const ATTRIBUTE_SUMMARY_UI_SCENE_PATH: String = "res://scenes/inventory/AttributeSummaryUI.tscn"


## 提供 AttributeSummaryUI 所需稳定方法与信号的最小属性组件。
class FakeAttributeComponent extends Node:
	## 任一最终属性变化时携带不透明变更对象。
	signal AttributeChanged(change_event)
	## 可用属性点变化时携带最新点数。
	signal AvailablePointsChanged(available_points)

	## 以 AttributeType 整数值索引的最终属性表。
	var values: Dictionary = {}

	## 读取指定属性的最终值。
	## 参数 attribute_type：与 C# AttributeType 一致的整数值。
	## 返回值：已配置的最终值；未配置时返回 0。
	func GetEffectiveValue(attribute_type: int) -> float:
		return float(values.get(attribute_type, 0.0))

	## 修改一个最终属性并发出 AttributeChanged。
	## 参数 attribute_type：需要修改的属性整数值。
	## 参数 value：新的最终值。
	## 返回值：无。
	func set_effective_value(attribute_type: int, value: float) -> void:
		values[attribute_type] = value
		AttributeChanged.emit(null)

	## 发出 AvailablePointsChanged，验证摘要沿用旧事件刷新边界。
	## 参数 available_points：新的可用点数。
	## 返回值：无。
	func notify_available_points_changed(available_points: int) -> void:
		AvailablePointsChanged.emit(available_points)


## 返回套件名称，供 GodotAI 精确筛选本批测试。
## 返回值：固定套件名。
func suite_name() -> String:
	return "attribute_summary_ui_contract"


## 验证生产属性摘要场景已经挂载 GDScript 实现。
## 返回值：无。
func test_production_scene_uses_gdscript_attribute_summary() -> void:
	## 强制从磁盘重新加载生产场景，避免切换前的 C# 脚本缓存干扰。
	var packed_scene := ResourceLoader.load(
		ATTRIBUTE_SUMMARY_UI_SCENE_PATH,
		"PackedScene",
		ResourceLoader.CACHE_MODE_REPLACE
	) as PackedScene
	assert_true(packed_scene != null, "AttributeSummaryUI 生产场景必须能够加载。")
	if packed_scene == null:
		return
	## 未进入场景树的生产属性摘要实例。
	var ui := packed_scene.instantiate() as PanelContainer
	## 生产根节点当前实际挂载的脚本。
	var script := ui.get_script() as Script
	assert_true(script != null, "AttributeSummaryUI 生产根节点必须保留脚本。")
	if script != null:
		assert_eq(script.resource_path, "res://core/ui/attribute_summary_ui.gd", "生产场景必须使用 GDScript AttributeSummaryUI。")
	ui.free()


## 验证未绑定状态、五项摘要以及全部详情的数值格式。
## 返回值：无。
func test_summary_and_detail_values_preserve_formatting() -> void:
	# 并行 UI 夹具承载本用例全部展示断言。
	var ui: PanelContainer = _new_attribute_summary_ui()
	_assert_all_values(ui, "-", "未绑定属性组件时")

	# 属性夹具覆盖整数、小数、比率和穿透的代表值。
	var attributes := FakeAttributeComponent.new()
	attributes.values = {
		0: 12.0,
		1: 3.26,
		2: 8.5,
		3: 4.0,
		4: 6.75,
		5: 123.0,
		6: 45.46,
		7: 7.0,
		8: 0.125,
		9: 2.25,
		10: 0.08,
		11: 0.123,
		12: 1.5,
		13: 0.045,
		14: 0.0,
	}
	ui.call("Bind", attributes)

	assert_eq(_label_text(ui, "PhysAtkValue"), "12", "整数物攻必须省略小数部分。")
	assert_eq(_label_text(ui, "PhysDefValue"), "3.3", "小数物防必须四舍五入到一位。")
	assert_eq(_label_text(ui, "MagPowerValue"), "8.5", "法强必须保留一位有效小数。")
	assert_eq(_label_text(ui, "MagResistValue"), "4", "整数法抗必须省略小数部分。")
	assert_eq(_label_text(ui, "SpeedValue"), "6.8", "速度必须按旧 0.# 格式显示。")
	assert_eq(_label_text(ui, "MaxHealthDetailValue"), "123", "生命上限必须使用普通数值格式。")
	assert_eq(_label_text(ui, "MaxEnergyDetailValue"), "45.5", "能量上限必须保留至多一位小数。")
	assert_eq(_label_text(ui, "PhysPenetrationDetailValue"), "7 | 12.5%", "物理穿透必须组合固定值与一位百分比。")
	assert_eq(_label_text(ui, "MagicPenetrationDetailValue"), "2.3 | 8%", "法术穿透百分比为整数时不得保留 .0。")
	assert_eq(_label_text(ui, "CritRateDetailValue"), "12.3%", "暴击率必须转换为百分比。")
	assert_eq(_label_text(ui, "CritDamageDetailValue"), "150%", "暴击伤害整数百分比必须省略小数。")
	assert_eq(_label_text(ui, "EvasionRateDetailValue"), "4.5%", "闪避率必须保留一位百分比。")
	assert_eq(_label_text(ui, "LifestealRateDetailValue"), "0%", "零吸血率必须显示为整数百分比。")
	_dispose_ui(ui)


## 验证两个属性信号都会刷新，并且重复绑定不会重复连接。
## 返回值：无。
func test_signal_driven_refresh_and_rebind_cleanup() -> void:
	# 并行 UI 夹具用于观察信号触发后的标签变化。
	var ui: PanelContainer = _new_attribute_summary_ui()
	# 首个属性组件用于验证连接、刷新和旧连接清理。
	var first := FakeAttributeComponent.new()
	first.values[0] = 10.0
	ui.call("Bind", first)
	# 属性变化回调用于核对连接生命周期。
	var attribute_callback := Callable(ui, "_on_attribute_changed")
	# 点数变化回调用于核对连接生命周期。
	var points_callback := Callable(ui, "_on_available_points_changed")
	assert_true(first.AttributeChanged.is_connected(attribute_callback), "Bind 必须连接 AttributeChanged。")
	assert_true(first.AvailablePointsChanged.is_connected(points_callback), "Bind 必须连接 AvailablePointsChanged。")

	first.set_effective_value(0, 11.5)
	assert_eq(_label_text(ui, "PhysAtkValue"), "11.5", "AttributeChanged 必须立即刷新摘要。")
	first.values[1] = 9.0
	first.notify_available_points_changed(2)
	assert_eq(_label_text(ui, "PhysDefValue"), "9", "AvailablePointsChanged 必须立即刷新摘要。")

	ui.call("Bind", first)
	assert_true(first.AttributeChanged.is_connected(attribute_callback), "重复绑定同一组件后信号必须仍保持单一有效连接。")
	# 第二个属性组件用于验证重绑后的显示来源和旧连接移除。
	var second := FakeAttributeComponent.new()
	second.values[0] = 20.0
	ui.call("Bind", second)
	assert_false(first.AttributeChanged.is_connected(attribute_callback), "切换组件时必须解除旧 AttributeChanged。")
	assert_false(first.AvailablePointsChanged.is_connected(points_callback), "切换组件时必须解除旧 AvailablePointsChanged。")
	assert_eq(_label_text(ui, "PhysAtkValue"), "20", "切换组件后必须读取新组件值。")
	_dispose_ui(ui)


## 验证详情按钮打开弹窗，并在退出场景树时清理全部信号。
## 返回值：无。
func test_details_popup_and_exit_cleanup() -> void:
	# 并行 UI 夹具用于触发真实按钮和出树生命周期。
	var ui: PanelContainer = _new_attribute_summary_ui()
	# 属性夹具用于核对退出后的两个信号连接。
	var attributes := FakeAttributeComponent.new()
	ui.call("Bind", attributes)
	# 生产唯一名称定位到详情按钮。
	var details_button := ui.get_node("%DetailsButton") as Button
	# 生产唯一名称定位到详情弹窗。
	var details_popup := ui.get_node("%AttributeDetailsPopup") as PopupPanel
	details_button.pressed.emit()
	assert_true(details_popup.visible, "详情按钮必须请求居中打开属性详情弹窗。")

	# 属性变化回调用于核对退出清理。
	var attribute_callback := Callable(ui, "_on_attribute_changed")
	# 点数变化回调用于核对退出清理。
	var points_callback := Callable(ui, "_on_available_points_changed")
	# 按钮回调用于核对退出清理。
	var button_callback := Callable(ui, "_on_details_button_pressed")
	# 编辑器主循环提供真实场景树的移除生命周期。
	var scene_tree := Engine.get_main_loop() as SceneTree
	scene_tree.root.remove_child(ui)
	assert_false(attributes.AttributeChanged.is_connected(attribute_callback), "退出场景树时必须解除 AttributeChanged。")
	assert_false(attributes.AvailablePointsChanged.is_connected(points_callback), "退出场景树时必须解除 AvailablePointsChanged。")
	assert_false(details_button.pressed.is_connected(button_callback), "退出场景树时必须解除详情按钮。")
	ui.free()


## 构造与生产唯一节点名一致的轻量属性摘要树并触发正常 Ready 生命周期。
## 返回值：已进入场景树的 AttributeSummaryUI。
func _new_attribute_summary_ui() -> PanelContainer:
	# 新建生产脚本根节点，以最小子树独立验证视图逻辑。
	var ui := ATTRIBUTE_SUMMARY_UI_SCRIPT.new() as PanelContainer
	ui.name = "AttributeSummaryUIContractProbe"
	for label_name: String in [
		"PhysAtkValue",
		"PhysDefValue",
		"MagPowerValue",
		"MagResistValue",
		"SpeedValue",
		"MaxHealthDetailValue",
		"MaxEnergyDetailValue",
		"PhysPenetrationDetailValue",
		"MagicPenetrationDetailValue",
		"CritRateDetailValue",
		"CritDamageDetailValue",
		"EvasionRateDetailValue",
		"LifestealRateDetailValue",
	]:
		# 每个标签使用生产场景相同的唯一名称。
		var label := Label.new()
		label.name = label_name
		label.unique_name_in_owner = true
		ui.add_child(label)
		label.owner = ui
	# 详情按钮保留生产场景唯一名称和 pressed 信号。
	var details_button := Button.new()
	details_button.name = "DetailsButton"
	details_button.unique_name_in_owner = true
	ui.add_child(details_button)
	details_button.owner = ui
	# PopupPanel 允许测试真实 popup_centered 请求。
	var details_popup := PopupPanel.new()
	details_popup.name = "AttributeDetailsPopup"
	details_popup.unique_name_in_owner = true
	ui.add_child(details_popup)
	details_popup.owner = ui
	# 编辑器主循环提供 is_node_ready 所需的真实场景树状态。
	var scene_tree := Engine.get_main_loop() as SceneTree
	scene_tree.root.add_child(ui)
	# 非 @tool 生产脚本在编辑器测试中不会自动执行脚本生命周期；节点入树后显式调用可保留 is_node_ready 契约。
	ui.call("_ready")
	return ui


## 读取指定唯一名称 Label 的文本。
## 参数 ui：属性摘要根节点。
## 参数 label_name：生产场景使用的唯一节点名。
## 返回值：标签当前文本。
func _label_text(ui: PanelContainer, label_name: String) -> String:
	return (ui.get_node("%%%s" % label_name) as Label).text


## 断言摘要和详情的每个显示值都使用同一占位文本。
## 参数 ui：属性摘要根节点。
## 参数 expected：预期占位文本。
## 参数 context：失败信息的场景前缀。
## 返回值：无。
func _assert_all_values(ui: PanelContainer, expected: String, context: String) -> void:
	for label_name: String in [
		"PhysAtkValue",
		"PhysDefValue",
		"MagPowerValue",
		"MagResistValue",
		"SpeedValue",
		"MaxHealthDetailValue",
		"MaxEnergyDetailValue",
		"PhysPenetrationDetailValue",
		"MagicPenetrationDetailValue",
		"CritRateDetailValue",
		"CritDamageDetailValue",
		"EvasionRateDetailValue",
		"LifestealRateDetailValue",
	]:
		assert_eq(_label_text(ui, label_name), expected, "%s%s 必须显示 %s。" % [context, label_name, expected])


## 从场景树移除并释放测试 UI，使 _exit_tree 清理逻辑接受真实生命周期验证。
## 参数 ui：需要销毁的属性摘要根节点。
## 返回值：无。
func _dispose_ui(ui: PanelContainer) -> void:
	if ui == null:
		return
	if ui.is_inside_tree():
		ui.get_parent().remove_child(ui)
	ui.free()
