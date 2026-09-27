@tool
extends McpTestSuite

## 大小地图的共享画布、探索揭示、场景接线和快照扩展契约。

const MAP_LITTLE_SCRIPT: GDScript = preload("res://scripts/map_scripts/UIMapLittle.gd")
const RUN_SNAPSHOT_SCRIPT: GDScript = preload("res://core/gameflow/run_snapshot.gd")
const ROOM_TEXTURE_PATH: String = "res://res/room_icon/Room.png"
const CURRENT_ROOM_TEXTURE_PATH: String = "res://res/room_icon/Room-With-Me.png"


class FakeMapModel:
	extends Node
	signal room_discovered(position: Vector2i)
	signal current_room_changed(position: Vector2i)

	var current_position: Vector2i = Vector2i(2, 2)
	var discovered_rooms: Dictionary = {}
	var scene_to_scene: Dictionary = {
		Vector2i(2, 2): [0, 1, 0, 0],
		Vector2i(2, 3): [0, 0, 1, 1],
		Vector2i(3, 3): [1, 0, 0, 0],
		Vector2i(1, 1): [0, 0, 0, 0],
	}

	func get_discovered_positions() -> Array[Vector2i]:
		var positions: Array[Vector2i] = []
		for value: Variant in discovered_rooms.keys():
			if value is Vector2i:
				positions.append(value)
		positions.sort_custom(
			func(left: Vector2i, right: Vector2i) -> bool:
				return left.x < right.x or (left.x == right.x and left.y < right.y)
		)
		return positions

	func is_room_discovered(position: Vector2i) -> bool:
		return bool(discovered_rooms.get(position, false))

	func are_rooms_connected(first: Vector2i, second: Vector2i) -> bool:
		var offset: Vector2i = second - first
		var directions: Array[Vector2i] = [
			Vector2i(-1, 0), Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1)
		]
		var opposite: Array[int] = [2, 3, 0, 1]
		var direction: int = directions.find(offset)
		if direction < 0:
			return false
		var first_connections: Array = scene_to_scene.get(first, []) as Array
		var second_connections: Array = scene_to_scene.get(second, []) as Array
		return (
			direction < first_connections.size()
			and opposite[direction] < second_connections.size()
			and int(first_connections[direction]) == 1
			and int(second_connections[opposite[direction]]) == 1
		)

	func discover(position: Vector2i) -> bool:
		if discovered_rooms.has(position):
			return false
		discovered_rooms[position] = true
		room_discovered.emit(position)
		return true

	func move_to(position: Vector2i) -> void:
		current_position = position
		current_room_changed.emit(position)


class FakeSnapshotMapModel:
	extends Node
	var map: Array = [["room"]]
	var scene_to_scene: Dictionary = {Vector2i.ZERO: [0, 0, 0, 0]}
	var start_position: Vector2i = Vector2i.ZERO
	var current_position: Vector2i = Vector2i(2, 3)
	var discovered_rooms: Dictionary = {
		Vector2i(2, 3): true,
		Vector2i(1, 3): true,
	}


## 返回编辑器测试入口名称。
## @return 大小地图 UI 契约套件名称。
func suite_name() -> String:
	return "map_ui_contract"


## 画布用 RoomTemplate 显示已探索房间，默认提前显示真实连接桥，并切换当前纹理。
## @return 无返回值。
func test_canvas_reveals_rooms_bridges_and_current_texture() -> void:
	var model: FakeMapModel = track(FakeMapModel.new()) as FakeMapModel
	model.discovered_rooms[Vector2i(2, 2)] = true
	var canvas: Control = _create_canvas(model)
	assert_eq(int(canvas.call("get_generated_room_count")), 1)
	assert_eq(int(canvas.call("get_generated_bridge_count")), 1, "未探索邻居存在真实连接时也要显示桥。")
	assert_eq(int(canvas.call("get_room_bridge_mask", Vector2i(2, 2))), 1 << 1)
	var first_room: Node = canvas.get_node("RoomsContainer/Room_2_2")
	assert_true(first_room.get_node_or_null("RoomView") is Sprite2D)
	assert_true(first_room.get_node_or_null("BridgeContainer") is Node2D)
	assert_eq(
		String(canvas.call("get_room_texture_path", Vector2i(2, 2))), CURRENT_ROOM_TEXTURE_PATH
	)

	assert_true(model.discover(Vector2i(2, 3)))
	assert_eq(int(canvas.call("get_generated_room_count")), 2)
	assert_eq(int(canvas.call("get_generated_bridge_count")), 2, "新房间揭示后还要显示它通往未探索下方房间的桥。")
	assert_false(model.discover(Vector2i(2, 3)))
	canvas.call("refresh_discovered_rooms")
	assert_eq(int(canvas.call("get_generated_bridge_count")), 2, "重复刷新不得重复生成桥。")

	model.move_to(Vector2i(2, 3))
	assert_eq(String(canvas.call("get_room_texture_path", Vector2i(2, 2))), ROOM_TEXTURE_PATH)
	assert_eq(
		String(canvas.call("get_room_texture_path", Vector2i(2, 3))), CURRENT_ROOM_TEXTURE_PATH
	)

	assert_true(model.discover(Vector2i(1, 1)))
	assert_eq(int(canvas.call("get_generated_room_count")), 3)
	assert_eq(int(canvas.call("get_generated_bridge_count")), 2, "无连接房间不得生成桥。")
	assert_true(model.discover(Vector2i(3, 3)))
	assert_eq(int(canvas.call("get_generated_bridge_count")), 2)
	var room_nodes: Dictionary = canvas.get_node("RoomsContainer").get("_room_nodes")
	var horizontal_owner: Node = room_nodes[Vector2i(2, 2)] as Node
	var vertical_owner: Node = room_nodes[Vector2i(2, 3)] as Node
	var horizontal_bridge: Sprite2D = (
		horizontal_owner.get_node("BridgeContainer").call("get_bridge_node", 1) as Sprite2D
	)
	var vertical_bridge: Sprite2D = (
		vertical_owner.get_node("BridgeContainer").call("get_bridge_node", 2) as Sprite2D
	)
	assert_eq(horizontal_bridge.rotation, 0.0, "水平桥不得旋转。")
	var vertical_rotation: float = vertical_bridge.rotation
	assert_true(
		is_equal_approx(vertical_rotation, PI / 2.0),
		"垂直桥必须旋转 90 度，实际为 %s。" % str(rad_to_deg(vertical_rotation))
	)


## 桥显示策略可切回“仅连接双方都已探索”，并能恢复默认提前显示模式。
## @return 无返回值。
func test_canvas_can_switch_bridge_visibility_mode() -> void:
	var model: FakeMapModel = track(FakeMapModel.new()) as FakeMapModel
	model.discovered_rooms[Vector2i(2, 2)] = true
	var canvas: Control = _create_canvas(model)
	assert_eq(int(canvas.call("get_generated_bridge_count")), 1)
	assert_true(bool(canvas.call("set_bridge_visibility_mode", 1)))
	assert_eq(int(canvas.call("get_generated_bridge_count")), 0)
	assert_true(bool(canvas.call("set_bridge_visibility_mode", 0)))
	assert_eq(int(canvas.call("get_generated_bridge_count")), 1)
	assert_false(bool(canvas.call("set_bridge_visibility_mode", 99)))


## 小地图和大地图使用独立画布节点，但绑定同一 Model 后生成结果一致。
## @return 无返回值。
func test_two_canvas_instances_are_independent_and_consistent() -> void:
	var model: FakeMapModel = track(FakeMapModel.new()) as FakeMapModel
	model.discovered_rooms = {Vector2i(2, 2): true, Vector2i(2, 3): true}
	var first: Control = _create_canvas(model)
	var second: Control = _create_canvas(model)
	assert_ne(first, second)
	assert_ne(first.get_node("RoomsContainer"), second.get_node("RoomsContainer"))
	assert_eq(first.call("get_generated_room_count"), second.call("get_generated_room_count"))
	assert_eq(first.call("get_generated_bridge_count"), second.call("get_generated_bridge_count"))
	first.position = Vector2(10, 20)
	assert_ne(first.position, second.position, "两个 View 必须能独立平移画布。")


## 三张用户场景必须按约定嵌套 WorldMapCanvas，MapControl 保留兼容节点与 CanvasLayer。
## @return 无返回值。
func test_scene_structure_uses_shared_canvas_and_compatibility_nodes() -> void:
	var mini: Node = (
		track((load("res://scenes/map_scenes/map_view/MiniMap.tscn") as PackedScene).instantiate())
		as Node
	)
	var large: Node = (
		track((load("res://scenes/map_scenes/map_view/LargeMap.tscn") as PackedScene).instantiate())
		as Node
	)
	var room_template: Node = (
		track(
			(
				(load("res://scenes/map_scenes/map_view/RoomTemplate.tscn") as PackedScene)
				. instantiate()
			)
		)
		as Node
	)
	var map_control: Node = (
		track((load("res://scenes/map_scenes/map_control.tscn") as PackedScene).instantiate())
		as Node
	)
	assert_true(mini.get_node_or_null("MaskContainer/CanvasViewport/WorldMapCanvas") != null)
	assert_true(large.get_node_or_null("ViewportControl/WorldMapCanvas") != null)
	assert_true(room_template.has_method("configure_room"))
	assert_true(room_template.get_node_or_null("RoomView") is Sprite2D)
	assert_true(room_template.get_node_or_null("RoomView").has_method("set_current_room"))
	assert_true(room_template.get_node_or_null("BridgeContainer") is Node2D)
	assert_true(room_template.get_node_or_null("BridgeContainer").has_method("configure_bridges"))
	assert_true(map_control.get_node_or_null("CanvasLayer/MiniMap") != null)
	assert_true(map_control.get_node_or_null("LargeMap") != null)
	assert_true(map_control.get_node_or_null("MapLittle") != null)
	assert_true(map_control.get_node_or_null("CanvasLayer") is CanvasLayer)
	var old_adapter: Node = MAP_LITTLE_SCRIPT.new()
	track(old_adapter)
	for method_name: StringName in [
		&"build_little_map",
		&"change_this_cell_color",
		&"return_this_cell_color",
		&"update_current_position",
	]:
		assert_true(old_adapter.has_method(method_name), "旧动态入口必须保留：%s" % method_name)


## RunSnapshot 必须稳定编码探索集合，并能从 payload 恢复且去重。
## @return 无返回值。
func test_run_snapshot_round_trips_discovered_rooms() -> void:
	var snapshot: Node = RUN_SNAPSHOT_SCRIPT.new()
	track(snapshot)
	var model := FakeSnapshotMapModel.new()
	track(model)
	var encoded: Array = snapshot.call("_encode_positions", model.discovered_rooms)
	assert_eq(encoded, ["1,3", "2,3"])

	assert_true(
		bool(
			(
				snapshot
				. call(
					"apply_save_data",
					{
						"current": "2,3",
						"discovered_rooms": ["2,3", "broken", "1,3", "2,3", "1,not-a-number"],
					}
				)
			)
		)
	)
	assert_eq(
		snapshot.call("GetDiscoveredRooms"), [Vector2i(2, 3), Vector2i(1, 3)], "恢复时必须保留首次出现顺序并去重。"
	)


func _create_canvas(model: FakeMapModel) -> Control:
	var canvas_scene: PackedScene = (
		ResourceLoader.load(
			"res://scenes/map_scenes/map_view/WorldMapCanvas.tscn",
			"PackedScene",
			ResourceLoader.CACHE_MODE_IGNORE_DEEP
		)
		as PackedScene
	)
	var canvas: Control = track(canvas_scene.instantiate()) as Control
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	tree.root.add_child(canvas)
	assert_true(bool(canvas.call("bind_model", model)))
	return canvas
