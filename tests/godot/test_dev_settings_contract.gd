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

## 生产场景路径，用于锁定「一个功能一行」的排版契约。
const DEV_SETTINGS_SCENE_PATH: String = "res://scenes/ui_scenes/dev_settings_ui.tscn"

## 局外入口（主菜单）场景路径。
## 它必须复用同一份面板场景，而不是另建一套内容不同的开发者菜单。
const MAIN_MENU_SCENE_PATH: String = "res://scenes/main_menu_scenes/main_menu.tscn"

## 局内主场景路径。
## 它保留全套功能，用来对照局外入口确实只关掉了局内专属的那部分。
const MAIN_SCENE_PATH: String = "res://scenes/Main.tscn"

## 仓库场景路径。
## 它同样属于局外，也必须复用同一份面板。
const WAREHOUSE_SCENE_PATH: String = "res://scenes/Warehouse/Warehouse.tscn"

## 局外入口场景清单（入口名 → 场景路径）。
##
## 局外的每一处入口都必须复用同一份面板场景，并且都必须关掉局内专属功能；把它写成清单
## 而不是逐个写断言，是为了将来新增入口（例如商店）时只改一处。
const OUT_OF_RUN_ENTRY_SCENES: Dictionary = {
	"主菜单": MAIN_MENU_SCENE_PATH,
	"仓库": WAREHOUSE_SCENE_PATH,
}

## 必须各自独占一行的功能控件。
## 它们都直接挂在主纵向容器下，因此父路径本身就能证明「没有被并排分组」。
##
## GainGoldButton 刻意不在这份清单里：它是「获得金币」这一个功能的组成部分，与自己的
## 输入框同处 GoldRow 一行，由 GOLD_BUTTON_ROW_PARENT 单独锁定。
const REQUIRED_VBOX_ROWS: Array[String] = [
	"DayLabel",
	"CostRow",
	"NextDayButton",
	"LevelUpButton",
	"ResetCostButton",
	"GoldRow",
	"CloseButton",
]

## 「获得金币」按钮必须与数量输入框同处一行：按钮的声明行里必须出现指向 GoldRow 的父路径。
## 只比对路径尾部，既够精确又不必把整条层级路径抄第二遍。
const GOLD_ROW_PARENT_SUFFIX: String = "VBoxContainer/GoldRow\""

## 上述控件在生产场景中必须使用的直接父节点声明。
const REQUIRED_ROW_PARENT: String = "parent=\"CenterOverlay/Panel/MarginContainer/VBoxContainer\""


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


## 记录升级请求的伪等级系统。
##
## 刻意只实现 AddLevels 这一个公开接口：面板若绕过它去读写等级系统的内部字段或
## 另调其它方法，本套件就会当场暴露出来。
class FakePlayerLevel extends Node:
	## 每次 AddLevels 的入参，用于断言面板确实按「一级」驱动。
	var add_levels_calls: Array[int] = []

	## 记录一次升级请求。
	## 参数 count：请求提升的级数。
	## 返回值：实际提升的级数，这里与请求值相同。
	func AddLevels(count: int) -> int:
		add_levels_calls.append(count)
		return count


## 记录增发请求的伪钱包。
##
## 同样刻意只实现 Add 这一个公开接口：面板若绕过它去直接改写余额字段，本套件就会当场
## 暴露出来——直接写字段会让余额显示与存档层都收不到这次变化。
class FakeWallet extends Node:
	## 每次 Add 的入参，用于断言面板确实按输入框当前值增发。
	var add_calls: Array[int] = []

	## 记录一次增发请求。
	## 参数 amount：请求增发的金币数量。
	## 返回值：无。
	func Add(amount: int) -> void:
		add_calls.append(amount)


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


## 验证「获得金币」按输入框当前值增发金币，且每次都走钱包的公开接口。
## 返回值：无。
func test_gain_gold_button_adds_the_entered_amount() -> void:
	var scene_tree := Engine.get_main_loop() as SceneTree
	var time_system := _install_fake_time_system(scene_tree)
	if time_system == null:
		return
	var wallet := _install_fake_wallet(scene_tree)
	if wallet == null:
		_dispose(scene_tree, null, time_system)
		return

	var ui := _new_dev_settings_ui(scene_tree)
	var gold_spin_box := ui.get_node("%GoldSpinBox") as SpinBox
	var gain_button := ui.get_node("%GainGoldButton") as Button

	assert_eq(int(gold_spin_box.value), 1000, "金币输入框必须默认显示 1000。")

	gain_button.pressed.emit()
	var add_calls: Array = wallet.get("add_calls")
	assert_eq(add_calls.size(), 1, "点击必须且只能请求一次增发。")
	assert_eq(int(add_calls[0]), 1000, "必须按输入框当前值增发。")

	# 第二次换一个数量：证明面板读的是控件的实时值，而不是把默认值写死。
	gold_spin_box.value = 250
	gain_button.pressed.emit()
	add_calls = wallet.get("add_calls")
	assert_eq(add_calls.size(), 2, "第二次点击必须再请求一次增发。")
	assert_eq(int(add_calls[1]), 250, "必须按新的输入值增发，而不是沿用默认值。")

	# 这个按钮只负责给钱，不得顺带开关面板。
	assert_false(ui.visible, "「获得金币」不得意外打开面板。")

	_dispose(scene_tree, ui, time_system, null, wallet)


## 验证金币输入框在控件层就把非法输入夹紧，而不是留给下游判断。
## 返回值：无。
func test_gold_spin_box_clamps_input_to_the_documented_range() -> void:
	var scene_tree := Engine.get_main_loop() as SceneTree
	var time_system := _install_fake_time_system(scene_tree)
	if time_system == null:
		return
	var ui := _new_dev_settings_ui(scene_tree)
	var gold_spin_box := ui.get_node("%GoldSpinBox") as SpinBox

	assert_eq(int(gold_spin_box.min_value), 1, "金币下界必须是 1。")
	assert_eq(int(gold_spin_box.max_value), 999999, "金币上界必须是 999999。")
	assert_false(gold_spin_box.allow_greater, "必须关闭越界放行，否则上界形同虚设。")
	assert_false(gold_spin_box.allow_lesser, "必须关闭越界放行，否则下界形同虚设。")

	# 越界输入必须被控件自身夹紧：无论玩家手输还是脚本写入，非法值都不得留在控件里。
	gold_spin_box.value = 0
	assert_eq(int(gold_spin_box.value), 1, "低于下界的输入必须被夹紧到下界。")
	gold_spin_box.value = 5000000
	assert_eq(int(gold_spin_box.value), 999999, "高于上界的输入必须被夹紧到上界。")

	_dispose(scene_tree, ui, time_system)


## 验证钱包缺失时「获得金币」静默无效，且不拖累面板其余功能。
##
## 与「增加一级」缺少等级系统时同一套降级语义：装配问题不该让整个面板失效。
## 返回值：无。
func test_gain_gold_button_is_inert_without_wallet() -> void:
	var scene_tree := Engine.get_main_loop() as SceneTree
	var missing := scene_tree.root.get_node_or_null("PlayerWallet")
	assert_eq(missing, null, "本用例要求测试根节点没有 PlayerWallet。")
	if missing != null:
		return

	var time_system := _install_fake_time_system(scene_tree)
	if time_system == null:
		return
	var ui := _new_dev_settings_ui(scene_tree)
	var gain_button := ui.get_node("%GainGoldButton") as Button

	gain_button.pressed.emit()
	assert_true(is_instance_valid(ui), "缺少钱包时点击不得使面板失效。")
	assert_false(ui.visible, "缺少钱包时点击不得意外打开面板。")

	_dispose(scene_tree, ui, time_system)


## 验证局内专属功能按导出开关整组显隐，而金币相关控件在两种模式下都保留。
##
## 这是「一套代码两处入口」的核心约束：局外只是关掉了一组控件，而不是换了一份面板。
## 若有人改成「局外另建一套面板」，这条与入口场景契约都会失败。
## 返回值：无。
func test_run_features_visibility_follows_the_export_switch() -> void:
	var scene_tree := Engine.get_main_loop() as SceneTree
	var time_system := _install_fake_time_system(scene_tree)
	if time_system == null:
		return

	var run_only_names: Array[String] = [
		"%DayLabel",
		"%CostRow",
		"%ResetCostButton",
		"%NextDayButton",
		"%LevelUpButton",
	]
	var always_names: Array[String] = ["%GoldSpinBox", "%GainGoldButton", "%CloseButton"]

	# 局内：整组功能都必须可见。
	var in_run_ui := _new_dev_settings_ui(scene_tree, true)
	for node_name: String in run_only_names:
		assert_true(
			(in_run_ui.get_node(node_name) as CanvasItem).visible,
			"局内模式下 %s 必须可见。" % node_name
		)
	var in_run_gold := in_run_ui.get_node("%GoldSpinBox") as SpinBox
	assert_eq(int(in_run_gold.value), 1000, "局内模式下金币输入框必须可用。")
	# 只释放面板本身，伪时间系统留给下半段复用。
	_dispose(scene_tree, in_run_ui, null)

	# 局外：只剩金币相关控件。
	var out_of_run_ui := _new_dev_settings_ui(scene_tree, false)
	for node_name: String in run_only_names:
		assert_false(
			(out_of_run_ui.get_node(node_name) as CanvasItem).visible,
			"局外模式下 %s 必须隐藏，它能起的作用都只存在于局内。" % node_name
		)
	for node_name: String in always_names:
		assert_true(
			(out_of_run_ui.get_node(node_name) as CanvasItem).visible,
			"局外模式下 %s 必须保留。" % node_name
		)
	var out_of_run_gold := out_of_run_ui.get_node("%GoldSpinBox") as SpinBox
	assert_eq(int(out_of_run_gold.value), 1000, "局外模式下金币输入框必须可用。")

	_dispose(scene_tree, out_of_run_ui, time_system)


## 验证「增加一级」按钮通过等级系统的公开接口请求升级，且每次点击只提升一级。
## 返回值：无。
func test_level_up_button_advances_player_level_once() -> void:
	var scene_tree := Engine.get_main_loop() as SceneTree
	var time_system := _install_fake_time_system(scene_tree)
	if time_system == null:
		return
	var player_level := _install_fake_player_level(scene_tree)
	if player_level == null:
		_dispose(scene_tree, null, time_system)
		return
	var ui := _new_dev_settings_ui(scene_tree)
	var level_up_button := ui.get_node("%LevelUpButton") as Button

	# 光是创建面板不得升级：按钮点击是唯一触发点。
	assert_eq(
		(player_level.get("add_levels_calls") as Array).size(),
		0,
		"创建面板本身不得请求升级。"
	)

	level_up_button.pressed.emit()
	var calls: Array = player_level.get("add_levels_calls")
	assert_eq(calls.size(), 1, "点击一次必须且只能请求一次升级。")
	assert_eq(int(calls[0]), 1, "每次点击必须恰好提升一级，而不是一次性跳级。")

	level_up_button.pressed.emit()
	assert_eq(
		(player_level.get("add_levels_calls") as Array).size(),
		2,
		"再次点击必须再请求一次升级。"
	)

	_dispose(scene_tree, ui, time_system, player_level)


## 验证等级系统缺失时「增加一级」按钮静默无效，而不是让面板失效。
##
## 等级系统是可选依赖：这条路径保证把 PlayerLevel 从 project.godot 摘掉之后，面板其余
## 功能仍然可用，不会因为按钮在 null 上调用方法而中断。
## 返回值：无。
func test_level_up_button_is_inert_without_player_level() -> void:
	var scene_tree := Engine.get_main_loop() as SceneTree
	var time_system := _install_fake_time_system(scene_tree)
	if time_system == null:
		return
	var missing := scene_tree.root.get_node_or_null("PlayerLevel")
	assert_eq(missing, null, "本用例要求测试根节点没有 PlayerLevel。")
	if missing != null:
		_dispose(scene_tree, null, time_system)
		return

	var ui := _new_dev_settings_ui(scene_tree)
	var level_up_button := ui.get_node("%LevelUpButton") as Button

	level_up_button.pressed.emit()
	assert_true(is_instance_valid(ui), "缺少等级系统时点击不得使面板失效。")
	assert_false(ui.visible, "缺少等级系统时点击不得意外打开面板。")

	_dispose(scene_tree, ui, time_system)


## 验证生产场景按「一个功能一行」排版，且行动值消耗标签措辞符合要求。
##
## 断言的是控件声明行里的直接父路径：只要它们都直接挂在主纵向容器下，排版就必然是每个
## 功能独占一行。这条断言在有人把按钮重新并排分组时会立刻失败。
## 返回值：无。
func test_production_scene_layout_places_each_feature_on_its_own_row() -> void:
	var scene_text: String = FileAccess.get_file_as_string(DEV_SETTINGS_SCENE_PATH)
	assert_false(scene_text.is_empty(), "必须能读到开发者设置场景。")

	for node_name: String in REQUIRED_VBOX_ROWS:
		var declaration: String = _find_node_declaration(scene_text, node_name)
		assert_true(not declaration.is_empty(), "场景必须包含功能控件 %s。" % node_name)
		assert_true(
			declaration.contains(REQUIRED_ROW_PARENT),
			"%s 必须直接挂在主纵向容器下，以保证每个功能独占一行。" % node_name
		)

	# 旧的横向按钮分组必须消失，否则「一个功能一行」会被悄悄改回去。
	assert_false(
		scene_text.contains("ButtonRow"),
		"功能控件不得再被横向分组，每个功能必须独占一行。"
	)
	assert_true(
		scene_text.contains("text = \"每次行动消耗的行动值\""),
		"行动值消耗标签必须显示「每次行动消耗的行动值」。"
	)
	assert_true(scene_text.contains("text = \"增加一级\""), "必须保留「增加一级」按钮。")

	# 金币按钮与它的数量输入框刻意同处一行：这两个控件合起来才是「获得金币」一个功能，
	# 拆成两行会被读成两个互不相干的东西。
	var gold_button_declaration: String = _find_node_declaration(scene_text, "GainGoldButton")
	assert_true(not gold_button_declaration.is_empty(), "场景必须包含「获得金币」按钮。")
	assert_true(
		gold_button_declaration.contains(GOLD_ROW_PARENT_SUFFIX),
		"「获得金币」按钮必须与数量输入框同处 GoldRow 一行。"
	)


## 验证生产场景为「获得金币」提供了数字输入框与增发按钮，并写清了默认值与上界。
##
## 场景是编辑器里看得见的那一份，脚本常量是运行时权威的那一份。两者都断言，才能避免
## 「改了一处忘了另一处」。
## 返回值：无。
func test_production_scene_exposes_the_gold_input_contract() -> void:
	var scene_text: String = FileAccess.get_file_as_string(DEV_SETTINGS_SCENE_PATH)
	assert_false(scene_text.is_empty(), "必须能读到开发者设置场景。")

	assert_true(scene_text.contains("text = \"获得金币数量\""), "必须保留金币输入行的说明文字。")
	assert_true(scene_text.contains("text = \"获得金币\""), "必须保留「获得金币」按钮。")
	assert_true(scene_text.contains("value = 1000.0"), "金币输入框的默认值必须是 1000。")
	assert_true(scene_text.contains("max_value = 999999.0"), "金币输入框的上界必须是 999999。")

	var constants: Dictionary = DEV_SETTINGS_UI_SCRIPT.get_script_constant_map()
	assert_eq(int(constants["DEFAULT_GOLD_AMOUNT"]), 1000, "脚本里的默认值常量必须与需求一致。")
	assert_eq(int(constants["MAX_GOLD_AMOUNT"]), 999999, "脚本里的上界常量必须与需求一致。")


## 验证每一个入口都复用同一份面板，且恰好只有局外那些入口关掉了局内专属功能。
##
## 这条断言就是「直接复用，不要分叉」这条需求的可执行形式：一旦有人为某个入口复制出
## 一份内容不同的开发者菜单，或者新增入口时漏了设开关，这里都会立刻失败。
## 返回值：无。
func test_all_entry_points_share_one_panel_and_only_out_of_run_ones_hide_run_features() -> void:
	for entry_name: String in OUT_OF_RUN_ENTRY_SCENES:
		var entry_scene_path: String = str(OUT_OF_RUN_ENTRY_SCENES[entry_name])
		var entry_text: String = FileAccess.get_file_as_string(entry_scene_path)
		assert_false(
			entry_text.is_empty(),
			"必须能读到%s场景：%s。" % [entry_name, entry_scene_path]
		)
		assert_true(
			entry_text.contains(DEV_SETTINGS_SCENE_PATH),
			"%s必须复用同一份开发者设置场景，而不是另建一套。" % entry_name
		)
		assert_true(
			entry_text.contains("ShowRunFeatures = false"),
			"%s属于局外，必须关掉局内专属功能，只留「获得金币」。" % entry_name
		)

	var main_text: String = FileAccess.get_file_as_string(MAIN_SCENE_PATH)
	assert_false(main_text.is_empty(), "必须能读到局内主场景。")
	assert_true(
		main_text.contains(DEV_SETTINGS_SCENE_PATH),
		"局内主场景必须仍然挂着开发者设置面板。"
	)
	assert_false(
		main_text.contains("ShowRunFeatures = false"),
		"局内必须保留全套功能，不得跟着局外一起关掉。"
	)


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


## 验证面板被「摘下来再挂回去」后能自行恢复时间系统订阅与显示同步。
##
## 主菜单与仓库由 SceneManager 缓存复用，场景切换走的正是这条 remove_child → add_child
## 路径：_ready 不会重跑，而 _exit_tree 已经把 _time_system 置空。若不在这里恢复，
## 「下一天」「行动值消耗」会在第二次进入同一个缓存实例时静默失效且不报任何错。
## 返回值：无。
func test_panel_restores_time_system_subscription_after_being_readded() -> void:
	var scene_tree := Engine.get_main_loop() as SceneTree
	var time_system := _install_fake_time_system(scene_tree)
	if time_system == null:
		return
	var ui := _new_dev_settings_ui(scene_tree)
	var callback := Callable(ui, "_on_time_changed")
	var day_label := ui.get_node("%DayLabel") as Label
	var cost_spin_box := ui.get_node("%CostSpinBox") as SpinBox

	assert_true(time_system.is_connected(&"TimeChanged", callback), "首次进入必须订阅 TimeChanged。")

	# 模拟 SceneManager 的缓存切换：只摘不释放，再原样挂回。
	# 不在这里手动置空 _time_system：那正是 _exit_tree 的职责，交给它做才算真的验证了恢复。
	scene_tree.root.remove_child(ui)
	scene_tree.root.add_child(ui)

	assert_true(
		time_system.is_connected(&"TimeChanged", callback),
		"重新挂回后必须恢复订阅，否则缓存复用的入口会静默失效。"
	)
	assert_eq(day_label.text, "当前天数：1", "重新挂回后必须重新同步一次天数显示。")
	assert_eq(int(cost_spin_box.value), 10, "重新挂回后必须重新回填行动值消耗。")

	# 恢复必须是双向的：挂回后再推进时间，显示仍要跟着走。
	time_system.call("PassTime", 240)
	assert_eq(day_label.text, "当前天数：2", "重新挂回后 TimeChanged 必须仍然刷新天数标签。")

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


## 安装伪等级系统到测试根节点。
##
## 与伪 TimeSystem 同理：编辑器测试根节点不应已有 PlayerLevel；若已存在则直接失败，
## 避免覆盖真实 Autoload 而让断言失去意义。
##
## 参数 scene_tree：当前测试的主循环。
## 返回值：已进入场景树的伪等级系统；前置条件不满足时返回 null。
func _install_fake_player_level(scene_tree: SceneTree) -> Node:
	var existing := scene_tree.root.get_node_or_null("PlayerLevel")
	assert_eq(existing, null, "编辑器测试根节点不应已有 PlayerLevel，以免覆盖真实 Autoload。")
	if existing != null:
		return null

	var player_level := FakePlayerLevel.new()
	player_level.name = "PlayerLevel"
	scene_tree.root.add_child(player_level)
	return player_level


## 安装伪钱包到测试根节点。
##
## 与伪 TimeSystem 同理：编辑器测试根节点不应已有 PlayerWallet；若已存在则直接失败，
## 避免覆盖真实 Autoload 而让断言失去意义。
##
## 参数 scene_tree：当前测试的主循环。
## 返回值：已进入场景树的伪钱包；前置条件不满足时返回 null。
func _install_fake_wallet(scene_tree: SceneTree) -> Node:
	var existing := scene_tree.root.get_node_or_null("PlayerWallet")
	assert_eq(existing, null, "编辑器测试根节点不应已有 PlayerWallet，以免覆盖真实 Autoload。")
	if existing != null:
		return null

	var wallet := FakeWallet.new()
	wallet.name = "PlayerWallet"
	scene_tree.root.add_child(wallet)
	return wallet


## 在场景文件全文里定位某个节点的声明行。
## 参数 scene_text：场景文件全文。
## 参数 node_name：节点名。
## 返回值：匹配到的声明行；未找到时返回空字符串。
func _find_node_declaration(scene_text: String, node_name: String) -> String:
	var marker: String = "[node name=\"%s\" type=" % node_name
	for raw_line: String in scene_text.split("\n"):
		if raw_line.begins_with(marker):
			return raw_line

	return ""


## 用最小节点树构造面板，避免复刻整棵场景层级。
##
## 必须在进树之前就设好 ShowRunFeatures：面板在 _ready 里按它决定整组局内控件的可见性，
## 进树之后再改只会得到一个已经定型的显示状态，断言就失去意义。
##
## 参数 scene_tree：当前测试的主循环。
## 参数 show_run_features：是否显示局内专属功能；默认 true，即局内模式。
## 返回值：已进入场景树并完成初始同步的面板。
func _new_dev_settings_ui(scene_tree: SceneTree, show_run_features: bool = true) -> Control:
	var ui := DEV_SETTINGS_UI_SCRIPT.new() as Control
	ui.name = "DevSettingsUIContractProbe"
	ui.set("ShowRunFeatures", show_run_features)
	_add_unique_child(ui, "CostRow", HBoxContainer.new())
	_add_unique_child(ui, "DayLabel", Label.new())
	_add_unique_child(ui, "CostSpinBox", SpinBox.new())
	_add_unique_child(ui, "NextDayButton", Button.new())
	_add_unique_child(ui, "LevelUpButton", Button.new())
	_add_unique_child(ui, "ResetCostButton", Button.new())
	_add_unique_child(ui, "CloseButton", Button.new())
	_add_unique_child(ui, "GoldSpinBox", SpinBox.new())
	_add_unique_child(ui, "GainGoldButton", Button.new())
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


## 释放测试期间创建的面板、伪 TimeSystem、伪等级系统与伪钱包。
## 参数 scene_tree：当前测试的主循环。
## 参数 ui：本用例创建的面板；可为 null。
## 参数 time_system：本用例创建的伪 TimeSystem；只想释放面板时传 null。
## 参数 player_level：本用例创建的伪等级系统；未安装时传 null。
## 参数 player_wallet：本用例创建的伪钱包；未安装时传 null。
## 返回值：无。
func _dispose(
	scene_tree: SceneTree,
	ui: Control,
	time_system: Node,
	player_level: Node = null,
	player_wallet: Node = null
) -> void:
	if is_instance_valid(ui):
		if ui.get_parent() != null:
			scene_tree.root.remove_child(ui)
		ui.free()
	if is_instance_valid(time_system):
		if time_system.get_parent() != null:
			scene_tree.root.remove_child(time_system)
		time_system.free()
	if is_instance_valid(player_level):
		if player_level.get_parent() != null:
			scene_tree.root.remove_child(player_level)
		player_level.free()
	if is_instance_valid(player_wallet):
		if player_wallet.get_parent() != null:
			scene_tree.root.remove_child(player_wallet)
		player_wallet.free()
