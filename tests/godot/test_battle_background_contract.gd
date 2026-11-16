@tool
extends McpTestSuite

## 五行背景契约：资源映射、默认回退、当前房间来源与战斗过场的配置时序。

## 背景组件使用正式贴图，断言实际纹理而不只检查群系字符串。
const BACKGROUND: GDScript = preload("res://scripts/battle_scripts/battle_background.gd")
## 协调器保留真实背景配置协议，地图和过场使用轻量替身隔离其它玩法。
const COORDINATOR: GDScript = preload("res://core/gameflow/world_interaction_coordinator.gd")
## 地图资源容器保持生产字段面，不需要实例化完整地图瓦片。
const MAP_RESOURCE: GDScript = preload("res://resources/map/map_scene_resource.gd")


## 仅提供当前坐标与资源查询，故意不持有任何房间 View 缓存。
class MapModelStub extends Node:
	## 当前房间坐标；测试切到第二个坐标以复现过场中的换房。
	var current_position: Vector2i = Vector2i.ZERO
	## 两个坐标的资源配置，证明解析器依赖当前坐标而非字典顺序。
	var rooms: Dictionary[Vector2i, Resource] = {}


	## 查询指定坐标的地图资源；参数 position：房间坐标；返回值：资源或 null。
	func get_scene_resource(position: Vector2i) -> Resource:
		return rooms.get(position) as Resource


## 战斗替身保留结束信号，以经过正式 _enter_combat 的动态连接流程。
class BattleStub extends Node2D:
	## 不触发实际胜负，只满足正式战斗实例的信号协议。
	signal battle_ended(is_victory: bool)


## 复用正式进入战斗流程，只替换动画、战斗实体和世界视图副作用。
class EntryProbe extends "res://core/gameflow/world_interaction_coordinator.gd":
	## 淡出时切换当前坐标，用于验证背景来源已在过场之前锁定。
	var model_stub: MapModelStub


	func _ready() -> void:
		pass


	func _exit_tree() -> void:
		pass


	func _is_run_ending() -> bool:
		return false


	func _cancel_active_hold() -> void:
		pass


	func _fade_out() -> void:
		model_stub.current_position = Vector2i.ONE


	func _fade_in() -> void:
		pass


	func _set_world_view_visible(_visible: bool) -> void:
		pass


	func _create_battle_instance(_deck: Array[Resource], _monsters: Array[Resource]) -> Node:
		# 正式背景组件保持非 tool 脚本，与运行时战斗的调用面一致。
		var battle: BattleStub = BattleStub.new()
		# 复用正式组件，避免替身自己实现映射而漏掉动态调用错误。
		var background: Sprite2D = BACKGROUND.new() as Sprite2D
		background.name = "测试背景"
		battle.add_child(background)
		return battle


## 返回稳定套件名；返回值：五行战斗背景契约名称。
func suite_name() -> String:
	return "battle_background_contract"


## 五种群系的不同类别场景均必须选中对应素材，并完整覆盖设计视口。
## 返回值：无。
func test_five_biomes_use_distinct_textures_and_fill_viewport() -> void:
	# 金行目录名为 gold，素材名为 metal，不能把两个词误认为同一个资源键。
	var expected_files: Dictionary[String, String] = {
		"gold": "metal", "wood": "wood", "water": "water", "fire": "fire", "earth": "earth",
	}
	# 单个实例连续切换，能同时发现上一次背景残留的问题。
	var background: Sprite2D = track(BACKGROUND.new()) as Sprite2D
	for biome: String in expected_files:
		for category: String in ["main", "secondary", "transmitting", "market"]:
			background.call("configure_for_map", "res://scenes/map_scenes/map_env/%s/%s/room.tscn" % [biome, category])
			assert_eq(background.texture.resource_path, "res://res/background/battle/%s.png" % expected_files[biome], "群系必须选择自己的贴图。")
			assert_eq(background.position, Vector2(640, 360), "背景必须以设计视口为中心。")
			assert_true((background.texture.get_size() * background.scale).is_equal_approx(Vector2(1280, 720)), "不同原图尺寸均应完整覆盖视口。")
			assert_eq(background.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST, "像素背景必须使用最近邻采样。")


## 普通房间、未知路径与独立战斗应回退；文件名中的元素词不能覆盖群系目录。
## 返回值：无。
func test_unknown_maps_reset_to_wood_and_ready_keeps_configuration() -> void:
	# 先配置火行，再模拟入树，防止 _ready 把正确背景重置为默认背景。
	var background: Sprite2D = track(BACKGROUND.new()) as Sprite2D
	background.call("configure_for_map", "res://scenes/map_scenes/map_env/fire/main/volcano.tscn")
	background.call("_ready")
	assert_eq(background.get("current_biome"), "fire", "入树不得覆盖提前注入的背景。")
	for path: String in ["", "res://scenes/map_scenes/map_env/normal/main/fire_valley.tscn", "res://other/water/room.tscn"]:
		background.call("configure_for_map", path)
		assert_eq(background.get("current_biome"), "wood", "未知或普通地图必须回到默认背景。")
		assert_eq(background.texture.resource_path, "res://res/background/battle/wood.png", "回退不能留下上一次火行贴图。")


## 背景解析始终使用 Model 当前坐标，无模型时安全返回空串。
## 返回值：无。
func test_current_room_resource_is_authoritative() -> void:
	# 不启动协调器，避免绑定真实世界交互或 Autoload。
	var coordinator: Node = track(COORDINATOR.new()) as Node
	coordinator.set("MapWorldModelPath", ^"MapWorldModel")
	assert_eq(coordinator.call("_get_current_map_scene_path"), "", "独立场景没有地图模型时应允许默认背景。")
	# 第一个条目为金行，切换坐标后必须读取水行，不能取缓存中的首项。
	var model: MapModelStub = _make_model()
	coordinator.add_child(model)
	model.current_position = Vector2i.ONE
	assert_eq(coordinator.call("_get_current_map_scene_path"), model.rooms[Vector2i.ONE].scene_path, "必须按当前房间坐标读取资源。")


## 正式战斗入口应在淡出前捕获地图，并通过动态协议在首帧前配置背景。
## 返回值：无。
func test_entry_captures_room_before_transition() -> void:
	# 使用测试世界持有所有节点，结束时统一释放，不污染编辑器打开的场景。
	var world: Node = track(Node.new()) as Node
	# 淡出期间将发生金行到水行的坐标变化。
	var model: MapModelStub = _make_model()
	world.add_child(model)
	# 替身只替换过场副作用，进入战斗方法和背景协议均来自生产脚本。
	var coordinator: EntryProbe = EntryProbe.new()
	coordinator.model_stub = model
	coordinator.MapWorldModelPath = ^"../MapWorldModel"
	coordinator.set("_world_root", world)
	world.add_child(coordinator)
	# 进入树是正式入口取得视口与挂入战斗实例的前提。
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	tree.root.add_child(world)
	# 动态调用也必须传入类型匹配的资源数组，不能用无元素类型的 Array 替代。
	var empty_resources: Array[Resource] = []
	assert_true(await coordinator.call("_enter_combat", empty_resources, empty_resources), "有合法地图时应成功进入战斗。")
	# 读取真实背景组件，而不是测试替身记录的参数。
	var battle: Node = coordinator.get("_active_battle") as Node
	var background: Sprite2D = battle.get_node("测试背景") as Sprite2D
	assert_eq(model.current_position, Vector2i.ONE, "淡出替身必须实际改变当前房间。")
	assert_eq(background.get("current_biome"), "gold", "背景必须属于遭遇开始时的金行地图。")
	assert_eq(background.texture.resource_path, "res://res/background/battle/metal.png", "动态配置应已写入实际贴图。")


## 构造两个群系的地图模型；返回值：尚未入树的模型替身。
func _make_model() -> MapModelStub:
	# 使用生产地图资源字段，保持与 Model 查询结果一致。
	var gold: Resource = MAP_RESOURCE.new()
	gold.set("scene_path", "res://scenes/map_scenes/map_env/gold/main/mine.tscn")
	# 第二个房间与第一个使用不同素材，能检测错取缓存或过晚读取当前坐标。
	var water: Resource = MAP_RESOURCE.new()
	water.set("scene_path", "res://scenes/map_scenes/map_env/water/secondary/lake.tscn")
	# 节点名沿用生产默认路径，父节点按测试隔离需要调整。
	var model: MapModelStub = MapModelStub.new()
	model.name = "MapWorldModel"
	model.rooms = {Vector2i.ZERO: gold, Vector2i.ONE: water}
	return model
