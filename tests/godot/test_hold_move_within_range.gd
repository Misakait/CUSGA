@tool
extends McpTestSuite

## 长按交互「范围内移动不打断」契约套件。
##
## 锁定三件事：地形卡长按期间在交互范围内移动必须保留长按（该复查函数不再读任何输入）、
## 走出 InteractionRange 必须按拥有者取消并给出距离不足反馈、
## 建筑拆除的每帧门禁只判距离而完成门禁才判遮挡，且「玩家自己动过鼠标」的判据是鼠标**屏幕**坐标的变化。
##
## 两个环境约束决定了本套件的形状：
## 1. 协调器与建筑控制器都不是 `@tool`，但 `GDScript.new()` 在编辑器运行器里拿到的是**真实**实例
##    （`test_room_terrain_store_contract.gd` 已用同一手法驱动生产脚本）。因此地形卡一侧用
##    「真实脚本 + 只注入内部字段的最小夹具」做运行期断言；`PackedScene.instantiate()` 的占位实例
##    限制只影响场景实例化，本套件不实例化任何生产场景。
## 2. 建筑一侧需要相机漂移与真实输入流程，最小夹具无法复刻。它的运行期行为由
##    `tests/godot/building_system_tests.tscn`（真实场景）与 Main 场景冒烟阶段的 `game_eval` 实证，
##    本套件只对建筑锁定源码形状。

## 地形卡长按的协调器。
const COORDINATOR: String = "res://core/gameflow/world_interaction_coordinator.gd"
## 建筑拆除长按的控制器。
const BUILDING_CONTROLLER: String = "res://core/building/building_controller.gd"
## 协调器脚本，供夹具直接实例化。
const COORDINATOR_SCRIPT: GDScript = preload("res://core/gameflow/world_interaction_coordinator.gd")
## 夹具里使用的交互范围，与生产默认值一致。
const FIXTURE_INTERACTION_RANGE: float = 160.0
## 夹具节点名前缀；运行器会清理带 `_McpTest` 前缀的残留节点。
const FIXTURE_NAME: String = "_McpTestHoldMoveWithinRangeFixture"


## 共享长按端口替身：只记录取消调用，不创建 Tween。
##
## 生产端口用 Tween 计时，而本运行器的用例是同步执行的、无法推进帧，因此这里只验证
## 「谁被取消、取消了几次」这一层事实，真实进度环行为由场景冒烟覆盖。
class StubHold extends Node:
	## 收到 cancel_hold_for 的拥有者，按调用顺序记录。
	var cancelled: Array = []
	## 收到 cancel_active_hold 的次数。
	var active_cancel_count: int = 0

	## 记录一次按拥有者的取消。
	##
	## @param hold_owner 请求取消的拥有者。
	## @return 无返回值。
	func cancel_hold_for(hold_owner: Node) -> void:
		cancelled.append(hold_owner)

	## 记录一次无条件取消；长按复查不得走这条路径，否则会误伤其它交互。
	##
	## @return 无返回值。
	func cancel_active_hold() -> void:
		active_cancel_count += 1


## 飘字服务替身：只记录 show_at_target 的实参，便于核对半径来源。
class StubFloatingText extends Node:
	## 每次调用的实参数组 [target, message, text_color, world_radius]。
	var calls: Array = []

	## 记录一次目标处飘字。
	##
	## @param target 提示锚点节点。
	## @param message 正文文案。
	## @param text_color 正文颜色。
	## @param world_radius 提示圈的世界半径。
	## @return 无返回值。
	func show_at_target(target: Node, message: String, text_color: Color, world_radius: float) -> void:
		calls.append([target, message, text_color, world_radius])


## 地形卡替身：只提供协调器长按路径真正会调用的两个协议。
class StubCard extends Node2D:
	## 收到的 SetDestroying 实参，按调用顺序记录。
	var destroying_calls: Array = []

	## 记录一次抖动状态切换。
	##
	## @param destroying 目标抖动状态。
	## @return 无返回值。
	func SetDestroying(destroying: bool) -> void:
		destroying_calls.append(destroying)

	## 返回空地形实例，让完成回调越过「地形是否仍是同一个」的前置校验。
	##
	## 完成入口的范围复查排在这次校验之后、读取地形内容之前，因此夹具用 null 即可覆盖。
	##
	## @return 固定返回 null。
	func GetTerrainInstanceOrNull() -> Variant:
		return null


## 玩家鼠标移动屏蔽替身：记录两个协议名的调用顺序。
class StubClickWalk extends Node:
	## 收到的协议名，按调用顺序记录。
	var calls: Array = []

	## 记录进入世界交互。
	##
	## @return 无返回值。
	func BeginWorldInteraction() -> void:
		calls.append(&"BeginWorldInteraction")

	## 记录结束世界交互。
	##
	## @return 无返回值。
	func EndWorldInteraction() -> void:
		calls.append(&"EndWorldInteraction")


## 提供 GodotAI 使用的稳定套件名称。
func suite_name() -> String:
	return "hold_move_within_range"


## 地形卡长按期间在交互范围内移动：长按必须保留，且不产生任何取消或提示。
##
## 改动前这条会失败：旧实现每帧只要按下任意 WASD 就取消长按。
## 键盘本身无法在本运行器里模拟——`move_*` 动作只写在 project.godot，
## 编辑器进程的 InputMap 里并没有它们（input_map_manage 的 loaded_in_input_map 全为 false），
## `Input.action_press` 会直接报错。因此「键盘不再打断」由 test_source_contracts 里
## 「该函数不读任何输入」的形状断言承担，这里承担它真正的语义：**移动**只要不出范围就不打断。
##
## @return 无返回值。
func test_terrain_hold_survives_in_range_movement() -> void:
	var fixture: Dictionary = _make_terrain_fixture(Vector2(200, 200), Vector2(300, 200))
	var coordinator: Node = fixture["coordinator"]
	var card: StubCard = fixture["card"]
	var player: Node2D = fixture["player"]
	var hold: StubHold = fixture["hold"]
	var floating: StubFloatingText = fixture["floating"]

	# 走一步：距离从 100 变成约 63.2，仍在 160 之内。
	player.global_position = Vector2(240, 220)
	coordinator.call("_process_terrain_hold_input")

	assert_eq(coordinator.get("_active_terrain_hold_card"), card, "范围内移动不得清空地形长按记录。")
	assert_true(hold.cancelled.is_empty(), "范围内移动不得取消共享长按。")
	assert_eq(hold.active_cancel_count, 0, "范围内移动不得走无条件取消路径。")
	assert_true(floating.calls.is_empty(), "范围内移动不得弹出距离不足提示。")
	assert_true(card.destroying_calls.is_empty(), "范围内移动不得复位卡牌抖动。")


## 地形卡长按期间走出交互范围：立即取消、按拥有者提交、给出距离不足反馈并复位表现。
##
## @return 无返回值。
func test_terrain_hold_cancels_when_leaving_range() -> void:
	var fixture: Dictionary = _make_terrain_fixture(Vector2(200, 200), Vector2(300, 200))
	var coordinator: Node = fixture["coordinator"]
	var card: StubCard = fixture["card"]
	var player: Node2D = fixture["player"]
	var hold: StubHold = fixture["hold"]
	var floating: StubFloatingText = fixture["floating"]
	var click_walk: StubClickWalk = fixture["click_walk"]

	# 玩家原地不动时距离是 100，走出去后是 400，跨过 160 的边界。
	player.global_position = Vector2(600, 200)
	coordinator.call("_process_terrain_hold_input")

	assert_eq(coordinator.get("_active_terrain_hold_card"), null, "走出范围必须清空地形长按记录。")
	assert_eq(hold.cancelled.size(), 1, "走出范围必须且只取消一次共享长按。")
	assert_eq(hold.cancelled[0], card, "取消必须按拥有者提交，避免误伤已接管的其它交互。")
	assert_eq(hold.active_cancel_count, 0, "取消不得走无条件路径。")
	assert_eq(floating.calls.size(), 1, "走出范围必须给出一次距离不足提示。")
	assert_eq(floating.calls[0][1], "距离不够！", "提示文案必须与其它距离不足入口共用同一措辞。")
	assert_eq(float(floating.calls[0][3]), FIXTURE_INTERACTION_RANGE, "提示圈半径必须与距离判定同源。")
	assert_eq(card.destroying_calls, [false], "取消后必须复位卡牌抖动。")
	assert_eq(click_walk.calls, [&"EndWorldInteraction"], "取消后必须解除鼠标移动屏蔽。")


## 地形卡长按完成瞬间仍按同一判定复查：走出范围后完成回调不得结算。
##
## Tween 可能比 _process 的范围门禁先结算，因此完成入口必须自己再判一次。
##
## @return 无返回值。
func test_terrain_hold_completion_rechecks_range() -> void:
	var fixture: Dictionary = _make_terrain_fixture(Vector2(200, 200), Vector2(300, 200))
	var coordinator: Node = fixture["coordinator"]
	var card: StubCard = fixture["card"]
	var player: Node2D = fixture["player"]
	var floating: StubFloatingText = fixture["floating"]

	player.global_position = Vector2(600, 200)
	# 完成回调的四个形参与 begin_hold 的 bind 逐位一致；地形与交互资源在夹具里传 null，
	# 因为范围复查排在读取它们之前，走不到需要真实资源的分支。
	coordinator.call("_complete_terrain_hold", card, null, null, 0)

	assert_eq(coordinator.get("_active_terrain_hold_card"), null, "完成回调必须先清空长按记录。")
	assert_eq(floating.calls.size(), 1, "完成瞬间走出范围必须给出距离不足提示。")
	assert_eq(card.destroying_calls, [false], "完成瞬间被拒绝也必须复位卡牌抖动。")


## 源码形状：两条长按的取消条件与门禁拆分必须留在生产文件里。
##
## @return 无返回值。
func test_source_contracts() -> void:
	var coordinator: String = FileAccess.get_file_as_string(COORDINATOR)
	var building: String = FileAccess.get_file_as_string(BUILDING_CONTROLLER)

	var hold_process: String = _function_body(coordinator, "func _process_terrain_hold_input() -> void:")
	assert_true(hold_process.contains("_try_get_interaction_range(_active_terrain_hold_card)"),
		"长按复查必须复用按下时的距离判定，不引入第二处距离口径。")
	assert_true(hold_process.contains("cancel_hold_for"), "走出范围必须按拥有者取消。")
	assert_true(hold_process.contains("_report_out_of_range_interaction"), "走出范围必须给出距离不足反馈。")
	assert_false(hold_process.contains("Input."),
		"长按复查不得读任何输入：键盘是否按下与长按无关，移动只由距离决定。")

	var press: String = _function_body(coordinator, "func _on_board_card_pressed(card: Node2D) -> void:")
	assert_false(press.contains("Input.get_vector"), "按下入口不得再因为方向键已按住而放弃长按。")

	var complete: String = _function_body(coordinator, "func _complete_terrain_hold(")
	assert_true(complete.contains("_try_get_interaction_range(card)"),
		"完成入口必须复查距离，避免 Tween 比每帧门禁先结算。")

	var continue_gate: String = _function_body(building, "func _can_continue_demolition() -> bool:")
	assert_true(continue_gate.contains("_is_record_in_range"), "每帧门禁必须只判距离。")
	assert_true(continue_gate.contains("_is_demolition_target_kept"), "每帧门禁必须复查目标是否被切换。")
	assert_false(continue_gate.contains("_is_record_reachable"),
		"每帧门禁不得判遮挡，否则走到墙后会打断拆除。")

	var complete_gate: String = _function_body(building, "func _can_complete_demolition() -> bool:")
	assert_true(complete_gate.contains("_is_record_reachable"), "完成门禁必须保留遮挡判定。")
	assert_true(complete_gate.contains("_record_for_instance"), "完成门禁必须按锁定目标取记录。")

	var kept: String = _function_body(building, "func _is_demolition_target_kept() -> bool:")
	assert_true(kept.contains("_mouse_screen_position"), "目标复查必须按鼠标屏幕坐标判断玩家是否动过鼠标。")
	assert_true(kept.contains("DEMOLITION_MOUSE_MOVE_TOLERANCE"), "漂移判定必须使用屏幕位移容差。")
	assert_true(kept.contains("_building_under_pointer"), "玩家动过鼠标时仍要按光标复查目标。")

	var screen: String = _function_body(building, "func _mouse_screen_position() -> Vector2:")
	assert_true(screen.contains("get_canvas_transform()"), "屏幕坐标必须由画布变换换算才能抵消相机漂移。")
	assert_false(screen.contains("get_mouse_position()"),
		"不得直接读视口鼠标坐标：那会绕过回归场景已注入的采样接口。")

	var begin: String = _function_body(building, "func _begin_demolition(record: Dictionary) -> void:")
	assert_true(begin.contains("_demolition_mouse_screen = _mouse_screen_position()"),
		"开始拆除必须写入鼠标屏幕坐标基准。")

	var out_of_range: String = _function_body(building, "func _out_of_range_demolition_record() -> Dictionary:")
	assert_true(out_of_range.contains("_is_record_in_range"), "距离不足反馈必须复用距离判定。")

	assert_true(building.contains("正在拆除 · 松开左键、移开鼠标或走出交互范围取消"),
		"拆除提示必须写明走出交互范围也会取消。")


## 构造只注入内部字段的地形长按夹具。
##
## 协调器是真实生产脚本，这里不实例化任何生产场景，只注入长按复查路径真正会读的字段。
## 只有玩家与卡牌进场景树：`Node2D.global_position` 在树外返回零变换，距离判定会失真。
## 协调器刻意留在树外——它的 `_ready()` 会连接 Main 场景里的固定节点路径，进树即报错；
## 而长按复查只读字段、只调替身，不需要它自己在树内。树外节点由 `track()` 负责释放。
##
## @param player_position 玩家节点的世界坐标。
## @param card_position 地形卡节点的世界坐标。
## @return 含 root / coordinator / card / player / hold / floating / click_walk 的字典。
func _make_terrain_fixture(player_position: Vector2, card_position: Vector2) -> Dictionary:
	var root: Node2D = Node2D.new()
	root.name = FIXTURE_NAME
	_editor_root().add_child(root)
	track(root)

	var player: Node2D = Node2D.new()
	var card: StubCard = StubCard.new()
	root.add_child(player)
	root.add_child(card)

	var coordinator: Node = track(COORDINATOR_SCRIPT.new()) as Node
	var hold: StubHold = track(StubHold.new()) as StubHold
	var floating: StubFloatingText = track(StubFloatingText.new()) as StubFloatingText
	var click_walk: StubClickWalk = track(StubClickWalk.new()) as StubClickWalk

	player.global_position = player_position
	card.global_position = card_position
	coordinator.set("_player_char", player)
	coordinator.set("_active_terrain_hold_card", card)
	coordinator.set("_hold_interaction_controller", hold)
	coordinator.set("_floating_text", floating)
	coordinator.set("_player_click_walk_state", click_walk)
	coordinator.set("InteractionRange", FIXTURE_INTERACTION_RANGE)

	return {
		"root": root,
		"coordinator": coordinator,
		"card": card,
		"player": player,
		"hold": hold,
		"floating": floating,
		"click_walk": click_walk,
	}


## 取编辑器主循环的场景树根，用于把夹具挂进真实场景树。
##
## `McpTestSuite` 继承 `RefCounted`，没有 `get_tree()`；只能经 `Engine.get_main_loop()` 拿场景树。
##
## @return 场景树根节点。
func _editor_root() -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	return tree.root


## 截取一个顶层函数的源码片段：从签名行起到该函数末尾。
##
## 直接对整份文件做 `contains()` 会误判——脚本里解释「不要写 X」的注释本身包含 X。
## 顶层函数之间固定空两行，据此截断，同时把下一个函数的文档注释排除在外。
##
## @param source 完整脚本源码。
## @param signature 目标函数的签名片段（含 func 关键字）。
## @return 该函数的源码片段；签名不存在时返回空字符串。
func _function_body(source: String, signature: String) -> String:
	var start: int = source.find(signature)
	if start < 0:
		return ""
	var tail: String = source.substr(start)
	var end: int = tail.find("\n\n\n")
	if end < 0:
		return tail
	return tail.substr(0, end)
