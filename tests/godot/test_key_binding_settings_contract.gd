@tool
extends McpTestSuite

## 按键绑定设置的契约套件。
##
## 这套契约守住的是一条最容易悄悄退化的链路：`project.godot` 注册了动作 → 注册表把它
## 列进面板 → 玩家改键写进 `user://settings.cfg` → 下次启动按记录还原。任何一环断掉，
## 表现都是「游戏里能按、设置里改不了」或者「改完重启就没了」，而界面本身看起来仍然
## 正常，所以必须由测试锁住。
##
## 编辑器进程不会载入 `project.godot` 的输入映射（所有项目动作的 `loaded_in_input_map`
## 都是 false），也不会创建 autoload，因此这里分两层验证：
##   ① 配置与场景结构用 `project.godot` / `.tscn` 文本加节点实例断言；
##   ② 编解码、冲突判定、落盘与还原用注册表与 KeyBindingManager 的独立实例驱动，
##      并为需要 InputMap 的用例自建夹具动作，用完精确回收。
## 真实按键在游戏里是否生效，由运行中游戏进程的 `game_eval` 负责。

## 项目配置文件路径，动作清单的唯一来源。
const PROJECT_CONFIG_PATH: String = "res://project.godot"

## 按键绑定注册表脚本路径。
const REGISTRY_PATH: String = "res://core/input/key_binding_registry.gd"

## 按键绑定管理器脚本路径。
const MANAGER_PATH: String = "res://core/input/key_binding_manager.gd"

## 参数设置面板场景路径。
const OPTION_PANEL_SCENE_PATH: String = "res://scenes/ui_scenes/option_panel.tscn"

## 参数设置面板脚本路径。
const OPTION_PANEL_SCRIPT_PATH: String = "res://scripts/ui_scripts/UIOptionPanel.gd"

## 按键绑定行场景路径。
const ROW_SCENE_PATH: String = "res://scenes/ui_scenes/key_binding_row.tscn"

## 按键绑定行脚本路径。
const ROW_SCRIPT_PATH: String = "res://scripts/ui_scripts/key_binding_row.gd"

## 登录菜单控制器路径。
##
## 开始界面的确认键在这里处理，它是 `check` 唯一的真实消费方。
const LOGIN_MENU_CONTROLLER_PATH: String = "res://core/ui/login_menu_controller.gd"

## 面板必须暴露的唯一名节点。
##
## 唯一名被摘掉时脚本的 `@onready` 引用会在真实游戏里变成 null，而场景本身仍然能正常
## 加载——这正是必须在这里锁住的原因。
const REQUIRED_PANEL_UNIQUE_NAMES: Array[String] = [
	"KeyBindingCategoryButton",
	"KeyBindingSettings",
	"BindingList",
	"BindingFeedbackLabel",
	"ResetAllBindingsButton",
]

## 面板脚本里必须保留的按键接线语句。
##
## 非 @tool 脚本在编辑器进程里不会执行 `_ready`，因此接线只能用源码锁定。
const REQUIRED_PANEL_WIRING: Array[String] = [
	"_key_binding_category_button.pressed.connect(_on_key_binding_category_pressed)",
	"_reset_all_bindings_button.pressed.connect(_on_reset_all_bindings_pressed)",
	"KEY_BINDING_ROW_SCENE.instantiate()",
	'row.connect(&"rebind_requested", _on_binding_rebind_requested)',
	'row.connect(&"reset_requested", _on_binding_reset_requested)',
	'_key_binding_manager.call("rebind", action, event)',
	'_key_binding_manager.call("reset_action_to_default", action)',
	'_key_binding_manager.call("reset_all_to_defaults")',
	'_key_binding_manager.call("get_conflicting_actions")',
]

## 行场景必须暴露的唯一名节点。
const REQUIRED_ROW_UNIQUE_NAMES: Array[String] = ["ActionName", "Note", "KeyButton", "ResetButton"]

## 管理器必须保留的公开入口。
const REQUIRED_MANAGER_METHODS: Array[String] = [
	"func capture_project_defaults",
	"func apply_saved_bindings",
	"func get_binding_event",
	"func get_default_event",
	"func is_default_binding",
	"func get_conflicting_actions",
	"func rebind",
	"func reset_action_to_default",
	"func reset_all_to_defaults",
]


## 记录写入内容的内存设置服务，用来在编辑器进程里替代 SettingsManager。
##
## 编辑器进程没有 autoload，而键位偏好的落盘路径必须被验证，因此这里用一个签名与
## `core/autoloads/SettingsManager.gd` 完全一致的替身：只有依赖接口而不是具体实现，
## 这段逻辑才可能在没有 autoload 的环境里被验证。
class FakeSettingsSource:
	extends RefCounted

	## 已写入的设置，键为 "section/key"。
	var stored: Dictionary = {}
	## 是否模拟磁盘写入失败。
	var fail_writes: bool = false
	## 是否收到过 get_setting 调用。
	var last_default_received: bool = false
	## 最近一次 get_setting 收到的默认值。
	##
	## 专门记录下来用于证明调用方没有传 null：ConfigFile.get_value 的默认值为 null 时
	## 会打印 C++ 错误（"no default was given"），把首次运行变成启动报错。
	var last_default: Variant = null


	func get_setting(section: String, key: String, default_value: Variant) -> Variant:
		last_default_received = true
		last_default = default_value
		return stored.get("%s/%s" % [section, key], default_value)


	func set_setting(section: String, key: String, value: Variant) -> bool:
		if fail_writes:
			return false
		stored["%s/%s" % [section, key]] = value
		return true


	func erase_setting(section: String, key: String) -> bool:
		stored.erase("%s/%s" % [section, key])
		return true


## 本次用例使用的注册表脚本。
var _registry_script: GDScript = null

## 本次用例使用的管理器脚本。
var _manager_script: GDScript = null


## 返回 GodotAI 使用的稳定套件名称。
## 返回值：按键绑定契约套件名。
func suite_name() -> String:
	return "key_binding_settings_contract"


## 每个用例前以磁盘版本重新加载被测脚本。
##
## 编辑器长会话会保留 preload 的旧编译结果，脚本改完立刻重跑会读到上一版并产生假失败；
## 这里强制替换缓存，保证测的始终是磁盘上的那一份。
## 返回值：无。
func setup() -> void:
	_registry_script = ResourceLoader.load(
		REGISTRY_PATH, "GDScript", ResourceLoader.CACHE_MODE_REPLACE
	) as GDScript
	_manager_script = ResourceLoader.load(
		MANAGER_PATH, "GDScript", ResourceLoader.CACHE_MODE_REPLACE
	) as GDScript


## 注册表与 project.godot 的动作集合必须双向相等。
##
## 这是整套契约的地基：注册表少了动作，玩家就改不了那个键；注册表多了动作，面板会列出
## 一个 InputMap 里根本不存在的行。两个方向都要卡住，因此这里断言的是集合相等而不是包含。
## 返回值：无。
func test_registry_and_project_actions_match_exactly() -> void:
	var project_actions: Array[String] = _project_input_action_names()
	assert_gt(project_actions.size(), 0, "必须能从 project.godot 解析出输入动作。")

	var registry_actions: Array[String] = []
	for value: Variant in _registry_script.call("get_action_names"):
		registry_actions.append(String(value))

	for action: String in project_actions:
		assert_true(
			registry_actions.has(action),
			"project.godot 注册的动作 %s 必须出现在可重绑清单里，否则玩家改不了它。" % action
		)
	for action: String in registry_actions:
		assert_true(
			project_actions.has(action),
			"可重绑清单里的 %s 必须在 project.godot 中真实注册。" % action
		)

	assert_eq(
		registry_actions.size(),
		project_actions.size(),
		"两个动作集合的大小必须一致，多一个少一个都说明清单和配置脱节了。"
	)

	# 面板文案会直接展示给玩家，必须与真实行为一致。
	#
	# `check` 曾经被写成「检查 / 当前版本未使用」，但它的默认键位 Enter 在开始界面是确认键，
	# 这样标注等于告诉玩家这个键没用。这里把「每个动作都有显示名」和「不得出现未使用字样」
	# 钉死，避免同类误导文案再写回来。
	for entry: Variant in _registry_script.call("get_rebindable_actions"):
		var record: Dictionary = entry as Dictionary
		var action_name: String = String(record.get("action", ""))
		assert_false(
			String(record.get("display", "")).is_empty(),
			"动作 %s 必须有面向玩家的显示名。" % action_name
		)
		assert_false(
			String(record.get("note", "")).contains("未使用"),
			"动作 %s 的说明不得标注为「未使用」；键位有真实用途时必须写清用途。" % action_name
		)

	var check_note: String = String(
		_registry_script.call("get_note", &"check")
	)
	assert_true(
		check_note.is_empty(),
		"`check` 的说明文案已按需求移除，不得再写回来。"
	)


## 开始界面的确认必须走项目动作 `check`，不能走引擎内置的 `ui_accept`。
##
## 这条契约同时钉住「读哪个动作」和「在哪一层读」。原生 `Button` 在 `_gui_input` 阶段就会用
## `ui_accept` 触发 `pressed`，而 `_gui_input` 排在 `_unhandled_input` 之前——所以只在
## `_unhandled_input` 里改读 `check` 是不够的：改键后按新键会确认，按旧键（回车/空格）也会
## 确认，等于没改。必须用 `_input` 抢在 `_gui_input` 之前把 `ui_accept` 吞掉。
##
## 返回值：无。
func test_login_menu_confirm_uses_the_rebindable_action() -> void:
	var source: String = FileAccess.get_file_as_string(LOGIN_MENU_CONTROLLER_PATH)
	assert_false(source.is_empty(), "必须能读到登录菜单控制器。")

	assert_true(
		source.contains("func _input(event: InputEvent) -> void:"),
		"确认必须放在 _input 里：_unhandled_input 排在 _gui_input 之后，抢不过原生 Button。"
	)
	assert_false(
		source.contains("func _unhandled_input("),
		"控制器不应再保留 _unhandled_input，否则按键处理会分散在两处。"
	)
	assert_true(
		source.contains("is_action_pressed(CONFIRM_ACTION)"),
		"确认必须读项目动作常量 CONFIRM_ACTION，才能跟着玩家改键走。"
	)
	assert_true(
		source.contains('const CONFIRM_ACTION: StringName = &"check"'),
		"CONFIRM_ACTION 必须指向 project.godot 里真实注册的 check。"
	)
	assert_true(
		source.contains('is_action_pressed(&"ui_accept")'),
		"必须吞掉内置 ui_accept，否则原生 Button 会绕过 check 继续确认。"
	)


## 被改过的动作必须能在行内单独恢复默认。
##
## 契约分三层：行提供按钮与信号、面板把信号接到管理器、管理器真的能还原并清掉记录。
## 只锁其中一层都不够——少了信号接线，按钮点了没反应；少了记录清理，重启后旧键位会回来。
##
## 返回值：无。
func test_single_action_reset_contract() -> void:
	var row_source: String = FileAccess.get_file_as_string(ROW_SCRIPT_PATH)
	assert_true(
		row_source.contains("signal reset_requested(action: StringName)"),
		"行必须提供 reset_requested 信号。"
	)
	assert_true(
		row_source.contains("reset_requested.emit(_action)"),
		"「恢复默认」按钮必须发出本行的动作名。"
	)
	assert_true(
		row_source.contains("_reset_button.disabled = is_default"),
		"默认键位时必须禁用「恢复默认」按钮，否则会给出一个点了没反应的入口。"
	)

	var panel_source: String = FileAccess.get_file_as_string(OPTION_PANEL_SCRIPT_PATH)
	assert_true(
		panel_source.contains('row.connect(&"reset_requested", _on_binding_reset_requested)'),
		"面板必须把行信号接到单行恢复默认的处理函数。"
	)

	# 管理器必须真的还原并清掉已保存记录：只还原 InputMap 的话重启后旧键位会回来。
	var manager_source: String = FileAccess.get_file_as_string(MANAGER_PATH)
	var erase_call: String = 'KEY_BINDING_REGISTRY.call("erase_saved_event", _settings_source, action)'
	assert_true(
		manager_source.contains(erase_call),
		"单行恢复默认必须同时清除该动作已保存的键位记录。"
	)

	# 行场景必须真的有这个按钮，否则脚本的 %ResetButton 在真实游戏里会拿到 null。
	var row_scene_text: String = FileAccess.get_file_as_string(ROW_SCENE_PATH)
	assert_true(
		_find_node_block(row_scene_text, "ResetButton").contains("text = \"恢复默认\""),
		"行场景里的恢复按钮文案必须是「恢复默认」。"
	)


## 参数设置面板必须暴露按键分类的全部控件，且按键分类初始隐藏。
##
## 断言唯一名而不是只断言节点存在：脚本用 `%Name` 解析控件，节点在但唯一名被摘掉时
## 真实游戏里会直接拿到 null。
## 返回值：无。
func test_option_panel_exposes_the_key_binding_category() -> void:
	var scene_text: String = FileAccess.get_file_as_string(OPTION_PANEL_SCENE_PATH)
	assert_false(scene_text.is_empty(), "必须能读到参数设置面板场景。")

	for node_name: String in REQUIRED_PANEL_UNIQUE_NAMES:
		assert_true(
			_find_node_block(scene_text, node_name).contains("unique_name_in_owner = true"),
			"%s 必须开启唯一名，脚本才能用 %%%s 解析。" % [node_name, node_name]
		)

	# 分类按钮必须排在既有分类之后：声明顺序就是左侧分类栏的显示顺序。
	assert_gt(
		scene_text.find('[node name="KeyBindingCategoryButton"'),
		scene_text.find('[node name="InventoryCategoryButton"'),
		"「按键」分类必须排在「背包」之后。"
	)

	var option_scene: PackedScene = load(OPTION_PANEL_SCENE_PATH) as PackedScene
	var panel: Control = track(option_scene.instantiate()) as Control
	assert_true(panel.get_node_or_null("%KeyBindingCategoryButton") is Button, "分类按钮必须是 Button。")
	assert_true(panel.get_node_or_null("%KeyBindingSettings") is Control, "按键设置容器必须是 Control。")
	assert_true(panel.get_node_or_null("%BindingList") is VBoxContainer, "绑定列表必须是 VBoxContainer。")
	assert_true(panel.get_node_or_null("%BindingFeedbackLabel") is Label, "提示文案必须是 Label。")
	assert_true(panel.get_node_or_null("%ResetAllBindingsButton") is Button, "恢复默认必须是 Button。")

	var category_button: Button = panel.get_node("%KeyBindingCategoryButton") as Button
	var settings_container: Control = panel.get_node("%KeyBindingSettings") as Control
	var reset_button: Button = panel.get_node("%ResetAllBindingsButton") as Button
	assert_eq(category_button.text, "按键", "分类按钮文案必须是「按键」。")
	assert_eq(reset_button.text, "全部恢复默认", "恢复默认按钮文案必须是「全部恢复默认」。")
	assert_false(settings_container.visible, "按键分类初始必须隐藏，打开面板时默认停在「地图」。")

	# 10 行绑定加上分组标题和说明文案，面板高度不足会把内容压出可视区。
	var panel_container: Control = panel.get_node("Center/Panel") as Control
	assert_true(
		panel_container.custom_minimum_size.y >= 560.0,
		"面板最小高度必须容得下 10 行绑定，当前为 %s。" % panel_container.custom_minimum_size.y
	)

	# 按键分类只保留关键文本：分类标题与两个恢复入口，不再有操作说明段落。
	var description_path: String = "Center/Panel/Margin/RootVBox/Body/KeyBindingSettings/Description"
	assert_true(
		panel.get_node_or_null(description_path) == null,
		"按键分类不得再保留说明段落，操作方式由界面本身表达。"
	)
	var section_title: Label = panel.get_node(
		"Center/Panel/Margin/RootVBox/Body/KeyBindingSettings/SectionTitle"
	) as Label
	assert_eq(section_title.text, "按键绑定", "按键分类标题必须是「按键绑定」。")


## 面板脚本必须按注册表构建绑定行，并把改键与恢复默认交给管理器。
##
## 这几条接线决定了「点按钮没反应」「改完不保存」「同键不标红」这三类故障不会悄悄溜过去。
## 返回值：无。
func test_option_panel_script_wires_rows_to_the_manager() -> void:
	var source: String = FileAccess.get_file_as_string(OPTION_PANEL_SCRIPT_PATH)
	assert_false(source.is_empty(), "必须能读到参数设置面板脚本。")

	for wiring: String in REQUIRED_PANEL_WIRING:
		assert_true(source.contains(wiring), "面板脚本必须保留接线：%s" % wiring)

	assert_true(
		source.contains("get_rebindable_actions"),
		"绑定行必须来自注册表清单，面板不得硬编码动作名。"
	)
	assert_true(
		source.contains("_cancel_binding_listening()"),
		"切换分类与返回时必须取消等待按键，否则会留下一个吞掉全部键盘输入的行。"
	)

	# 冲突仍以红色键位表示，但不再附加说明文字；成功改键也不再回显。
	assert_false(
		source.contains("BINDING_CONFLICT_TEXT"),
		"冲突提示文案已按需求删除，不得再写回来。"
	)
	assert_false(
		source.contains("已把全部按键恢复为默认值"),
		"恢复默认不再回显成功文案，按钮与键位本身已经是结果。"
	)


## 按键绑定行场景必须暴露动作名、说明与键位按钮。
##
## 返回值：无。
func test_key_binding_row_scene_exposes_unique_names() -> void:
	var scene_text: String = FileAccess.get_file_as_string(ROW_SCENE_PATH)
	assert_false(scene_text.is_empty(), "必须能读到按键绑定行场景。")
	assert_true(scene_text.contains(ROW_SCRIPT_PATH), "行场景必须挂载按键绑定行脚本。")

	for node_name: String in REQUIRED_ROW_UNIQUE_NAMES:
		assert_true(
			_find_node_block(scene_text, node_name).contains("unique_name_in_owner = true"),
			"%s 必须开启唯一名，行脚本才能用 %%%s 解析。" % [node_name, node_name]
		)

	var row_source: String = FileAccess.get_file_as_string(ROW_SCRIPT_PATH)
	for node_name: String in REQUIRED_ROW_UNIQUE_NAMES:
		assert_true(row_source.contains("%%%s" % node_name), "行脚本必须通过 %%%s 引用控件。" % node_name)

	assert_true(
		row_source.contains("_is_cancel_key(key_event)"),
		"等待按键时必须能识别 ESC 并取消，而不是把 ESC 当成绑定目标。"
	)
	assert_true(
		row_source.contains("get_viewport().set_input_as_handled()"),
		"等待按键期间必须消费事件，否则按 ESC 会先弹出暂停菜单。"
	)
	assert_false(
		row_source.contains("ESC 取消"),
		"等待按键的按钮文案不得再附带操作提示，只保留「请按下新键」。"
	)
	# 「恢复默认」必须排在键位按钮之后：需求是按键被改过后在键位后面出现这个入口。
	assert_gt(
		scene_text.find('[node name="ResetButton"'),
		scene_text.find('[node name="KeyButton"'),
		"「恢复默认」按钮必须声明在键位按钮之后。"
	)

	var row_scene: PackedScene = load(ROW_SCENE_PATH) as PackedScene
	var row: Control = track(row_scene.instantiate()) as Control
	assert_true(row.get_node_or_null("%ActionName") is Label, "动作名必须是 Label。")
	assert_true(row.get_node_or_null("%Note") is Label, "说明文案必须是 Label。")
	assert_true(row.get_node_or_null("%KeyButton") is Button, "键位必须是 Button。")
	assert_true(row.get_node_or_null("%ResetButton") is Button, "「恢复默认」必须是 Button。")

	# 说明列必须自动换行。
	#
	# 说明列拿到的是「行宽减去动作名与键位按钮后的剩余空间」，实测只有 160px；不开自动换行
	# 时 Label 的最小宽度等于整段文字宽度，一条长说明会把整行最小宽度顶到 712px，面板被撑到
	# 925px 高。这里钉住换行开关，避免以后再加长说明时重演。
	var note_label: Label = row.get_node_or_null("%Note") as Label
	assert_true(note_label != null, "行场景必须能实例化出说明 Label。")
	assert_eq(note_label.autowrap_mode, TextServer.AUTOWRAP_WORD_SMART, "说明文案必须自动换行。")


## 键位编解码必须能往返，并且拒绝一切非法记录。
##
## 拒绝比接受更重要：玩家手改坏 `user://settings.cfg` 时，只有解析失败才会退化成
## 「键位回到默认」，否则会把一个空绑定写进 InputMap，表现为某个动作彻底失效。
## 返回值：无。
func test_event_codec_round_trips_and_rejects_invalid_records() -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_S
	event.ctrl_pressed = true

	var encoded: Dictionary = _registry_script.call("encode_event", event)
	assert_eq(int(encoded.get("physical_keycode", 0)), KEY_S, "编码必须保留物理键码。")
	assert_true(bool(encoded.get("ctrl", false)), "编码必须保留修饰键。")

	var decoded: InputEventKey = _registry_script.call("decode_event", encoded)
	assert_true(decoded != null, "合法记录必须能还原。")
	assert_eq(decoded.physical_keycode, KEY_S, "还原后物理键码必须一致。")
	assert_true(decoded.ctrl_pressed, "还原后修饰键必须一致。")
	assert_false(decoded.pressed, "InputMap 存的是匹配模板，还原后不得带按下标记。")
	assert_eq(
		String(_registry_script.call("format_event_text", decoded)), "Ctrl+S", "键位文案必须带修饰键前缀。"
	)

	# 非法记录必须一律被拒绝，而不是被勉强解释成某个键。
	var invalid_records: Array = [
		"不是字典",
		{},
		{"physical_keycode": 0, "keycode": 0},
		{"physical_keycode": -1},
		{"physical_keycode": "83"},
		{"physical_keycode": true},
		{"physical_keycode": KEY_S, "ctrl": "yes"},
	]
	for record: Variant in invalid_records:
		assert_true(
			_registry_script.call("decode_event", record) == null,
			"非法记录必须解析失败并回退默认键位：%s" % str(record)
		)

	# 纯修饰键与键盘重复事件都不能作为绑定目标。
	var modifier_only := InputEventKey.new()
	modifier_only.shift_pressed = true
	assert_true(
		(_registry_script.call("encode_event", modifier_only) as Dictionary).is_empty(),
		"只按下修饰键不能作为绑定目标。"
	)
	var echo_event := InputEventKey.new()
	echo_event.physical_keycode = KEY_S
	echo_event.echo = true
	assert_true(
		(_registry_script.call("encode_event", echo_event) as Dictionary).is_empty(),
		"键盘重复事件不能作为绑定目标。"
	)
	assert_true(
		(_registry_script.call("encode_event", InputEventJoypadButton.new()) as Dictionary).is_empty(),
		"非键盘事件不能作为绑定目标。"
	)
	assert_eq(
		String(_registry_script.call("format_event_text", null)),
		String(_registry_script.get("UNBOUND_TEXT")),
		"没有键位时必须显示「未绑定」而不是空字符串。"
	)


## 已保存键位必须能读回，损坏或缺失时必须退化为项目默认。
##
## 返回值：无。
func test_saved_binding_reads_back_and_degrades_on_corruption() -> void:
	var settings := FakeSettingsSource.new()

	assert_true(
		_registry_script.call("read_saved_event", settings, &"move_up") == null,
		"没有保存记录时必须返回 null，让调用方使用项目默认键位。"
	)
	assert_true(settings.last_default_received, "读取键位必须走设置服务，而不是自己去读文件。")
	assert_true(
		settings.last_default != null,
		"读取键位的默认值不能是 null，否则 ConfigFile 会打印 C++ 错误，把首次运行变成启动报错。"
	)

	var event := InputEventKey.new()
	event.physical_keycode = KEY_UP
	assert_true(
		bool(_registry_script.call("write_saved_event", settings, &"move_up", event)),
		"合法键位必须能写入设置服务。"
	)
	var restored: InputEventKey = _registry_script.call("read_saved_event", settings, &"move_up")
	assert_true(restored != null, "写入后的键位必须能读回。")
	assert_eq(restored.physical_keycode, KEY_UP, "读回的物理键码必须与写入一致。")

	# 记录损坏时必须退化为默认键位，而不是让游戏启动报错。
	#
	# 这里刻意覆盖两种坏法：字典里字段类型不对，以及整条记录根本不是字典。后者曾经让
	# `read_saved_event` 在 `==` 两侧类型不同时直接抛错，把「手改坏配置」升级成启动崩溃。
	for corrupt_record: Variant in [{"physical_keycode": "坏了"}, "完全不是字典", 12345]:
		settings.stored["input/move_up"] = corrupt_record
		assert_true(
			_registry_script.call("read_saved_event", settings, &"move_up") == null,
			"损坏的记录必须解析失败并回退默认键位：%s" % str(corrupt_record)
		)

	settings.stored.erase("input/move_up")
	assert_true(
		bool(_registry_script.call("erase_saved_event", settings, &"move_up")),
		"删除一个不存在的键位也必须视为成功。"
	)

	# 设置服务缺失时不得报错，只应退化为「没有持久化」。
	assert_true(
		_registry_script.call("read_saved_event", null, &"move_up") == null,
		"没有设置服务时必须安全退化。"
	)
	assert_false(
		bool(_registry_script.call("write_saved_event", null, &"move_up", event)),
		"没有设置服务时写入必须返回失败，让界面提示玩家。"
	)


## 改键只能替换键盘事件，并把同键事实报告出来；恢复默认必须回到快照。
##
## 「只替换键盘事件」这条尤其重要：动作上将来补了手柄绑定，玩家改一次键盘不能把它们
## 一起清掉。这里用带手柄事件的夹具动作证明它没有被误删。
## 返回值：无。
func test_rebind_preserves_other_event_types_and_reports_conflicts() -> void:
	var fixtures: Dictionary = _ensure_input_map_fixtures()
	var settings := FakeSettingsSource.new()
	var manager: Node = track(_manager_script.new()) as Node
	manager.call("set_settings_source", settings)

	# 手柄事件必须在抓取默认快照之前挂上：快照是「恢复默认」的唯一依据，先挂后抓才能
	# 同时验证「改键不误删非键盘事件」和「恢复默认把非键盘事件一起还原」两件事。
	var joypad_event := InputEventJoypadButton.new()
	joypad_event.button_index = JOY_BUTTON_A
	InputMap.action_add_event(&"move_up", joypad_event)
	manager.call("capture_project_defaults")

	var default_up: InputEventKey = manager.call("get_default_event", &"move_up")
	assert_true(default_up != null, "必须能取到 move_up 的默认键位快照。")

	var events_before: int = InputMap.action_get_events(&"move_up").size()

	var new_event := InputEventKey.new()
	new_event.physical_keycode = KEY_UP
	var result: Dictionary = manager.call("rebind", &"move_up", new_event)
	assert_true(bool(result.get("ok", false)), "合法改键必须成功：%s" % str(result.get("reason", "")))
	assert_true(bool(result.get("saved", false)), "改键必须写入设置服务。")

	var applied: InputEventKey = manager.call("get_binding_event", &"move_up")
	assert_eq(applied.physical_keycode, KEY_UP, "改键后必须立即生效。")
	assert_eq(
		InputMap.action_get_events(&"move_up").size(),
		events_before,
		"改键只能替换键盘事件，不能顺手删掉手柄事件。"
	)
	assert_true(
		_has_joypad_button(&"move_up", JOY_BUTTON_A),
		"手柄事件必须在改键后仍然存在。"
	)

	# 允许两个动作同键，但必须能被查询出来供界面标红。
	var second: Dictionary = manager.call("rebind", &"move_down", new_event)
	assert_true(bool(second.get("ok", false)), "允许把两个动作绑到同一个键。")
	var conflicts: Array = manager.call("get_conflicting_actions")
	assert_true(conflicts.has(&"move_up"), "同键的 move_up 必须出现在冲突清单里。")
	assert_true(conflicts.has(&"move_down"), "同键的 move_down 必须出现在冲突清单里。")

	# 恢复默认：InputMap 回到快照，已保存的偏好必须被清干净。
	manager.call("reset_all_to_defaults")
	var restored: InputEventKey = manager.call("get_binding_event", &"move_up")
	assert_eq(
		restored.physical_keycode,
		default_up.physical_keycode,
		"恢复默认后 move_up 必须回到项目默认键位。"
	)
	assert_false(
		settings.stored.has("input/move_up"),
		"恢复默认必须删除已保存的键位记录，否则下次启动又会读回玩家设定。"
	)
	assert_true(
		_has_joypad_button(&"move_up", JOY_BUTTON_A),
		"恢复默认必须整组还原快照，连同手柄事件一起回来。"
	)
	assert_true(
		(manager.call("get_conflicting_actions") as Array).is_empty(),
		"恢复默认后不应再有同键动作。"
	)

	_remove_input_map_fixtures(fixtures)


## 单个动作恢复默认必须只影响该动作，并如实报告「是否已回到默认」。
##
## `is_default_binding` 是面板决定要不要显示「恢复默认」按钮的唯一依据：它一旦恒真，按钮
## 永远不出现，玩家就再也没有单行恢复的入口；它一旦恒假，按钮常驻，玩家又看不出哪些被改过。
## 返回值：无。
func test_single_action_reset_only_touches_that_action() -> void:
	var fixtures: Dictionary = _ensure_input_map_fixtures()
	var settings := FakeSettingsSource.new()
	var manager: Node = track(_manager_script.new()) as Node
	manager.call("set_settings_source", settings)
	manager.call("capture_project_defaults")

	assert_true(
		bool(manager.call("is_default_binding", &"move_up")),
		"刚抓完快照、还没改键时必须报告为默认键位。"
	)

	# 改两个动作，随后只恢复其中一个。
	var up_event := InputEventKey.new()
	up_event.physical_keycode = KEY_UP
	var down_event := InputEventKey.new()
	down_event.physical_keycode = KEY_DOWN
	manager.call("rebind", &"move_up", up_event)
	manager.call("rebind", &"move_down", down_event)
	assert_false(
		bool(manager.call("is_default_binding", &"move_up")),
		"改过键之后必须报告为非默认，否则「恢复默认」按钮不会出现。"
	)

	assert_true(
		bool(manager.call("reset_action_to_default", &"move_up")),
		"有默认快照的动作必须能单独恢复。"
	)
	assert_true(
		bool(manager.call("is_default_binding", &"move_up")),
		"恢复后必须重新报告为默认键位，按钮才会收回去。"
	)
	assert_false(
		settings.stored.has("input/move_up"),
		"单行恢复必须删除该动作已保存的记录，否则重启后旧键位会回来。"
	)

	# 另一个动作必须原封不动：单行恢复不能顺手把别的动作一起还原。
	assert_false(
		bool(manager.call("is_default_binding", &"move_down")),
		"单行恢复不得影响其它动作。"
	)
	var down_now: InputEventKey = manager.call("get_binding_event", &"move_down")
	assert_eq(down_now.physical_keycode, KEY_DOWN, "其它动作的键位必须保持玩家设定。")
	assert_true(
		settings.stored.has("input/move_down"),
		"其它动作已保存的记录不得被一起清掉。"
	)

	# 不在清单里的动作必须被拒绝，避免界面以外的地方把任意动作塞进来。
	assert_false(
		bool(manager.call("reset_action_to_default", &"ui_accept")),
		"不在可重绑清单里的动作必须拒绝恢复。"
	)

	_remove_input_map_fixtures(fixtures)


## 落盘失败时本次运行仍然生效，但必须如实报告没保存成功。
##
## 界面靠这个标记决定是否提示「重启后会丢失」；一旦它变成恒真，玩家就会在毫不知情的
## 情况下丢掉设置。
## 返回值：无。
func test_rebind_reports_save_failure_without_blocking_the_change() -> void:
	var fixtures: Dictionary = _ensure_input_map_fixtures()
	var settings := FakeSettingsSource.new()
	settings.fail_writes = true
	var manager: Node = track(_manager_script.new()) as Node
	manager.call("set_settings_source", settings)
	manager.call("capture_project_defaults")

	var new_event := InputEventKey.new()
	new_event.physical_keycode = KEY_H
	var result: Dictionary = manager.call("rebind", &"move_left", new_event)
	assert_true(bool(result.get("ok", false)), "落盘失败不应阻止本次运行生效。")
	assert_false(bool(result.get("saved", false)), "落盘失败必须如实报告 saved = false。")

	var applied: InputEventKey = manager.call("get_binding_event", &"move_left")
	assert_eq(applied.physical_keycode, KEY_H, "落盘失败时本次运行仍必须用新键位。")

	# 非可重绑动作必须被拒绝，避免界面以外的地方把任意动作塞进来。
	var rejected: Dictionary = manager.call("rebind", &"ui_accept", new_event)
	assert_false(bool(rejected.get("ok", false)), "不在清单里的动作必须被拒绝。")
	assert_false(String(rejected.get("reason", "")).is_empty(), "拒绝时必须给出可展示的原因。")

	_remove_input_map_fixtures(fixtures)


## 管理器必须在 SettingsManager 之后注册，并保留公开入口。
##
## 顺序决定了玩家偏好能否在启动时生效：SettingsManager 必须先完成 `settings.cfg` 的
## 读取，KeyBindingManager 才能把记录应用到 InputMap。
## 返回值：无。
func test_manager_is_registered_after_settings_manager() -> void:
	var config_text: String = FileAccess.get_file_as_string(PROJECT_CONFIG_PATH)
	var manager_index: int = config_text.find("KeyBindingManager=")
	var settings_index: int = config_text.find("SettingsManager=")
	assert_gt(manager_index, -1, "project.godot 必须注册 KeyBindingManager autoload。")
	assert_gt(settings_index, -1, "project.godot 必须保留 SettingsManager autoload。")
	assert_true(
		manager_index > settings_index,
		"KeyBindingManager 必须排在 SettingsManager 之后，否则启动时读不到玩家偏好。"
	)
	assert_true(
		config_text.contains("KeyBindingManager=\"*res://core/input/key_binding_manager.gd\""),
		"autoload 必须指向按键绑定管理器脚本。"
	)

	var source: String = FileAccess.get_file_as_string(MANAGER_PATH)
	for method_declaration: String in REQUIRED_MANAGER_METHODS:
		assert_true(source.contains(method_declaration), "管理器必须保留入口 %s。" % method_declaration)
	assert_true(source.contains("signal binding_changed"), "管理器必须广播单键变化。")
	assert_true(source.contains("signal bindings_reset"), "管理器必须广播全部恢复默认。")


## 从 project.godot 文本里解析 [input] 段注册的全部动作名。
##
## 只认「行首标识符 + ={」这种动作块开头，因此不会被块内的 "events"、"deadzone"
## 等字段或其它段落的同名文本干扰。
## 返回值：动作名列表，顺序与配置文件一致。
func _project_input_action_names() -> Array[String]:
	var names: Array[String] = []
	var in_input_section: bool = false
	for raw_line: String in FileAccess.get_file_as_string(PROJECT_CONFIG_PATH).split("\n"):
		var line: String = raw_line.strip_edges()
		if line.begins_with("[") and line.ends_with("]"):
			in_input_section = line == "[input]"
			continue
		if not in_input_section or not line.ends_with("={") or line.length() <= 2:
			continue
		names.append(line.substr(0, line.length() - 2))
	return names


## 在场景文本里截取某个节点的完整声明块。
## 参数 scene_text：场景文件全文。
## 参数 node_name：节点名。
## 返回值：从声明行到下一个节点声明之前的文本；未找到时返回空字符串。
func _find_node_block(scene_text: String, node_name: String) -> String:
	var start: int = scene_text.find('[node name="%s"' % node_name)
	if start < 0:
		return ""
	var end: int = scene_text.find("\n[node ", start + 1)
	if end < 0:
		return scene_text.substr(start)
	return scene_text.substr(start, end - start)


## 为全部可重绑动作准备 InputMap 夹具。
##
## 编辑器进程不载入项目输入映射，缺动作会让默认键位快照缺失、管理器刷出一串告警，
## 因此这里补齐；记录哪些动作是本次新建的，用例结束时精确回收，不污染编辑器输入。
## 返回值：动作名 → {added: bool, default_event: InputEventKey}。
func _ensure_input_map_fixtures() -> Dictionary:
	var fixtures: Dictionary = {}
	var names: Array = _registry_script.call("get_action_names")
	for index: int in names.size():
		var action: StringName = StringName(names[index])
		var added: bool = false
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			added = true
		var default_event: InputEventKey = _first_key_event(action)
		if default_event == null:
			default_event = InputEventKey.new()
			# 用功能键而不是字母键：功能键不会和 project.godot 里可能已存在的默认键位撞车。
			default_event.physical_keycode = KEY_F1 + index
			InputMap.action_add_event(action, default_event)
		fixtures[action] = {"added": added, "default_event": default_event}
	return fixtures


## 回收 _ensure_input_map_fixtures 新建的动作。
## 参数 fixtures：_ensure_input_map_fixtures 返回的字典。
## 返回值：无。
func _remove_input_map_fixtures(fixtures: Dictionary) -> void:
	for action: Variant in fixtures.keys():
		if bool((fixtures[action] as Dictionary).get("added", false)):
			InputMap.erase_action(StringName(action))


## 读取某个动作当前的第一个键盘事件。
## 参数 action：动作名。
## 返回值：键盘事件；动作不存在或没有键盘事件时返回 null。
func _first_key_event(action: StringName) -> InputEventKey:
	if not InputMap.has_action(action):
		return null
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventKey:
			return event as InputEventKey
	return null


## 判断某个动作是否绑定了指定手柄按键。
## 参数 action：动作名。
## 参数 button_index：手柄按键枚举值。
## 返回值：绑定了返回 true。
func _has_joypad_button(action: StringName, button_index: int) -> bool:
	if not InputMap.has_action(action):
		return false
	for event: InputEvent in InputMap.action_get_events(action):
		var joypad_event: InputEventJoypadButton = event as InputEventJoypadButton
		if joypad_event != null and joypad_event.button_index == button_index:
			return true
	return false
