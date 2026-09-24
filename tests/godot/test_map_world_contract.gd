@tool
extends McpTestSuite

## 无缝地图的数据、状态信号、资源缓存和视图窗口契约。
const MODEL: GDScript = preload("res://core/map/map_world_model.gd")
const VIEW: GDScript = preload("res://scripts/map_scripts/UIMapWorldView.gd")
const CONTROLLER: GDScript = preload("res://scripts/map_scripts/UIMapWorldController.gd")
const ROOM: String = "res://scenes/map_scenes/map_env/normal/main/clear_creek.tscn"
const OFFSETS: Array[Vector2i] = [Vector2i(-1, 0), Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1)]

## 返回编辑器测试入口名称。
## @return 无缝地图契约套件名称。
func suite_name() -> String:
	return "map_world_contract"


func _model() -> Node:
	var model: Node = track(MODEL.new()) as Node
	var grid: Array = []
	var roads: Dictionary = {}
	var connections: Dictionary = {}
	for row in range(5):
		grid.append(["room", "room", "room", "room", "room"])
		for column in range(5):
			var position := Vector2i(row, column)
			roads[position] = ROOM
			connections[position] = [int(row > 0), int(column < 4), int(row < 4), int(column > 0)]
	model.set("map", grid)
	model.set("map_road_in_map", roads)
	model.set("scene_to_scene", connections)
	model.set("current_position", Vector2i(2, 2))
	model.set("start_position", Vector2i(2, 2))
	return model


## 四个方向掩码、双向连接和坐标轴必须沿用地图生成器约定。
## @return 无返回值。
func test_direction_masks_and_negative_world_coordinates() -> void:
	var model: Node = _model()
	for direction in range(4):
		var context: RoomContext = model.call("get_room_context", Vector2i(2, 2))
		assert_true(context.has_connection(direction))
		var neighbor: Vector2i = Vector2i(2, 2) + OFFSETS[direction]
		assert_true(bool(model.call("are_rooms_connected", Vector2i(2, 2), neighbor)))
		assert_eq(model.call("world_origin_for", neighbor), Vector2(OFFSETS[direction].y * 1280, OFFSETS[direction].x * 720))
	assert_eq(model.call("map_position_for_world", Vector2(-0.01, -0.01)), Vector2i(1, 1))
	assert_eq(model.call("map_position_for_world", Vector2(1279.99, 719.99)), Vector2i(2, 2))
	assert_eq(model.call("map_position_for_world", Vector2(1280, 720)), Vector2i(3, 3))
	var context := RoomContext.new()
	assert_false(context.has_connection(-1))
	assert_false(context.has_connection(4))


## 无效坐标、非相邻、单向连接和资源缺失均不得改变状态或成功信号。
## @return 无返回值。
func test_rejected_moves_preserve_state_and_signal_count() -> void:
	var model: Node = _model()
	var observed: Array[Vector2i] = []
	model.connect("current_room_changed", func(position: Vector2i) -> void: observed.append(position))
	for invalid in [Vector2i(-1, 2), Vector2i(5, 2), Vector2i(0, 0), Vector2i(3, 3)]:
		assert_false(bool(model.call("try_enter_room", invalid)))
	var grid: Array = model.get("map")
	grid[1][2] = "void"
	assert_false(bool(model.call("try_enter_room", Vector2i(1, 2))))
	var connections: Dictionary = model.get("scene_to_scene")
	connections[Vector2i(2, 3)] = [1, 1, 1, 0]
	assert_false(bool(model.call("try_enter_room", Vector2i(2, 3))), "单向连接不得开放。")
	var roads: Dictionary = model.get("map_road_in_map")
	roads[Vector2i(3, 2)] = "res://missing_room_for_contract.tscn"
	assert_false(bool(model.call("try_enter_room", Vector2i(3, 2))))
	assert_eq(model.get("current_position"), Vector2i(2, 2))
	assert_eq(observed.size(), 0)
	assert_true(bool(model.call("try_enter_room", Vector2i(2, 1))))
	assert_eq(observed, [Vector2i(2, 1)])
	assert_true(bool(model.call("try_enter_room", Vector2i(2, 1))))
	assert_eq(observed.size(), 1, "重复进入当前房间不得重发成功信号。")


## 每个坐标只创建一个资源；同路径跨坐标共享 PackedScene，上下文不包含节点。
## @return 无返回值。
func test_resource_identity_and_context_data_boundary() -> void:
	var model: Node = _model()
	var first: MapSceneResource = model.call("get_scene_resource", Vector2i(2, 2))
	var other: MapSceneResource = model.call("get_scene_resource", Vector2i(2, 3))
	assert_eq(first, model.call("get_scene_resource", Vector2i(2, 2)))
	assert_ne(first, other)
	assert_eq(first.packed_scene, other.packed_scene)
	var context: RoomContext = model.call("get_room_context", Vector2i(2, 2))
	assert_eq(context.scene_resource, first)
	assert_eq(context.room_position, Vector2i(2, 2))
	assert_eq(context.room_size, Vector2(1280, 720))
	for property in context.get_property_list():
		assert_false(context.get(property["name"]) is Node, "上下文不得含运行时节点。")
	assert_eq((model.call("get_window_positions", Vector2i.ZERO) as Array).size(), 4)
	assert_eq((model.call("get_window_positions", Vector2i(2, 2)) as Array).size(), 9)


## 窗口外节点实际释放，回访创建新节点并复用原场景资源。
## @return 无返回值。
func test_window_releases_nodes_and_reuses_resources_on_return() -> void:
	# 编辑器测试器同步回收夹具，不会等待下一帧；必须在游戏中 await 调用本用例。
	if Engine.is_editor_hint():
		skip("节点释放需要跨帧；请在运行中的游戏通过 game_eval await 执行本用例。")
		return
	var model: Node = _model()
	var view: Node2D = track(VIEW.new()) as Node2D
	view.set("map_world_model", model)
	view.call("_activate_window", Vector2i(2, 2))
	view.call("_set_current_scene", Vector2i(2, 2), false)
	assert_eq((view.call("get_active_positions") as Array).size(), 9)
	var instances: Dictionary = view.get("active_instances")
	var old_room: Node2D = instances[Vector2i(1, 1)]
	var old_id: int = old_room.get_instance_id()
	var old_resource: Resource = model.call("get_scene_resource", Vector2i(1, 1))
	view.call("_activate_window", Vector2i(3, 3))
	assert_false(instances.has(Vector2i(1, 1)))
	assert_true(old_room.is_queued_for_deletion())
	await (Engine.get_main_loop() as SceneTree).process_frame
	assert_false(is_instance_valid(old_room), "窗口外旧房间必须真正释放。")
	view.call("_activate_window", Vector2i(2, 2))
	assert_ne((instances[Vector2i(1, 1)] as Node).get_instance_id(), old_id)
	assert_eq(model.call("get_scene_resource", Vector2i(1, 1)), old_resource)
	assert_eq((view.get("map_scene") as Dictionary).size(), 9)
	assert_eq(view.get("current_position"), Vector2i(2, 2))
	assert_true(view.get("current_scene") != null)


## Controller 只观察连续位置：有效跨界更新地图，无连接方向拒绝且不回写玩家。
## @return 无返回值。
func test_controller_observes_player_without_teleporting() -> void:
	var model: Node = _model()
	var controller: Node = track(CONTROLLER.new()) as Node
	var player := track(Node2D.new()) as Node2D
	controller.set("_map_world_model", model)
	controller.set("_player", player)
	player.position = Vector2(1281, 352)
	controller.call("_process", 0.016)
	assert_eq(model.get("current_position"), Vector2i(2, 3))
	assert_eq(player.position, Vector2(1281, 352))
	player.position = Vector2(1281, -1)
	var connections: Dictionary = model.get("scene_to_scene")
	connections[Vector2i(2, 3)] = [0, 1, 1, 1]
	controller.call("_process", 0.016)
	assert_eq(model.get("current_position"), Vector2i(2, 3))
	assert_eq(player.position, Vector2(1281, -1))


## Model 的真实信号必须刷新 View 兼容字段，并向已有消费者广播一次。
## @return 无返回值。
func test_model_signal_updates_current_room_compatibility_surface() -> void:
	# 信号会触发真实房间配置，编辑器中的非工具脚本占位实例不能执行该链路。
	if Engine.is_editor_hint():
		skip("信号兼容需要真实房间实例；请在运行中的游戏通过 game_eval await 执行本用例。")
		return
	var model: Node = _model()
	var view: Node2D = track(VIEW.new()) as Node2D
	view.set("map_world_model", model)
	model.connect("current_room_changed", Callable(view, "_on_model_current_room_changed"))
	view.call("_activate_window", Vector2i(2, 2))
	var notifications: Array = []
	view.connect("on_entered_room", func(position: Vector2i, scene: Node2D) -> void:
		notifications.append([position, scene])
	)
	assert_true(bool(model.call("try_enter_room", Vector2i(2, 3))))
	assert_eq(view.get("current_position"), Vector2i(2, 3))
	assert_eq(notifications.size(), 1)
	if notifications.size() != 1:
		return
	assert_eq(notifications[0][0], Vector2i(2, 3))
	assert_eq(notifications[0][1], view.get("current_scene"))
	assert_eq((view.get("active_instances") as Dictionary).size(), 9)
	assert_eq((view.get("map_scene") as Dictionary)[Vector2i(2, 3)], view.get("current_scene"))
	assert_eq((view.get("current_scene") as Node2D).position, Vector2(1280, 0))


## 用户确认的初始出生点写在 Main 场景；跨房 Controller 仍不改玩家位置。
## @return 无返回值。
func test_main_authors_initial_spawn_inside_start_room() -> void:
	var packed := load("res://scenes/Main.tscn") as PackedScene
	assert_true(packed != null, "Main 必须可加载。")
	if packed == null:
		return
	var state: SceneState = packed.get_state()
	var found: bool = false
	for index in range(state.get_node_count()):
		if String(state.get_node_path(index)).trim_prefix("./") != "PlayerChar":
			continue
		for property_index in range(state.get_node_property_count(index)):
			if state.get_node_property_name(index, property_index) == &"position":
				found = true
				assert_eq(state.get_node_property_value(index, property_index), Vector2(640, 360))
	assert_true(found, "Main 必须显式配置初始出生点。")
