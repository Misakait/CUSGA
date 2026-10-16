@tool
extends McpTestSuite

## 掉落物自动拾取与缩小的契约套件。
##
## 本套件只做**源码形状与场景形状**断言，不做运行时行为断言。
## 原因：生产掉落视图 `loot_view.gd` 与协调器 `world_interaction_coordinator.gd` 都不是 `@tool`，
## 编辑器里 `PackedScene.instantiate()` 对它们只会得到占位实例、方法不可调用，
## 因此「靠近入包」「背包满不拾取」「飞入缩小消失」一律交给 Main 场景冒烟阶段的 `game_eval` 实证。
## 依据：`.trellis/spec/backend/testing-guidelines.md`「编辑器测试的边界」。

## 生产掉落视图脚本；视觉缩放与可拾取协议都在这里。
const LOOT_VIEW_GD: String = "res://scripts/loot_scripts/loot_view.gd"
## 生产掉落视图场景；鼠标命中区域在这里序列化。
const LOOT_SCENE: String = "res://scenes/Loot/Loot.tscn"
## 局外世界交互协调器；自动拾取的触发与结算都在这里。
const COORDINATOR_GD: String = "res://core/gameflow/world_interaction_coordinator.gd"


## 提供 GodotAI 使用的稳定套件名称。
##
## @return 掉落物自动拾取契约套件名。
func suite_name() -> String:
	return "loot_auto_pickup_contract"


## 判断文本中是否存在以指定关键字开头的声明行。
##
## 否定断言不能直接对整份源码用 contains()：脚本里解释「不要再保留旧入口」的注释本身会包含
## 那个标识符，会让断言无条件变红。只看真正的声明行可以避开注释干扰。
##
## @param text 待检查的源码文本。
## @param keyword 声明行开头应当匹配的关键字。
## @return 存在以该关键字开头的行时为 true。
func _has_declaration_line(text: String, keyword: String) -> bool:
	for line: String in text.split("\n"):
		if line.strip_edges().begins_with(keyword):
			return true

	return false


## 验证掉落物视觉缩放参数、可拾取协议与命中区域尺寸。
##
## @return 无返回值。
func test_loot_visual_scale_and_hit_area() -> void:
	var view: String = FileAccess.get_file_as_string(LOOT_VIEW_GD)
	for literal: String in [
		"@export_range(0.05, 2.0, 0.01) var LootVisualScale: float = 0.4",
		"func IsPickupAvailable() -> bool:",
		"_base_visual_scale = Vector2.ONE * LootVisualScale",
	]:
		assert_true(view.contains(literal), "掉落视图必须保留缩放与可拾取协议：%s" % literal)

	# 待机、悬停、散射与飞入四种表现全部由 _base_visual_scale 派生，
	# 漏接任何一处都会出现「待机变小但悬停弹回 100%」的基准不一致。
	assert_true(
		view.contains("_visuals.scale = _base_visual_scale"),
		"掉落物待机缩放必须来自视觉基准 _base_visual_scale。"
	)

	var scene_text: String = FileAccess.get_file_as_string(LOOT_SCENE)
	assert_true(
		scene_text.contains("size = Vector2(37.2, 54.8)"),
		"掉落物命中区域必须同步缩到 40%（93×137 → 37.2×54.8）。"
	)
	assert_true(
		scene_text.contains("RectangleShape2D_interaction"),
		"命中区域形状名必须保持场景序列化协议。"
	)


## 验证协调器的自动拾取入口、独立半径与两个鼠标入口的掉落物排除。
##
## @return 无返回值。
func test_coordinator_auto_pickup_shape() -> void:
	var coordinator: String = FileAccess.get_file_as_string(COORDINATOR_GD)
	for literal: String in [
		"@export_range(1.0, 1000.0, 1.0) var AutoPickupRange: float = 60.0",
		"func _process_auto_pickup() -> void:",
		"func _should_auto_pickup(card: Node2D) -> bool:",
		"func _is_loot_card(card: Node2D) -> bool:",
		"func _is_loot_within_auto_pickup_range(card: Node2D) -> bool:",
		"func _handle_loot_card_pickup(card: Node2D, stack: RefCounted) -> void:",
		"func _process_terrain_hold_input() -> void:",
	]:
		assert_true(coordinator.contains(literal), "协调器必须保留自动拾取协议：%s" % literal)

	# 自动拾取半径必须独立于地形交互半径：否则「只想调拾取手感」会被迫连带改地形交互距离，
	# 而且地形超范围要飘字、掉落物超范围必须静默，共用一个判定会诱导把提示逻辑带进拾取路径。
	assert_true(
		coordinator.contains(
			"_player_char.global_position.distance_to(card.global_position) <= AutoPickupRange"
		),
		"自动拾取必须按独立的 AutoPickupRange 判定，而不是复用 InteractionRange。"
	)
	# 掉落物必须在距离判定之前被排除，否则远处点击它会弹出对自动拾取毫无意义的「距离不够！」。
	assert_true(
		coordinator.contains("if _is_loot_card(card):"),
		"点击与按下两个鼠标入口都必须先排除掉落物。"
	)
	# 飞入中的卡片仍留在棋盘快照里（DetachForFlight 只 reparent），必须能识别出来跳过，避免重复入包。
	assert_true(
		coordinator.contains('card.has_method("IsPickupAvailable")'),
		"自动拾取必须按稳定方法协议查询掉落物是否仍可拾取。"
	)
	# 拾取入口已改名：点击拾取不再是独立函数，只保留靠近拾取这一个入口。
	assert_false(
		_has_declaration_line(coordinator, "func _handle_loot_card_clicked"),
		"掉落卡拾取不得再保留点击专用入口。"
	)


## 验证自动拾取由每帧棋盘快照驱动，且门禁覆盖暂停、过场与结算收尾。
##
## @return 无返回值。
func test_auto_pickup_is_driven_by_board_snapshot() -> void:
	var coordinator: String = FileAccess.get_file_as_string(COORDINATOR_GD)
	assert_true(
		coordinator.contains("func _process(_delta: float) -> void:\n\t_process_auto_pickup()"),
		"_process 必须每帧先推进自动拾取。"
	)
	assert_true(
		coordinator.contains('_board_controller.call("GetActiveCardsSnapshot")'),
		"自动拾取必须遍历棋盘活动卡牌快照。"
	)
	assert_true(
		coordinator.contains("if _is_run_ending() or not CanUseWorld():"),
		"自动拾取必须复用 CanUseWorld 门禁并叠加结算收尾判定。"
	)
