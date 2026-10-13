@tool
extends McpTestSuite

## 交互飘字契约套件。
##
## 锁定四件事：飘字表现组件与全局服务按「零耦合 + 可降级」协议工作、棋盘卡与建筑两条交互路径
## 都把离散结果改由飘字播报、建筑的距离门禁与遮挡门禁已分离、新增 autoload 没有破坏
## SaveManager 必须排在首位的既有契约。
##
## 运行期效果不能由编辑器套件证明：非 @tool 生产脚本在编辑器中实例化后方法不可调用，
## 因此套件只锁定源码形状。真实效果（鼠标点击后飘字出现在目标处、样式与去重窗口、
## 暂停时仍会淡出并自释放）由 Main 场景冒烟阶段的 game_eval 实证。

## 飘字服务（autoload FloatingText）。
const SERVICE_GD: String = "res://core/autoloads/floating_text.gd"
## 单条飘字表现组件。
const LABEL_GD: String = "res://core/ui/feedback/floating_text_label.gd"
## 棋盘卡交互协调器。
const COORDINATOR_GD: String = "res://core/gameflow/world_interaction_coordinator.gd"
## 建筑输入协调器。
const BUILDING_GD: String = "res://core/building/building_controller.gd"
## 工程配置。
const PROJECT_GODOT: String = "res://project.godot"

## 服务注册行；必须与 project.godot 逐字一致。
const AUTOLOAD_ENTRY: String = 'FloatingText="*res://core/autoloads/floating_text.gd"'
## 两条交互路径共用的距离不足文案。
const OUT_OF_RANGE_TEXT: String = "距离不够！"


## 提供 GodotAI 使用的稳定套件名称。
##
## 必须覆写：McpTestSuite.suite_name() 默认返回 "unnamed"，
## 不覆写会让本套件以 unnamed 注册，test_run(suite=...) 永远找不到它。
##
## @return 套件名。
func suite_name() -> String:
	return "floating_text_contract"


## 验证飘字服务已注册为 autoload，且没有把 SaveManager 挤出首位。
##
## autoload_manage(op="add") 会按自己的内部顺序重写整个 [autoload] 段，把 SaveManager 挪到中间，
## 直接导致 test_save_system_contract 失败；因此这里把顺序本身也锁进契约。
##
## @return 无返回值。
func test_service_is_registered_autoload() -> void:
	var project: String = FileAccess.get_file_as_string(PROJECT_GODOT)

	assert_true(
		project.contains(AUTOLOAD_ENTRY),
		"飘字服务必须注册为 autoload，否则两条交互路径都会静默降级为无提示。"
	)

	var save_index: int = project.find('SaveManager="*res://core/save/save_manager.gd"')
	var floating_index: int = project.find(AUTOLOAD_ENTRY)
	assert_true(save_index >= 0, "工程必须保留 SaveManager autoload。")
	assert_true(
		save_index < floating_index,
		"新增 autoload 不得插到 SaveManager 之前，否则存档契约测试会失败。"
	)


## 验证飘字服务刻意不声明 class_name。
##
## autoload 已经提供全局名 FloatingText；再声明同名 class_name 会与之冲突，
## 表现为整个工程报「Class FloatingText hides an autoload singleton」。
##
## @return 无返回值。
func test_service_declares_no_class_name() -> void:
	var service: String = FileAccess.get_file_as_string(SERVICE_GD)

	# 不能用 contains("class_name")：脚本里讲解「刻意不声明 class_name」的注释也会命中，
	# 否定断言会被说明文本误伤。只看真正的声明行。
	assert_false(
		_has_declaration_line(service, "class_name"),
		"autoload 已提供全局名 FloatingText，服务不得再声明 class_name。"
	)


## 验证服务的公开入口与「坐标由服务自行读取」的解耦约定。
##
## @return 无返回值。
func test_service_api_shape() -> void:
	var service: String = FileAccess.get_file_as_string(SERVICE_GD)

	for literal: String in [
		"func show_at_target(target: CanvasItem, text: String,",
		"func show_at_world(world_position: Vector2, text: String,",
		"func clear_all() -> void:",
	]:
		assert_true(service.contains(literal), "飘字服务缺少公开入口：%s" % literal)

	# 交互目标（棋盘卡视图、建筑视图）不得为实现提示而新增任何接口。
	assert_true(
		service.contains("_resolve_target_screen_position(target)"),
		"目标坐标必须由服务自行换算，调用方不需要目标实现任何接口。"
	)
	assert_true(
		service.contains("target.get_screen_transform().origin"),
		"Node2D 目标必须用 get_screen_transform 换算屏幕坐标。"
	)


## 验证承载层级、字体与鼠标穿透。
##
## @return 无返回值。
func test_service_layer_font_and_mouse_passthrough() -> void:
	var service: String = FileAccess.get_file_as_string(SERVICE_GD)

	assert_true(
		service.contains("const CANVAS_LAYER: int = 10"),
		"飘字层号必须高于 UI/HUDLayer(2)，否则会被 HUD 面板遮住。"
	)
	assert_true(
		service.contains('preload("res://res/font/Uranus_Pixel_11Px.ttf")'),
		"飘字必须使用游戏字体，不得引入第二套字体来源。"
	)
	assert_true(
		service.contains("const OUTLINE_SIZE: int = 6"),
		"描边宽度必须显式定义。"
	)
	assert_true(
		service.contains("const OUTLINE_COLOR: Color = Color(0.0, 0.0, 0.0, 1.0)"),
		"描边必须是纯黑，才能在任意地形贴图上保证对比度。"
	)
	# 全屏 Control 宿主漏掉 IGNORE 会吞掉其下方所有输入，且不会有任何报错。
	assert_true(
		service.contains("_host.mouse_filter = Control.MOUSE_FILTER_IGNORE"),
		"全屏宿主必须忽略鼠标，否则会吞掉其下方所有输入。"
	)
	assert_true(
		service.contains("_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)"),
		"宿主必须铺满视口，飘字子节点的 position 才等于屏幕坐标。"
	)


## 验证单条飘字表现组件的主题覆盖与自释放协议。
##
## @return 无返回值。
func test_label_component_shape() -> void:
	var label: String = FileAccess.get_file_as_string(LABEL_GD)

	assert_true(label.contains("class_name FloatingTextLabel"), "表现组件必须提供 class_name 以便复用。")
	assert_true(label.contains("extends Label"), "表现组件必须是 Label 子类。")
	assert_true(label.contains("signal finished"), "表现组件必须在释放前广播 finished。")
	assert_true(
		label.contains("mouse_filter = Control.MOUSE_FILTER_IGNORE"),
		"飘字必须忽略鼠标，漏掉会静默吞掉输入。"
	)
	# Tween 默认跟随宿主节点的处理状态；暂停期间生成的飘字会永久停在屏幕上，既不淡出也不释放。
	assert_true(
		label.contains("process_mode = Node.PROCESS_MODE_ALWAYS"),
		"飘字必须在暂停时继续推进动画，否则会永久残留。"
	)
	# LabelSettings 会整体覆盖 theme_override 的颜色，使调用方传入的颜色失效。
	assert_false(
		label.contains("label_settings ="),
		"不得使用 LabelSettings，否则 theme_override 的正文颜色会失效。"
	)
	for literal: String in [
		'add_theme_font_override("font"',
		'add_theme_font_size_override("font_size"',
		'add_theme_color_override("font_color"',
		'add_theme_constant_override("outline_size"',
		'add_theme_color_override("font_outline_color"',
	]:
		assert_true(label.contains(literal), "表现组件缺少主题覆盖：%s" % literal)
	# 字号必须来自调用方：组件自带默认值会让工程出现第二处字体参数来源。
	assert_true(
		label.contains("font: Font, font_size: int,"),
		"字体与字号必须由调用方传入，组件不得自带默认值。"
	)


## 验证棋盘卡路径把「距离不足」接进飘字服务，且保持可降级。
##
## @return 无返回值。
func test_coordinator_wires_floating_text() -> void:
	var coordinator: String = FileAccess.get_file_as_string(COORDINATOR_GD)

	# test_run 环境没有 autoload，裸标识符会让脚本以「Identifier not found」解析失败。
	assert_true(
		coordinator.contains('const FLOATING_TEXT_PATH: NodePath = ^"/root/FloatingText"'),
		"协调器必须用 NodePath 解析飘字服务，裸 autoload 标识符会让脚本在无 autoload 环境下解析失败。"
	)
	assert_false(
		coordinator.contains("FloatingText."),
		"协调器不得直接引用 FloatingText 标识符。"
	)
	assert_true(
		coordinator.contains("_floating_text = get_node_or_null(FLOATING_TEXT_PATH)"),
		"协调器必须在 _ready 解析飘字服务。"
	)
	assert_true(
		coordinator.contains('const OUT_OF_RANGE_TEXT: String = "%s"' % OUT_OF_RANGE_TEXT),
		"距离不足文案必须集中定义。"
	)
	# 点击与长按共用 _report_out_of_range_interaction 这一个漏斗，因此只需接一次提示。
	assert_eq(
		_count_occurrences(coordinator, "_show_out_of_range_floating_text(card)"),
		1,
		"距离不足提示必须只从共用的漏斗函数里发起一次。"
	)
	assert_true(
		coordinator.contains("_floating_text.has_method(FLOATING_TEXT_SHOW_AT_TARGET)"),
		"必须用 has_method 做鸭子类型，服务缺失时静默降级。"
	)


## 验证建筑路径的八处离散提示已全部改由飘字播报，且实时状态提示仍留在底部标签。
##
## @return 无返回值。
func test_building_controller_migrates_discrete_feedback() -> void:
	var building: String = FileAccess.get_file_as_string(BUILDING_GD)

	assert_false(
		building.contains("FeedbackSeconds"),
		"离散结果已由飘字播报，不得残留底部提示倒计时。"
	)
	assert_false(building.contains("_show_feedback"), "不得残留旧的底部反馈助手。")
	assert_false(building.contains("var _feedback"), "不得残留反馈文本字段。")
	assert_false(
		building.contains("FloatingText."),
		"建筑控制器不得直接引用 FloatingText 标识符。"
	)
	assert_true(
		building.contains('const FLOATING_TEXT_PATH: NodePath = ^"/root/FloatingText"'),
		"建筑控制器必须用 NodePath 解析飘字服务。"
	)
	assert_true(
		building.contains('const OUT_OF_RANGE_TEXT: String = "%s"' % OUT_OF_RANGE_TEXT),
		"建筑与棋盘卡必须共用同一句距离不足文案。"
	)
	# 距离与遮挡必须分开判定，「距离不够」才不会被纯遮挡原因误触发。
	assert_true(
		building.contains("func _is_record_in_range(record: Dictionary) -> bool:"),
		"必须把距离判定从遮挡判定里拆出来。"
	)
	assert_true(
		building.contains("if not _is_record_in_range(record):"),
		"_is_record_reachable 必须复用距离判定，保持距离口径单一。"
	)
	# 服务的 message 同时承载成功（已放置/已拆除）与失败文案，不能一律用红色。
	assert_true(
		building.contains("func _result_text_color(result: Dictionary) -> Color:"),
		"必须按服务结果分色，否则成功提示会被显示成报错。"
	)
	# 实时状态（落点说明、拆除进行中、F 交互提示）必须继续走底部标签。
	assert_true(
		building.contains("_hint.text = _interaction_prompt(record)"),
		"底部实时状态提示必须保留。"
	)


## 判断文本中是否存在以关键字开头的声明行。
##
## 不能用 contains("class_name") 之类的朴素判定：脚本里讲解「不要声明 class_name」的注释同样会命中，
## 使否定断言被说明文本误伤（本工程已有同类先例，见 test_pause_menu_contract.gd）。
##
## @param text 被搜索的文本。
## @param keyword 声明关键字，例如 "class_name"。
## @return 存在以该关键字开头的声明行时为 true。
func _has_declaration_line(text: String, keyword: String) -> bool:
	for line: String in text.split("\n"):
		if line.strip_edges().begins_with(keyword):
			return true
	return false


## 统计文本中某个字面片段出现的次数。
##
## @param text 被搜索的文本。
## @param literal 待统计的字面片段。
## @return 出现次数。
func _count_occurrences(text: String, literal: String) -> int:
	if literal.is_empty():
		return 0
	var count: int = 0
	var from: int = 0
	while true:
		var found: int = text.find(literal, from)
		if found < 0:
			break
		count += 1
		from = found + literal.length()
	return count
