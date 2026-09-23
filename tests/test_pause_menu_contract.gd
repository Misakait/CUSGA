@tool
extends McpTestSuite

## 局内暂停菜单（PauseMenu）的集成点契约套件。
##
## 暂停菜单挂在 Main/UI/HUDLayer/HUDRoot 下。该宿主是局外探索与局内战斗都存活的
## 唯一 UI 宿主，所以「暂停键是否还在这个宿主上」「ESC 是否还绑到暂停动作」
## 「退出游戏是否先解除暂停再换场景」都会在真实对局里决定玩家能不能脱身。
##
## 暂停映射（get_tree().paused 的取值与恢复）依赖 SceneTree 与真实 Main 实例，
## 编辑器进程里既没有 Main，也不会执行非 @tool 脚本的方法体，因此那部分按
## .trellis/spec/frontend/state-management.md 的浮层验证约定，用运行中游戏进程的
## game_eval 断言；本套件锁住结构与集成点，防止暂停键被摘掉、被改键或菜单被挪走。

## 待验证的暂停菜单脚本。
const PAUSE_MENU_SCRIPT: GDScript = preload("res://core/ui/hud/pause_menu.gd")

## 待验证的暂停菜单场景。
const PAUSE_MENU_SCENE: PackedScene = preload("res://scenes/ui_scenes/pause_menu.tscn")

## 暂停菜单场景的 res:// 路径。
const PAUSE_MENU_SCENE_PATH: String = "res://scenes/ui_scenes/pause_menu.tscn"

## 生产主场景路径。
const MAIN_SCENE_PATH: String = "res://scenes/Main.tscn"

## 主菜单场景路径，必须与脚本常量一致。
const EXPECTED_MAIN_MENU_SCENE_PATH: String = "res://scenes/main_menu_scenes/main_menu.tscn"

## 项目配置文件路径。
const PROJECT_CONFIG_PATH: String = "res://project.godot"

## 暂停菜单必须挂载的直接父节点声明。
##
## 只要这行还在，暂停菜单就仍然活在被局内战斗保留的 HUD 宿主上；一旦有人把它挪进
## battle.tscn，这条断言就会当场失败。
const REQUIRED_HOST_DECLARATION: String = "[node name=\"PauseMenu\" parent=\"UI/HUDLayer/HUDRoot\""

## 脚本里必须保留的控件接线语句。
## 非 @tool 脚本在编辑器进程里不会执行 _ready，因此接线用源码断言锁定。
const REQUIRED_WIRING_STATEMENTS: Array[String] = [
	"_pause_button.pressed.connect(_on_pause_button_pressed)",
	"_continue_button.pressed.connect(_on_continue_button_pressed)",
	"_exit_button.pressed.connect(_on_exit_button_pressed)",
]

## 脚本里必须保留的公开入口。
const REQUIRED_PUBLIC_METHODS: Array[String] = [
	"func open_pause_menu",
	"func close_pause_menu",
	"func toggle_pause_menu",
	"func _on_continue_button_pressed",
	"func _on_exit_button_pressed",
]

## 菜单必须按「继续游戏」在前、「退出游戏」在后排列的按钮。
## 继续游戏排在第一位，玩家打开菜单后第一个看到的选项才是「回到游戏」。
const REQUIRED_MENU_ORDER: Array[String] = [
	"ContinueButton",
	"ExitButton",
]


## 返回 GodotAI 使用的稳定套件名称。
## 返回值：暂停菜单契约套件名。
func suite_name() -> String:
	return "pause_menu_contract"


## 验证暂停动作已注册并绑定 ESC，且脚本引用的是同一个动作名。
##
## 绑定丢失或改成别的键时，玩家按 ESC 不会有任何反应，而界面本身仍然「看起来正常」，
## 因此这条断言是这套契约里最不能省的一条。
## 返回值：无。
func test_pause_action_is_registered_on_escape() -> void:
	var action_name: String = str(PAUSE_MENU_SCRIPT.get_script_constant_map()["PAUSE_ACTION"])
	assert_eq(action_name, "pause_game", "脚本必须监听 pause_game 动作。")

	# 编辑器进程不会把 project.godot 的输入映射载入 InputMap 单例（此处所有项目动作的
	# loaded_in_input_map 都是 false），所以这里只断言配置文件本身；按键是否真的生效由
	# 运行中游戏进程的 game_eval 负责。
	var block: String = _action_block(
		FileAccess.get_file_as_string(PROJECT_CONFIG_PATH),
		action_name
	)
	assert_false(block.is_empty(), "project.godot 必须包含 pause_game 动作块。")
	assert_true(
		block.contains("\"keycode\":%d" % KEY_ESCAPE),
		"pause_game 必须绑定 ESC（keycode %d）。" % KEY_ESCAPE
	)


## 验证暂停菜单仍挂在跨状态存活的 HUD 宿主上，且主场景引用了生产场景。
##
## 局内战斗把 battle.tscn 作为 Main 的子节点挂载，current_scene 仍是 Main；
## 只有挂在 HUDLayer/HUDRoot 下的浮层才能在两种状态下都可用。
## 返回值：无。
func test_scene_is_hosted_by_the_cross_state_hud_root() -> void:
	var main_scene_text: String = FileAccess.get_file_as_string(MAIN_SCENE_PATH)
	assert_false(main_scene_text.is_empty(), "必须能读到生产主场景。")

	assert_true(
		_find_node_declaration(main_scene_text, "HUDRoot").contains("parent=\"UI/HUDLayer\""),
		"HUDRoot 必须仍挂在 UI/HUDLayer 下。"
	)
	assert_true(
		main_scene_text.contains("path=\"%s\"" % PAUSE_MENU_SCENE_PATH),
		"主场景必须引用暂停菜单生产场景。"
	)
	assert_true(
		_find_node_declaration(main_scene_text, "PauseMenu").begins_with(REQUIRED_HOST_DECLARATION),
		"暂停菜单必须直接挂在 UI/HUDLayer/HUDRoot 下。"
	)


## 验证浮层结构与初始可见性符合全屏浮层契约。
##
## 根 Control 必须忽略鼠标，隐藏时才不会吞掉 HUD 点击；暂停键本身必须常驻，
## 否则菜单关着的时候玩家没有任何暂停入口。
## 返回值：无。
func test_overlay_starts_hidden_and_root_ignores_mouse() -> void:
	var scene_tree := Engine.get_main_loop() as SceneTree
	var menu := _new_pause_menu(scene_tree)

	assert_eq(menu.mouse_filter, Control.MOUSE_FILTER_IGNORE, "浮层根节点必须忽略鼠标，避免吞掉 HUD 点击。")
	assert_eq(menu.process_mode, Node.PROCESS_MODE_ALWAYS, "暂停期间菜单必须继续处理输入。")
	assert_eq(menu.visible, true, "浮层根节点常驻，暂停键才能一直可见。")

	var overlay := menu.get_node("%PauseOverlay") as Control
	var pause_button := menu.get_node("%PauseButton") as Button
	assert_false(overlay.visible, "菜单浮层初始必须隐藏。")
	assert_true(pause_button.visible, "右上角暂停键必须常驻可见。")

	# 暂停键必须贴在视口右上角：左右锚点都为 1，且右偏移为负。
	assert_eq(pause_button.anchor_left, 1.0, "暂停键必须锚定在右侧。")
	assert_eq(pause_button.anchor_right, 1.0, "暂停键必须锚定在右侧。")
	assert_true(pause_button.offset_right <= 0.0, "暂停键必须从右边缘向内偏移。")

	_dispose(scene_tree, menu)


## 验证菜单两个选项的文案与先后顺序：「继续游戏」必须在第一行。
##
## 顺序断言用同一容器内的索引而不是屏幕坐标：容器布局由子节点顺序决定，索引比较
## 不依赖节点是否已经完成一帧布局，因此在编辑器进程里同样可靠。
## 返回值：无。
func test_menu_offers_continue_first_then_exit() -> void:
	var scene_tree := Engine.get_main_loop() as SceneTree
	var menu := _new_pause_menu(scene_tree)

	var continue_button := menu.get_node("%ContinueButton") as Button
	var exit_button := menu.get_node("%ExitButton") as Button
	assert_eq(continue_button.text, "继续游戏", "菜单第一行必须是「继续游戏」。")
	assert_eq(exit_button.text, "退出游戏", "菜单必须保留「退出游戏」选项。")

	assert_eq(continue_button.get_parent(), exit_button.get_parent(), "两个选项必须挂在同一个纵向容器下。")
	assert_true(
		continue_button.get_index() < exit_button.get_index(),
		"「继续游戏」必须排在「退出游戏」之前。"
	)
	assert_true(
		continue_button.visible and exit_button.visible,
		"两个选项在菜单展开时都必须可见。"
	)

	_dispose(scene_tree, menu)


## 验证生产场景把暂停键放在右上角，并把菜单内容交给全屏 CenterContainer 居中。
##
## 只给子面板设 0.5 锚点、offsets 留 0 会把它推到右下角，因此居中必须由全屏
## CenterContainer 承担。
## 返回值：无。
func test_production_scene_places_pause_button_in_the_top_right_corner() -> void:
	var scene_text: String = FileAccess.get_file_as_string(PAUSE_MENU_SCENE_PATH)
	assert_false(scene_text.is_empty(), "必须能读到暂停菜单场景。")

	var declaration: String = _find_node_declaration(scene_text, "PauseButton")
	assert_true(not declaration.is_empty(), "场景必须包含 PauseButton。")
	assert_true(
		declaration.contains("parent=\".\""),
		"暂停键必须直接挂在浮层根节点下，才能独立于菜单显隐常驻显示。"
	)
	assert_true(
		scene_text.contains("type=\"CenterContainer\""),
		"菜单内容必须交给全屏 CenterContainer 居中，而不是靠子面板自身锚点。"
	)
	assert_true(scene_text.contains("type=\"ColorRect\""), "暂停时必须有一层全屏遮罩。")


## 验证生产场景引用了唯一名节点，脚本才能用 %Name 解析菜单控件。
##
## 唯一名被摘掉时，脚本的 @onready 引用会在真实游戏里变成 null，而场景本身
## 仍然能正常加载——这正是需要在这里锁住的原因。
## 返回值：无。
func test_scene_exposes_the_unique_names_the_script_depends_on() -> void:
	var scene_text: String = FileAccess.get_file_as_string(PAUSE_MENU_SCENE_PATH)
	var script_source: String = FileAccess.get_file_as_string(PAUSE_MENU_SCRIPT.resource_path)

	for node_name: String in ["PauseButton", "PauseOverlay", "ContinueButton", "ExitButton"]:
		assert_true(
			not _find_node_declaration(scene_text, node_name).is_empty(),
			"场景必须包含 %s 节点。" % node_name
		)
		assert_true(
			_find_node_block(scene_text, node_name).contains("unique_name_in_owner = true"),
			"%s 必须开启唯一名，脚本才能用 %%%s 解析。" % [node_name, node_name]
		)
		assert_true(
			script_source.contains("%%%s" % node_name),
			"脚本必须通过 %%%s 引用该控件。" % node_name
		)


## 验证生产场景里两个选项的声明顺序与契约一致。
##
## 场景文本的声明顺序就是纵向容器里的排列顺序，这条断言让「继续游戏在第一行」
## 在场景文件层面也可被守住，而不只是运行时布局的结果。
## 返回值：无。
func test_production_scene_declares_continue_before_exit() -> void:
	var scene_text: String = FileAccess.get_file_as_string(PAUSE_MENU_SCENE_PATH)
	var previous_index: int = -1

	for node_name: String in REQUIRED_MENU_ORDER:
		var index: int = scene_text.find("[node name=\"%s\"" % node_name)
		assert_gt(index, -1, "场景必须声明 %s 节点。" % node_name)
		assert_gt(index, previous_index, "%s 必须声明在上一项之后，保持菜单顺序。" % node_name)
		previous_index = index


## 验证脚本保留暂停与退出的公开入口，以及暂停键与两个菜单按钮的接线。
##
## 非 @tool 脚本的 _ready 在编辑器进程里不执行，因此接线关系只能由源码锁定；
## 缺少任一条都会让按钮在真实对局里「点着没反应」。
## 返回值：无。
func test_script_keeps_wiring_and_public_entries() -> void:
	var source: String = FileAccess.get_file_as_string(PAUSE_MENU_SCRIPT.resource_path)
	assert_false(source.is_empty(), "必须能读到暂停菜单脚本。")

	for method_declaration: String in REQUIRED_PUBLIC_METHODS:
		assert_true(source.contains(method_declaration), "脚本必须保留入口 %s。" % method_declaration)

	for wiring: String in REQUIRED_WIRING_STATEMENTS:
		assert_true(source.contains(wiring), "脚本必须保留接线 %s。" % wiring)

	assert_true(
		source.contains("process_mode = Node.PROCESS_MODE_ALWAYS"),
		"脚本必须保证暂停期间菜单仍能处理输入。"
	)
	assert_true(
		source.contains("event.is_action_pressed(PAUSE_ACTION)"),
		"脚本必须监听暂停动作。"
	)
	assert_true(
		source.contains("get_viewport().set_input_as_handled()"),
		"消费暂停按键后必须标记事件已处理，避免同一次按键再次切换。"
	)


## 验证暂停映射的两条分支：打开才暂停，且只归还自己造成的暂停。
##
## 天赋选择界面（talent_manager.gd）也用同一个全局暂停开关。菜单必须记录打开前的
## 状态，否则关闭菜单会把本该停住的界面放回运行。
## 返回值：无。
func test_pause_mapping_records_and_restores_previous_state() -> void:
	var source: String = FileAccess.get_file_as_string(PAUSE_MENU_SCRIPT.resource_path)

	var open_body: String = _method_body(source, "func open_pause_menu")
	assert_true(open_body.contains("_was_paused_before_open = get_tree().paused"), "打开前必须记录全局暂停状态。")
	assert_true(open_body.contains("get_tree().paused = true"), "打开菜单必须暂停游戏。")

	var close_body: String = _method_body(source, "func close_pause_menu")
	assert_true(close_body.contains("_is_menu_open = false"), "关闭必须先清除展开状态。")
	assert_true(
		close_body.contains("if not _was_paused_before_open:"),
		"关闭时只能归还本次打开造成的暂停。"
	)
	assert_true(close_body.contains("get_tree().paused = false"), "关闭菜单必须解除本次暂停。")

	# 「继续游戏」必须复用同一条关闭路径，否则暂停的归还判据会出现第二份实现。
	var continue_body: String = _method_body(source, "func _on_continue_button_pressed")
	assert_true(continue_body.contains("close_pause_menu()"), "「继续游戏」必须复用关闭菜单的路径。")
	assert_false(continue_body.contains("paused ="), "「继续游戏」不得自行改写全局暂停。")


## 验证退出游戏接到的处理函数会先解除暂停、再换回主菜单场景，并有释放兜底。
##
## 这里刻意不真的点击按钮：那会切换编辑器当前场景。断言改为源码顺序与常量值，
## 共同锁住「换场景前必须解除暂停」这条契约——否则主菜单会带着 paused = true
## 启动，表现为整屏无响应。
## 返回值：无。
func test_exit_releases_pause_before_switching_scene() -> void:
	var source: String = FileAccess.get_file_as_string(PAUSE_MENU_SCRIPT.resource_path)
	var handler_body: String = _method_body(source, "func _on_exit_button_pressed")

	var release_index: int = handler_body.find("paused = false")
	var switch_index: int = handler_body.find("change_scene_to_file")
	assert_gt(release_index, -1, "退出处理必须先解除全局暂停。")
	assert_gt(switch_index, -1, "退出处理必须切换到主菜单场景。")
	assert_true(release_index < switch_index, "解除暂停必须发生在切换场景之前。")

	var target_path: String = str(PAUSE_MENU_SCRIPT.get_script_constant_map()["MAIN_MENU_SCENE_PATH"])
	assert_eq(target_path, EXPECTED_MAIN_MENU_SCENE_PATH, "退出游戏必须回到生产主菜单场景。")
	assert_true(ResourceLoader.exists(target_path), "主菜单场景路径必须真实存在。")

	# 非正常释放（外部换场景、编辑器停跑）时也必须归还暂停，否则下一个场景会带着
	# paused = true 启动；_exit_tree 是这条路径的唯一兜底。
	var exit_tree_body: String = _method_body(source, "func _exit_tree")
	assert_true(exit_tree_body.contains("tree.paused = false"), "场景释放时必须兜底归还全局暂停。")


## 在场景文件全文里定位某个节点的声明行。
## 参数 scene_text：场景文件全文。
## 参数 node_name：节点名。
## 返回值：匹配到的声明行；未找到时返回空字符串。
func _find_node_declaration(scene_text: String, node_name: String) -> String:
	var marker: String = "[node name=\"%s\"" % node_name
	for raw_line: String in scene_text.split("\n"):
		if raw_line.begins_with(marker):
			return raw_line

	return ""


## 在场景文件全文里截取某个节点的完整声明块（包含其属性行）。
## 参数 scene_text：场景文件全文。
## 参数 node_name：节点名。
## 返回值：从声明行到下一个节点声明之前的文本；未找到时返回空字符串。
func _find_node_block(scene_text: String, node_name: String) -> String:
	var start: int = scene_text.find("[node name=\"%s\"" % node_name)
	if start < 0:
		return ""

	var end: int = scene_text.find("\n[node ", start + 1)
	if end < 0:
		return scene_text.substr(start)

	return scene_text.substr(start, end - start)


## 在脚本源码里截取某个函数的函数体（到下一个顶层 func 之前）。
## 参数 source：脚本全文。
## 参数 declaration：函数声明前缀，例如 "func open_pause_menu"。
## 返回值：函数体文本（含声明行）；未找到时返回空字符串。
func _method_body(source: String, declaration: String) -> String:
	var start: int = source.find(declaration)
	if start < 0:
		return ""

	var next: int = source.find("\nfunc ", start + 1)
	var body: String = source.substr(start) if next < 0 else source.substr(start, next - start)

	# 剥掉尾部紧邻的下一个函数的文档注释：那些行从属于下一个函数，留在尾部会让
	# 「方法体里不包含 X」这类否定断言被注释文本误伤（例如注释里写了 paused = true）。
	var lines: PackedStringArray = body.split("\n")
	while not lines.is_empty() and lines[lines.size() - 1].begins_with("##"):
		lines.remove_at(lines.size() - 1)

	return "\n".join(lines)


## 从 project.godot 文本里截取某个输入动作的配置块。
## 参数 config_text：project.godot 全文。
## 参数 action_name：输入动作名。
## 返回值：动作块文本；未找到时返回空字符串。
func _action_block(config_text: String, action_name: String) -> String:
	var start: int = config_text.find("%s={" % action_name)
	if start < 0:
		return ""

	var end: int = config_text.find("\n}\n", start)
	if end < 0:
		return config_text.substr(start)

	return config_text.substr(start, end - start)


## 实例化生产暂停菜单并挂到测试根节点。
##
## 菜单脚本不是 @tool，编辑器进程不会执行它的方法体；这里实例化只为断言场景自身的
## 结构属性（鼠标过滤、暂停模式、初始显隐、锚点、唯一名、选项顺序）。
## 参数 scene_tree：当前测试的主循环。
## 返回值：已进入场景树的暂停菜单。
func _new_pause_menu(scene_tree: SceneTree) -> Control:
	var menu := PAUSE_MENU_SCENE.instantiate() as Control
	menu.name = "PauseMenuContractProbe"
	scene_tree.root.add_child(menu)
	return menu


## 释放测试期间创建的暂停菜单。
## 参数 scene_tree：当前测试的主循环。
## 参数 menu：本用例创建的菜单。
## 返回值：无。
func _dispose(scene_tree: SceneTree, menu: Control) -> void:
	if is_instance_valid(menu):
		if menu.get_parent() != null:
			scene_tree.root.remove_child(menu)
		menu.free()
