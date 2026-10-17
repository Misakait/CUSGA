@tool
extends McpTestSuite

## 长按破坏抖动契约套件。
##
## 锁定四件事：抖动只作用于贴图节点、进度圆环锚点在抖动期间逐帧静止、
## 锚点复刻的屏幕位置与「直接锚定图标」完全一致、启动与停止幂等且停止后贴图精确复位。
##
## 两个环境约束决定了本套件的形状：
## 1. `item_view.gd` / `building_view.gd` 不是 `@tool`，在编辑器测试运行器里实例化后是
##    placeholder instance，实例方法不可调用；`building_view.tscn` 还被 `building_controller.gd`
##    preload 缓存，场景改动在本进程内不保证可见。因此这里不实例化生产场景，
##    而是用等价的引擎节点夹具直接驱动生产组件，真实场景与真实长按由运行期 `game_eval` 覆盖。
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
## 夹具节点名前缀；运行器会清理带 `_McpTest` 前缀的残留节点。
const FIXTURE_NAME: String = "_McpTestDestroyShakeFixture"


## 提供 GodotAI 使用的稳定套件名称。
func suite_name() -> String:
	return "destroy_hold_shake"


## 源码与场景形状：抖动入口、独立锚点、两个调用点与配置字段都必须留在生产文件里。
func test_source_contracts() -> void:
	var item_view: String = FileAccess.get_file_as_string(ITEM_VIEW)
	assert_true(
		item_view.contains("func SetDestroying(destroying: bool) -> void:"),
		"地形卡视图必须提供幂等入口 SetDestroying。"
	)
	assert_true(
		item_view.contains("return _progress_anchor"),
		"GetProgressAnchor 必须返回不参与抖动的锚点，否则圆环会随图标一起抖。"
	)
	assert_true(
		item_view.contains("DestroyShake.SyncAnchor(_icon, _progress_anchor)"),
		"地形卡必须在刷新视图时重算锚点。"
	)
	assert_true(
		item_view.contains("DestroyShake.new("),
		"地形卡视图必须构造抖动组件。"
	)

	var building_view: String = FileAccess.get_file_as_string(BUILDING_VIEW)
	assert_true(
		building_view.contains("func SetDestroying(destroying: bool) -> void:"),
		"建筑视图必须提供幂等入口 SetDestroying。"
	)
	assert_true(
		building_view.contains("DestroyShake.SyncAnchor(icon, _progress_anchor)"),
		"建筑必须在占地缩放确定后重算锚点。"
	)
	assert_true(
		building_view.contains("DestroyShakeAmplitude"),
		"建筑视图必须复用同一份抖动参数资产。"
	)

	# 锚点必须挂在被抖动图标所在的同一个父节点下，否则 SyncAnchor 的换算不成立。
	var item_scene: String = FileAccess.get_file_as_string(ITEM_SCENE)
	assert_true(
		item_scene.contains("[node name=\"ProgressAnchor\" type=\"Marker2D\" parent=\"Visuals/PlayerView\""),
		"地形卡锚点必须与图标同属 Visuals/PlayerView。"
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


## 抖动必须把图标推离静止位置且偏移不超过配置幅度；停止后精确复位。
func test_shake_jitters_and_restores_exactly() -> void:
	var fixture: Dictionary = _make_shake_fixture()
	var icon: Sprite2D = fixture["icon"]
	var shake: DestroyShake = fixture["shake"]
	assert_true(shake != null, "夹具必须能构造抖动组件。")

	shake.Start()
	assert_true(shake.IsRunning(), "Start 之后抖动必须处于运行状态。")

	var moved: bool = false
	for step: int in range(16):
		shake.call("_apply_random_offset")
		var offset: float = icon.position.distance_to(PRODUCTION_ICON_POSITION)
		if offset > 0.001:
			moved = true
		assert_true(
			offset <= DestroyShake.DEFAULT_AMPLITUDE + 0.001,
			"抖动偏移不得超过配置幅度。"
		)

	assert_true(moved, "抖动必须真的把图标推离静止位置。")

	shake.Stop()
	assert_true(
		icon.position == PRODUCTION_ICON_POSITION,
		"停止抖动后图标必须精确复位到静止坐标。"
	)
	assert_true(not shake.IsRunning(), "停止后不得留下运行中的抖动。")


## 抖动期间圆环锚点必须逐帧静止，同时图标确实在抖（否则锚点静止的断言没有意义）。
func test_anchor_stays_still_while_icon_shakes() -> void:
	var fixture: Dictionary = _make_shake_fixture()
	var icon: Sprite2D = fixture["icon"]
	var anchor: Marker2D = fixture["anchor"]
	var shake: DestroyShake = fixture["shake"]

	var anchor_before: Vector2 = anchor.get_screen_transform().origin
	var icon_before: Vector2 = icon.get_screen_transform().origin
	shake.Start()

	var icon_moved: bool = false
	for step: int in range(16):
		shake.call("_apply_random_offset")
		assert_true(
			anchor.get_screen_transform().origin.is_equal_approx(anchor_before),
			"圆环锚点必须逐帧静止，不得随图标抖动位移。"
		)
		if not icon.get_screen_transform().origin.is_equal_approx(icon_before):
			icon_moved = true

	assert_true(icon_moved, "图标必须确实在抖，否则圆环静止的断言无法证明解耦生效。")
	shake.Stop()


## 锚点必须复刻图标静止时的右下角，保证圆环屏幕位置与改动前一致。
func test_anchor_reproduces_icon_rest_bottom_right() -> void:
	var fixture: Dictionary = _make_shake_fixture()
	var icon: Sprite2D = fixture["icon"]
	var anchor: Marker2D = fixture["anchor"]

	# 指示器对 Sprite2D 目标的取点公式；锚点必须落在同一个屏幕点上，
	# 否则「圆环稳定」会以圆环整体位移为代价。
	var legacy_point: Vector2 = icon.get_screen_transform() * icon.get_rect().end
	var anchor_point: Vector2 = anchor.get_screen_transform().origin
	assert_true(
		anchor_point.is_equal_approx(legacy_point),
		"锚点必须复刻图标静止右下角，圆环位置不得漂移。"
	)

	# 锚点自身坐标也必须等于同一父空间下的换算结果，避免父节点变换掩盖错误。
	var expected_local: Vector2 = icon.position + icon.scale * icon.get_rect().end
	assert_true(
		anchor.position.is_equal_approx(expected_local),
		"锚点本地坐标必须等于图标静止右下角。"
	)


## 启动与停止都幂等；未抖动时的停止不得覆盖夹具里设置的静止坐标。
func test_shake_lifecycle_is_idempotent() -> void:
	var fixture: Dictionary = _make_shake_fixture()
	var icon: Sprite2D = fixture["icon"]
	var shake: DestroyShake = fixture["shake"]

	shake.Stop()
	assert_true(
		icon.position == PRODUCTION_ICON_POSITION,
		"未抖动时的停止不得把图标写成原点。"
	)

	shake.Start()
	shake.Start()
	shake.call("_apply_random_offset")
	shake.Stop()
	shake.Stop()

	assert_true(icon.position == PRODUCTION_ICON_POSITION, "重复调用后图标必须回到静止坐标。")
	assert_true(not shake.IsRunning(), "重复停止后不得留下运行中的抖动。")


## 不在场景树中的贴图节点不得创建 Tween，也不得被停止流程改写坐标。
func test_destroy_shake_ignores_out_of_tree_sprite() -> void:
	var sprite: Sprite2D = Sprite2D.new()
	sprite.position = Vector2(11, 13)
	track(sprite)

	var shake: DestroyShake = DestroyShake.new(sprite)
	shake.Start()
	assert_true(not shake.IsRunning(), "不在场景树中的贴图节点不得创建 Tween。")
	shake.Stop()
	assert_true(sprite.position == Vector2(11, 13), "未抖动时停止不得改写贴图坐标。")


## 构造复刻生产层级的最小夹具：同一父节点下的图标与锚点，图标坐标与缩放同生产一致。
##
## 返回值：含 icon / anchor / shake 三个键的字典。
func _make_shake_fixture() -> Dictionary:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var fixture: Node2D = Node2D.new()
	fixture.name = FIXTURE_NAME
	tree.root.add_child(fixture)
	track(fixture)

	var icon: Sprite2D = Sprite2D.new()
	icon.name = "Icon"
	icon.position = PRODUCTION_ICON_POSITION
	icon.scale = PRODUCTION_ICON_SCALE
	icon.texture = _make_texture()
	fixture.add_child(icon)

	var anchor: Marker2D = Marker2D.new()
	anchor.name = "ProgressAnchor"
	fixture.add_child(anchor)

	DestroyShake.SyncAnchor(icon, anchor)

	return {
		"icon": icon,
		"anchor": anchor,
		"shake": DestroyShake.new(icon),
	}


## 构造一个固定尺寸的占位纹理，让 `Sprite2D.get_rect()` 有确定的非零尺寸。
##
## 返回值：32×32 的占位纹理。
func _make_texture() -> Texture2D:
	var texture: PlaceholderTexture2D = PlaceholderTexture2D.new()
	texture.size = Vector2(32.0, 32.0)
	return texture
