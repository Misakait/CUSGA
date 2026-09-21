@tool
extends McpTestSuite

## 开发者设置面板（DevSettingsUI）与序列匹配器（DevSequenceMatcher）的行为契约套件。
##
## 面板自身带 @onready 场景依赖，无法在真实游戏进程之外直接实例化，
## 因此本套件用「最小节点树 + 伪 TimeSystem」的方式验证它与时间系统的协议，
## 以及序列匹配的纯逻辑边界。

## 待验证的面板脚本。
const DEV_SETTINGS_UI_SCRIPT: GDScript = preload("res://core/ui/dev/dev_settings_ui.gd")

## 待验证的序列匹配器脚本。
const DEV_SEQUENCE_MATCHER_SCRIPT: GDScript = preload("res://core/ui/dev/dev_sequence_matcher.gd")


## 返回 GodotAI 使用的稳定套件名称。
## 返回值：开发者设置契约套件名。
func suite_name() -> String:
	return "dev_settings_contract"


## 提供面板所需的稳定协议，并刻意把阶段长度设为 120。
##
## 阶段长度不同于生产值 100 是刻意设计：面板若硬编码 100，本套件的
## 「下一天」期望值就会失败，从而真正验证面板读取的是时间系统的值。
class FakeTimeSystem extends Node:
	## 时间快照变化时发出全部旧参数。
	signal TimeChanged(total_time_passed, current_day, is_night, phase_progress, phase_length)

	## 刻意区别于生产值 100 的阶段长度，用于证明面板动态读取而非硬编码。
	const PhaseLength: int = 120

	## 开局以来累计的总时间。
	var TotalTimePassed: int = 0
	## 当前天数。
	var CurrentDay: int = 1
	## 当前是否为夜晚。
	var IsNight: bool = false
	## 当前阶段内的进度。
	var PhaseProgress: int = 0
	## 地图移动消耗的行动值。
	var MapMoveTimeCost: int = 10
	## 记录每次推进请求的实际点数，用于断言面板确实走了 PassTime。
	var pass_time_calls: Array[int] = []

	## 按生产 TimeSystem 的既有规则推进时间：每阶段切换昼夜，每两个阶段天数加一。
	## 参数 amount：本次增加的行动值点数；非正数会被忽略。
	## 返回值：无。
	func PassTime(amount: int) -> void:
		if amount <= 0:
			return

		pass_time_calls.append(amount)
		var previous_total: int = TotalTimePassed
		TotalTimePassed += amount
		var old_phase: int = previous_total / PhaseLength
		var new_phase: int = TotalTimePassed / PhaseLength
		for phase: int in range(old_phase + 1, new_phase + 1):
			IsNight = not IsNight
			if phase % 2 == 0:
				CurrentDay += 1
		PhaseProgress = TotalTimePassed % PhaseLength
		TimeChanged.emit(TotalTimePassed, CurrentDay, IsNight, PhaseProgress, PhaseLength)

	## 设置地图移动耗时，保留生产实现「只接受正数」的守卫。
	## 参数 amount：新的耗时；非正数不会覆盖当前值。
	## 返回值：无。
	func SetMapMoveTimeCost(amount: int) -> void:
		if amount > 0:
			MapMoveTimeCost = amount


## 验证序列匹配器的完整触发、错键容错与无效输入边界。
## 返回值：无。
func test_sequence_matcher_accepts_only_the_exact_sequence() -> void:
	var dev_sequence: String = str(DEV_SETTINGS_UI_SCRIPT.get_script_constant_map()["DEV_SEQUENCE"])
	var matcher = DEV_SEQUENCE_MATCHER_SCRIPT.new()

	assert_eq(matcher.get_progress(), 0, "初始进度必须为 0。")

	# 只送前缀不得触发，但必须逐字累积。
	matcher.reset()
	assert_false(
		_push_all(matcher, dev_sequence.substr(0, dev_sequence.length() - 1)),
		"未凑齐完整序列时不得返回 true。"
	)
	assert_eq(matcher.get_progress(), dev_sequence.length() - 1, "前缀必须被逐字累积。")

	# 完整序列必须触发，并在触发后归零。
	matcher.reset()
	assert_true(_push_all(matcher, dev_sequence), "凑齐完整序列必须返回 true。")
	assert_eq(matcher.get_progress(), 0, "凑齐后进度必须归零，允许立即再次触发。")

	# 多按一次首字母后仍应能触发，保证隐藏序列的容错预期。
	matcher.reset()
	assert_true(
		_push_all(matcher, dev_sequence[0] + dev_sequence),
		"重复按下首字母后仍必须能凑齐序列。"
	)

	# 中间按错字母必须打断序列。
	matcher.reset()
	assert_false(
		_push_all(matcher, dev_sequence[0] + "X" + dev_sequence.substr(1)),
		"中间按错字母后不得触发。"
	)

	# 非单字母输入不得污染进度。
	matcher.reset()
	matcher.push_letter("Shift")
	assert_eq(matcher.get_progress(), 0, "非单字母输入不得改变进度。")


## 验证未处理输入监听只在凑齐完整序列时打开面板，且重复输入是幂等的。
## 返回值：无。
func test_unhandled_input_opens_panel_only_after_full_sequence() -> void:
	var scene_tree := Engine.get_main_loop() as SceneTree
	var time_system := _install_fake_time_system(scene_tree)
	if time_system == null:
		return
	var ui := _new_dev_settings_ui(scene_tree)
	var ui_matcher: Variant = ui.get("_matcher")

	assert_false(ui.visible, "面板初始必须隐藏。")

	for letter in ["L", "I", "S", "B", "A"]:
		ui.call("_unhandled_input", _make_key_event(letter))
	assert_false(ui.visible, "未凑齐完整序列时不得打开面板。")

	ui.call("_unhandled_input", _make_key_event("M"))
	assert_true(ui.visible, "凑齐 LISBAM 必须打开面板。")

	# 已打开时再次输入完整序列必须保持打开，而不是创建第二个面板。
	for letter in ["L", "I", "S", "B", "A", "M"]:
		ui.call("_unhandled_input", _make_key_event(letter))
	assert_true(ui.visible, "重复输入完整序列必须保持面板打开。")

	# 普通按键推进进度，而键盘重复事件必须被忽略。
	ui_matcher.reset()
	ui.call("_unhandled_input", _make_key_event("L"))
	assert_eq(ui_matcher.get_progress(), 1, "普通按键必须推进序列进度。")

	var echo_event := _make_key_event("I")
	echo_event.echo = true
	ui.call("_unhandled_input", echo_event)
	assert_eq(ui_matcher.get_progress(), 1, "键盘重复事件不得推进序列进度。")

	# 关闭按钮必须隐藏面板。
	var close_button := ui.get_node("%CloseButton") as Button
	close_button.pressed.emit()
	assert_false(ui.visible, "关闭按钮必须隐藏面板。")

	_dispose(scene_tree, ui, time_system)


## 验证「下一天」按时间系统的阶段长度推进到下一个天数边界。
## 返回值：无。
func test_next_day_advances_to_the_next_day() -> void:
	var scene_tree := Engine.get_main_loop() as SceneTree
	var time_system := _install_fake_time_system(scene_tree)
	if time_system == null:
		return
	var ui := _new_dev_settings_ui(scene_tree)

	# 阶段长度为 120，因此一天是两个阶段共 240 点。
	var cases: Array = [
		{"total": 0, "expected": 240},
		{"total": 50, "expected": 190},
		{"total": 150, "expected": 90},
		{"total": 240, "expected": 240},
	]
	for test_case: Dictionary in cases:
		time_system.set("TotalTimePassed", int(test_case["total"]))
		assert_eq(
			int(ui.call("_get_points_to_next_day")),
			int(test_case["expected"]),
			"总时间 %d 时的推进点数必须落在下一个偶数阶段边界。" % int(test_case["total"])
		)

	time_system.set("TotalTimePassed", 0)
	time_system.set("CurrentDay", 1)
	var next_day_button := ui.get_node("%NextDayButton") as Button
	next_day_button.pressed.emit()

	var pass_calls: Array = time_system.get("pass_time_calls")
	assert_eq(pass_calls.size(), 1, "「下一天」必须且只能推进一次时间。")
	assert_eq(int(pass_calls[0]), 240, "推进点数必须落在下一个偶数阶段边界。")
	assert_eq(int(time_system.get("CurrentDay")), 2, "推进后天数必须增加 1。")

	_dispose(scene_tree, ui, time_system)


## 验证行动值消耗控件写入时间系统，并把越界输入夹紧到合法范围。
## 返回值：无。
func test_cost_spin_box_writes_through_and_clamps() -> void:
	var scene_tree := Engine.get_main_loop() as SceneTree
	var time_system := _install_fake_time_system(scene_tree)
	if time_system == null:
		return
	var ui := _new_dev_settings_ui(scene_tree)
	var spin_box := ui.get_node("%CostSpinBox") as SpinBox

	assert_eq(int(spin_box.value), 10, "行动值消耗控件必须默认显示 10。")

	spin_box.value = 25
	assert_eq(int(time_system.get("MapMoveTimeCost")), 25, "合法值必须立即写入时间系统。")

	# 越界输入由 SpinBox 的 min_value 夹紧，不得把时间系统置为非法值。
	spin_box.value = 0
	assert_eq(int(spin_box.value), 1, "越界输入必须被夹紧到控件下界。")
	assert_eq(int(time_system.get("MapMoveTimeCost")), 1, "夹紧后的值才是写入时间系统的值。")

	var reset_button := ui.get_node("%ResetCostButton") as Button
	reset_button.pressed.emit()
	assert_eq(int(time_system.get("MapMoveTimeCost")), 10, "「恢复默认」必须把行动值消耗写回 10。")

	_dispose(scene_tree, ui, time_system)


## 验证 TimeChanged 快照刷新天数标签，且退出场景树时解除连接。
## 返回值：无。
func test_time_changed_refreshes_day_label_and_disconnects() -> void:
	var scene_tree := Engine.get_main_loop() as SceneTree
	var time_system := _install_fake_time_system(scene_tree)
	if time_system == null:
		return
	var ui := _new_dev_settings_ui(scene_tree)
	var day_label := ui.get_node("%DayLabel") as Label
	var callback := Callable(ui, "_on_time_changed")

	assert_eq(day_label.text, "当前天数：1", "面板必须显示时间系统的初始天数。")
	assert_true(time_system.is_connected(&"TimeChanged", callback), "面板必须连接 TimeChanged。")

	time_system.call("PassTime", 240)
	assert_eq(day_label.text, "当前天数：2", "TimeChanged 必须刷新天数标签。")

	scene_tree.root.remove_child(ui)
	assert_false(time_system.is_connected(&"TimeChanged", callback), "退出场景树时必须解除 TimeChanged。")

	_dispose(scene_tree, ui, time_system)


## 把字符串逐字送入匹配器。
## 参数 matcher：待验证的序列匹配器实例。
## 参数 text：按顺序送入的字符序列。
## 返回值：最后一次送入是否凑齐完整序列。
func _push_all(matcher: Variant, text: String) -> bool:
	var completed: bool = false
	for index in range(text.length()):
		completed = matcher.push_letter(text[index])
	return completed


## 安装伪 TimeSystem 到测试根节点。
##
## 编辑器测试根节点不应已有 TimeSystem；若已存在则直接失败，避免覆盖真实 Autoload
## 而让断言失去意义。
##
## 参数 scene_tree：当前测试的主循环。
## 返回值：已进入场景树的伪 TimeSystem；前置条件不满足时返回 null。
func _install_fake_time_system(scene_tree: SceneTree) -> Node:
	var existing := scene_tree.root.get_node_or_null("TimeSystem")
	assert_eq(existing, null, "编辑器测试根节点不应已有 TimeSystem，以免覆盖真实 Autoload。")
	if existing != null:
		return null

	var time_system := FakeTimeSystem.new()
	time_system.name = "TimeSystem"
	scene_tree.root.add_child(time_system)
	return time_system


## 用最小节点树构造面板，避免复刻整棵场景层级。
## 参数 scene_tree：当前测试的主循环。
## 返回值：已进入场景树并完成初始同步的面板。
func _new_dev_settings_ui(scene_tree: SceneTree) -> Control:
	var ui := DEV_SETTINGS_UI_SCRIPT.new() as Control
	ui.name = "DevSettingsUIContractProbe"
	_add_unique_child(ui, "DayLabel", Label.new())
	_add_unique_child(ui, "CostSpinBox", SpinBox.new())
	_add_unique_child(ui, "NextDayButton", Button.new())
	_add_unique_child(ui, "ResetCostButton", Button.new())
	_add_unique_child(ui, "CloseButton", Button.new())
	scene_tree.root.add_child(ui)
	return ui


## 把子节点注册为父节点的唯一名，让面板的 %Name 访问生效。
## 参数 parent：唯一名所属的节点。
## 参数 child_name：唯一名。
## 参数 child：待注册的子控件。
## 返回值：无。
func _add_unique_child(parent: Control, child_name: String, child: Control) -> void:
	child.name = child_name
	child.unique_name_in_owner = true
	parent.add_child(child)
	child.owner = parent


## 构造一个按下状态的字母按键事件。
## 参数 letter：单个大写字母。
## 返回值：携带对应物理键位的按键事件。
func _make_key_event(letter: String) -> InputEventKey:
	var event := InputEventKey.new()
	event.pressed = true
	event.echo = false
	event.physical_keycode = OS.find_keycode_from_string(letter)
	return event


## 释放测试期间创建的面板与伪 TimeSystem。
## 参数 scene_tree：当前测试的主循环。
## 参数 ui：本用例创建的面板。
## 参数 time_system：本用例创建的伪 TimeSystem。
## 返回值：无。
func _dispose(scene_tree: SceneTree, ui: Control, time_system: Node) -> void:
	if is_instance_valid(ui):
		if ui.get_parent() != null:
			scene_tree.root.remove_child(ui)
		ui.free()
	if is_instance_valid(time_system):
		if time_system.get_parent() != null:
			scene_tree.root.remove_child(time_system)
		time_system.free()
