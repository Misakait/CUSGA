@tool
extends McpTestSuite

## 长按破坏抖动契约套件。
##
## 锁定五件事：抖动作用于**整张卡牌**（卡牌节点、卡框、卡内图标一起动）、
## 进度圆环锚点在抖动期间逐帧静止、锚点复刻的屏幕位置与「直接锚定图标」完全一致、
## 抖动期间重算锚点不会把当前偏移烘进锚点、启动与停止幂等且停止后精确复位。
##
## 两个环境约束决定了本套件的形状：
## 1. `item_view.gd` / `building_view.gd` 不是 `@tool`，在编辑器测试运行器里实例化后是
##    placeholder instance，实例方法不可调用；`building_view.tscn` 还被 `building_controller.gd`
##    preload 缓存，场景改动在本进程内不保证可见。因此这里不实例化生产场景，
##    而是用等价层级的最小夹具直接驱动生产组件，真实场景与真实长按由运行期 `game_eval` 覆盖。
## 2. 本运行器的用例是同步执行的（`suite.call(method_name)` 不 await），无法推进 Tween 帧，
##    因此这里直接驱动随机偏移算法做确定性断言，跨帧的「持续抖动」同样由 `game_eval` 覆盖。

## 地形卡视图脚本。
const ITEM_VIEW: String = "res://scripts/item_scripts/item_view.gd"
## 地形卡场景。
const ITEM_SCENE: String = "res://scenes/ItemTerrian/Item.tscn"
## 建筑视图脚本。
const BUILDING_VIEW: String = "res://core/building/building_view.gd"
## 建筑视图场景。
const BUILDING_SCENE: String = "res://scenes/building/building_view.tscn"
## 地形卡破坏长按的协调器。
const COORDINATOR: String = "res://core/gameflow/world_interaction_coordinator.gd"
## 建筑拆除长按的控制器。
const BUILDING_CONTROLLER: String = "res://core/building/building_controller.gd"
## 共享长按端口；本任务不得改它的公开签名。
const HOLD_CONTROLLER: String = "res://core/gameflow/world_hold_interaction_controller.gd"
## 动作参数脚本。
const MOTION_CONFIG_SCRIPT: String = "res://resources/interaction/item_motion_config.gd"

## 生产地形卡图标的静止坐标与缩放，夹具必须复刻它们才能验证锚点公式。
const PRODUCTION_ICON_POSITION: Vector2 = Vector2(50, 83)
const PRODUCTION_ICON_SCALE: Vector2 = Vector2(2, 2)
## 生产卡框在卡牌节点空间里的左上角（Button 居中锚点 + 偏移 -50.5 / -70.5）。
const PRODUCTION_PLAYER_VIEW_POSITION: Vector2 = Vector2(-50.5, -70.5)
## 夹具里卡牌节点的静止坐标。
##
## 生产场景中 `Visuals.position` 是 `(0, 0)`；夹具故意取非零值，让「停止后精确复位」
## 无法靠写死原点蒙对，必须真的用采样到的静止坐标。
const FIXTURE_VISUALS_POSITION: Vector2 = Vector2(4.0, -6.0)
## 夹具节点名前缀；运行器会清理带 `_McpTest` 前缀的残留节点。
const FIXTURE_NAME: String = "_McpTestDestroyShakeFixture"


## 提供 GodotAI 使用的稳定套件名称。
func suite_name() -> String:
	return "destroy_hold_shake"


## 源码与场景形状：抖动目标是整张卡牌、锚点在被抖子树之外、两个调用点与配置字段都必须留在生产文件里。
func test_source_contracts() -> void:
	var item_view: String = FileAccess.get_file_as_string(ITEM_VIEW)
	assert_true(
		item_view.contains("func SetDestroying(destroying: bool) -> void:"),
		"地形卡视图必须提供幂等入口 SetDestroying。"
	)
	assert_true(
		item_view.contains("return _progress_anchor"),
		"GetProgressAnchor 必须返回不参与抖动的锚点，否则圆环会随卡牌一起抖。"
	)
	assert_true(
		item_view.contains("_shake.SyncAnchor(_icon, _progress_anchor)"),
		"地形卡必须在刷新视图时重算锚点。"
	)
	# 抖动目标必须是卡牌节点 _visuals 而不是卡内图标 _icon；用正则容忍缩进与换行差异。
	assert_true(
		_matches(item_view, "_shake = DestroyShake\\.new\\(\\s*_visuals,"),
		"地形卡抖动必须作用于整张卡牌的视觉根节点 _visuals，而不是卡内的 _icon。"
	)
	assert_true(
		item_view.contains("@onready var _progress_anchor: Marker2D = $ProgressAnchor"),
		"地形卡锚点必须挂在根节点下，位于被抖动的 Visuals 子树之外。"
	)

	var building_view: String = FileAccess.get_file_as_string(BUILDING_VIEW)
	assert_true(
		building_view.contains("func SetDestroying(destroying: bool) -> void:"),
		"建筑视图必须提供幂等入口 SetDestroying。"
	)
	assert_true(
		building_view.contains("_shake.SyncAnchor(icon, _progress_anchor)"),
		"建筑必须在占地缩放确定后重算锚点。"
	)
	assert_true(
		building_view.contains("DestroyShakeAmplitude"),
		"建筑视图必须复用同一份抖动参数资产。"
	)

	var item_scene: String = FileAccess.get_file_as_string(ITEM_SCENE)
	assert_true(
		item_scene.contains("[node name=\"ProgressAnchor\" type=\"Marker2D\" parent=\".\""),
		"地形卡锚点必须挂在根节点下。"
	)
	assert_true(
		not item_scene.contains("name=\"ProgressAnchor\" type=\"Marker2D\" parent=\"Visuals"),
		"地形卡锚点不得留在 Visuals 子树里，否则会被整卡抖动带走。"
	)
	assert_true(
		item_scene.contains("[node name=\"Visuals\" type=\"Sprite2D\" parent=\".\""),
		"整卡抖动的目标节点必须是场景里的 Visuals。"
	)
	var building_scene: String = FileAccess.get_file_as_string(BUILDING_SCENE)
	assert_true(
		building_scene.contains("[node name=\"ProgressAnchor\" type=\"Marker2D\" parent=\".\""),
		"建筑锚点必须与图标同属建筑根节点。"
	)

	var coordinator: String = FileAccess.get_file_as_string(COORDINATOR)
	assert_true(
		coordinator.contains("card.call(\"SetDestroying\", true)"),
		"地形卡长按必须启动抖动。"
	)
	assert_true(
		coordinator.contains("released_card.call(\"SetDestroying\", false)"),
		"地形卡长按结束必须停止抖动。"
	)

	var controller: String = FileAccess.get_file_as_string(BUILDING_CONTROLLER)
	assert_true(
		controller.contains("view.call(\"SetDestroying\", true)"),
		"建筑拆除长按必须启动抖动。"
	)
	assert_true(
		controller.contains("cancelled_view.call(\"SetDestroying\", false)"),
		"建筑拆除结束必须停止抖动。"
	)
	assert_true(
		controller.contains("view.get_node_or_null(\"ProgressAnchor\")"),
		"建筑拆除圆环必须锚定独立锚点而不是会被抖动的图标。"
	)

	var motion: String = FileAccess.get_file_as_string(MOTION_CONFIG_SCRIPT)
	assert_true(motion.contains("DestroyShakeAmplitude"), "动作参数必须提供抖动幅度字段。")
	assert_true(motion.contains("DestroyShakeStepSeconds"), "动作参数必须提供抖动步进字段。")

	# 共享长按端口是四条长按共用的计时与圆环通道，本任务只加视图表现，不得改它的签名。
	var hold: String = FileAccess.get_file_as_string(HOLD_CONTROLLER)
	assert_true(
		hold.contains(
			"func begin_timed_hold(hold_owner: Node, duration_seconds: float, "
			+ "on_completed: Callable, progress_target: Node) -> void:"
		),
		"共享长按端口的公开签名必须保持不变。"
	)


## 抖动的必须是整张卡牌：卡牌节点动、卡框跟着动、卡内图标也跟着动，且偏移不超幅度、停止后精确复位。
func test_card_shakes_as_a_whole() -> void:
	var fixture: Dictionary = _make_shake_fixture()
	var visuals: Sprite2D = fixture["visuals"]
	var player_view: Node2D = fixture["player_view"]
	var icon: Sprite2D = fixture["icon"]
	var shake: DestroyShake = fixture["shake"]
	assert_true(shake != null, "夹具必须能构造抖动组件。")

	var frame_before: Vector2 = player_view.get_screen_transform().origin
	var icon_before: Vector2 = icon.get_screen_transform().origin
	shake.Start()
	assert_true(shake.IsRunning(), "Start 之后抖动必须处于运行状态。")

	var card_moved: bool = false
	var frame_moved: bool = false
	var icon_moved: bool = false
	for step: int in range(16):
		shake.call("_apply_random_offset")
		if not visuals.position.is_equal_approx(FIXTURE_VISUALS_POSITION):
			card_moved = true
		if not player_view.get_screen_transform().origin.is_equal_approx(frame_before):
			frame_moved = true
		if not icon.get_screen_transform().origin.is_equal_approx(icon_before):
			icon_moved = true
		assert_true(
			visuals.position.distance_to(FIXTURE_VISUALS_POSITION)
			<= DestroyShake.DEFAULT_AMPLITUDE + 0.001,
			"整卡抖动偏移不得超过配置幅度。"
		)

	# 三条一起才证明「整张卡牌在抖」：卡牌节点动、卡框跟着动、卡内图标也一起动。
	assert_true(card_moved, "抖动必须真的推动卡牌节点。")
	assert_true(frame_moved, "卡框必须跟着整卡一起抖，而不是只有卡内图标抖。")
	assert_true(icon_moved, "卡内图标必须跟着整卡一起抖。")

	shake.Stop()
	assert_true(
		visuals.position == FIXTURE_VISUALS_POSITION,
		"停止抖动后卡牌必须精确复位到静止坐标。"
	)
	assert_true(not shake.IsRunning(), "停止后不得留下运行中的抖动。")


## 抖动期间圆环锚点必须逐帧静止，同时卡牌确实在抖（否则锚点静止的断言没有意义）。
func test_anchor_stays_still_while_card_shakes() -> void:
	var fixture: Dictionary = _make_shake_fixture()
	var visuals: Sprite2D = fixture["visuals"]
	var anchor: Marker2D = fixture["anchor"]
	var shake: DestroyShake = fixture["shake"]

	var anchor_before: Vector2 = anchor.get_screen_transform().origin
	var card_before: Vector2 = visuals.get_screen_transform().origin
	shake.Start()

	var card_moved: bool = false
	for step: int in range(16):
		shake.call("_apply_random_offset")
		# 用精确相等而不是近似：锚点不在被抖子树内，屏幕坐标必须逐位不变。
		assert_true(
			anchor.get_screen_transform().origin == anchor_before,
			"圆环锚点必须逐帧静止，不得随整卡抖动位移。"
		)
		if not visuals.get_screen_transform().origin.is_equal_approx(card_before):
			card_moved = true

	assert_true(card_moved, "卡牌必须确实在抖，否则圆环静止的断言无法证明解耦生效。")
	shake.Stop()


## 锚点必须复刻图标静止时的右下角，保证圆环屏幕位置与改动前一致。
func test_anchor_reproduces_icon_rest_bottom_right() -> void:
	var fixture: Dictionary = _make_shake_fixture()
	var icon: Sprite2D = fixture["icon"]
	var anchor: Marker2D = fixture["anchor"]
	var root: Node2D = fixture["root"]

	# 锚点必须与图标处于不同父节点，否则「跨父节点换算正确」这条断言会退化成同父节点的巧合。
	assert_true(
		anchor.get_parent() != icon.get_parent(),
		"锚点必须与图标处于不同父节点下，否则无法证明整卡抖动与圆环解耦。"
	)

	# 指示器对 Sprite2D 目标的取点公式；锚点必须落在同一个屏幕点上，
	# 否则「圆环稳定」会以圆环整体位移为代价。
	var legacy_point: Vector2 = icon.get_screen_transform() * icon.get_rect().end
	assert_true(
		anchor.get_screen_transform().origin.is_equal_approx(legacy_point),
		"锚点必须复刻图标静止右下角，圆环位置不得漂移。"
	)

	# 锚点本地坐标也必须等于「图标静止右下角换算到锚点父空间」的结果，
	# 避免父节点变换恰好掩盖换算错误。
	var expected_local: Vector2 = root.to_local(icon.get_global_transform() * icon.get_rect().end)
	assert_true(
		anchor.position.is_equal_approx(expected_local),
		"锚点本地坐标必须等于图标静止右下角在锚点父空间下的换算值。"
	)


## 抖动期间重算锚点（例如长按中刷新视图）不得把当前抖动偏移烘进锚点。
func test_anchor_sync_during_shake_does_not_drift() -> void:
	var fixture: Dictionary = _make_shake_fixture()
	var icon: Sprite2D = fixture["icon"]
	var anchor: Marker2D = fixture["anchor"]
	var shake: DestroyShake = fixture["shake"]

	var anchor_before: Vector2 = anchor.get_screen_transform().origin
	shake.Start()
	for step: int in range(8):
		shake.call("_apply_random_offset")
		shake.SyncAnchor(icon, anchor)
		assert_true(
			anchor.get_screen_transform().origin == anchor_before,
			"抖动期间重算锚点不得把当前抖动偏移烘进锚点。"
		)
	shake.Stop()
	assert_true(
		anchor.get_screen_transform().origin == anchor_before,
		"停止抖动后锚点仍必须停在原处。"
	)


## 启动与停止都幂等；未抖动时的停止不得覆盖夹具里设置的静止坐标。
func test_shake_lifecycle_is_idempotent() -> void:
	var fixture: Dictionary = _make_shake_fixture()
	var visuals: Sprite2D = fixture["visuals"]
	var shake: DestroyShake = fixture["shake"]

	shake.Stop()
	assert_true(
		visuals.position == FIXTURE_VISUALS_POSITION,
		"未抖动时的停止不得把卡牌写成原点。"
	)

	shake.Start()
	shake.Start()
	shake.call("_apply_random_offset")
	shake.Stop()
	shake.Stop()

	assert_true(visuals.position == FIXTURE_VISUALS_POSITION, "重复调用后卡牌必须回到静止坐标。")
	assert_true(not shake.IsRunning(), "重复停止后不得留下运行中的抖动。")


## 不在场景树中的节点不得创建 Tween，也不得被停止流程改写坐标。
func test_destroy_shake_ignores_out_of_tree_target() -> void:
	var target: Sprite2D = Sprite2D.new()
	target.position = Vector2(11, 13)
	track(target)

	var shake: DestroyShake = DestroyShake.new(target)
	shake.Start()
	assert_true(not shake.IsRunning(), "不在场景树中的节点不得创建 Tween。")
	shake.Stop()
	assert_true(target.position == Vector2(11, 13), "未抖动时停止不得改写节点坐标。")


## 判断文本是否匹配给定正则；用于容忍缩进与换行差异的源码形状断言。
##
## 参数 text：被搜索的源码文本；参数 pattern：正则表达式。
## 返回值：匹配到至少一处时为 true。
func _matches(text: String, pattern: String) -> bool:
	var regex: RegEx = RegEx.create_from_string(pattern)
	if regex == null:
		return false
	return regex.search(text) != null


## 构造复刻生产层级的最小夹具。
##
## 层级与生产一致：根节点下是被抖动的卡牌节点，卡牌节点下是卡框，卡框下是图标；
## 锚点则挂在**根节点**下，位于被抖子树之外——这正是圆环不随整卡抖动的前提。
## 卡框用 `Node2D` 而不是生产里的 `Button`：Control 的位置由锚点布局推导，会引入
## 与被测换算无关的布局依赖；这里直接复刻生产卡框的左上角偏移即可。
##
## 返回值：含 root / visuals / player_view / icon / anchor / shake 的字典。
func _make_shake_fixture() -> Dictionary:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var root: Node2D = Node2D.new()
	root.name = FIXTURE_NAME
	tree.root.add_child(root)
	track(root)

	var visuals: Sprite2D = Sprite2D.new()
	visuals.name = "Visuals"
	visuals.position = FIXTURE_VISUALS_POSITION
	root.add_child(visuals)

	var player_view: Node2D = Node2D.new()
	player_view.name = "PlayerView"
	player_view.position = PRODUCTION_PLAYER_VIEW_POSITION
	visuals.add_child(player_view)

	var icon: Sprite2D = Sprite2D.new()
	icon.name = "Icon"
	icon.position = PRODUCTION_ICON_POSITION
	icon.scale = PRODUCTION_ICON_SCALE
	icon.texture = _make_texture()
	player_view.add_child(icon)

	var anchor: Marker2D = Marker2D.new()
	anchor.name = "ProgressAnchor"
	root.add_child(anchor)

	var shake: DestroyShake = DestroyShake.new(visuals)
	shake.SyncAnchor(icon, anchor)

	return {
		"root": root,
		"visuals": visuals,
		"player_view": player_view,
		"icon": icon,
		"anchor": anchor,
		"shake": shake,
	}


## 构造一个固定尺寸的占位纹理，让 `Sprite2D.get_rect()` 有确定的非零尺寸。
##
## 返回值：32×32 的占位纹理。
func _make_texture() -> Texture2D:
	var texture: PlaceholderTexture2D = PlaceholderTexture2D.new()
	texture.size = Vector2(32.0, 32.0)
	return texture
