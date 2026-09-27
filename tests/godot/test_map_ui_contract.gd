@tool
extends McpTestSuite

## 大小地图的共享画布、探索揭示、场景接线和快照扩展契约。

const MAP_LITTLE_SCRIPT: GDScript = preload("res://scripts/map_scripts/UIMapLittle.gd")
const RUN_SNAPSHOT_SCRIPT: GDScript = preload("res://core/gameflow/run_snapshot.gd")
const ROOM_TEXTURE_PATH: String = "res://res/room_icon/Room.png"
const CURRENT_ROOM_TEXTURE_PATH: String = "res://res/room_icon/Room-With-Me.png"
const VERTICAL_BRIDGE_TEXTURE_PATH: String = "res://res/room_icon/Room_Bridge_V.png"
const MARKER_CONFIG_SCRIPT: GDScript = preload("res://resources/map/map_marker_config.gd")
const MARKER_CONTROLLER_SCRIPT: GDScript = preload(
	"res://scripts/map_scripts/UIMapMarkerController.gd"
)


class FakeMapModel:
	extends Node
	signal room_discovered(position: Vector2i)
	signal current_room_changed(position: Vector2i)
	signal markers_changed

	var current_position: Vector2i = Vector2i(2, 2)
	var discovered_rooms: Dictionary = {}
	var scene_to_scene: Dictionary = {
		Vector2i(2, 2): [0, 1, 0, 0],
		Vector2i(2, 3): [0, 0, 1, 1],
		Vector2i(3, 3): [1, 0, 0, 0],
		Vector2i(1, 1): [0, 0, 0, 0],
	}
	var markers: Dictionary = {}
	var room_size: Vector2 = Vector2(1280.0, 720.0)

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

	func get_marker_snapshot() -> Array[Dictionary]:
		var snapshot: Array[Dictionary] = []
		for record: Dictionary in markers.values():
			snapshot.append(record.duplicate())
		return snapshot

	func add_test_marker(
		marker_id: StringName, config: Resource, logical_position: Vector2
	) -> void:
		markers[marker_id] = {
			"id": marker_id,
			"source_kind": &"player",
			"marker_type": config.get("marker_type"),
			"logical_position": logical_position,
			"config": config,
		}
		markers_changed.emit()

	func register_source_marker(
		marker_id: StringName, config: Resource, logical_position: Vector2
	) -> bool:
		if marker_id == &"" or config == null:
			return false
		var record := {
			"id": marker_id,
			"source_kind": &"source",
			"marker_type": config.get("marker_type"),
			"logical_position": logical_position,
			"config": config,
		}
		if markers.has(marker_id) and markers[marker_id] == record:
			return false
		markers[marker_id] = record
		markers_changed.emit()
		return true

	func has_marker(marker_id: StringName) -> bool:
		return markers.has(marker_id)

	func world_origin_for(_position: Vector2i) -> Vector2:
		return Vector2.ZERO


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
	assert_eq(vertical_bridge.rotation, 0.0, "垂直桥必须使用原始方向，不得旋转像素图。")
	assert_eq(vertical_bridge.texture.resource_path, VERTICAL_BRIDGE_TEXTURE_PATH)


## 两份画布必须渲染同一份逻辑标记快照，并保持各自独立节点。
## @return 无返回值。
func test_two_canvas_instances_share_marker_state_without_sharing_nodes() -> void:
	var model: FakeMapModel = track(FakeMapModel.new()) as FakeMapModel
	model.discovered_rooms[Vector2i(2, 2)] = true
	var first: Control = _create_canvas(model)
	var second: Control = _create_canvas(model)
	var config: Resource = MARKER_CONFIG_SCRIPT.new()
	config.set("marker_type", &"test_marker")
	config.set("icon", load("res://res/room_icon/room_marker/Room_Marker.png"))
	config.set("marker_scale", 1.25)
	model.add_test_marker(&"player:test", config, Vector2(2.5, 1.25))
	assert_eq(first.call("get_generated_marker_count"), 1)
	assert_eq(second.call("get_generated_marker_count"), 1)
	var first_marker: Sprite2D = first.get_node("PinesContainer").get_child(0) as Sprite2D
	var second_marker: Sprite2D = second.get_node("PinesContainer").get_child(0) as Sprite2D
	assert_ne(first_marker, second_marker)
	assert_eq(first_marker.position, Vector2(80.0, 40.0))
	assert_eq(second_marker.position, first_marker.position)
	assert_eq(first_marker.scale, Vector2(1.25, 1.25))


## Item 标记在房间未探索时等待，探索后注册，并在来源节点释放后由 Model 保留。
## @return 无返回值。
func test_item_marker_waits_for_discovery_and_persists_in_model() -> void:
	var model: FakeMapModel = track(FakeMapModel.new()) as FakeMapModel
	var item_scene := (
		ResourceLoader.load(
			"res://scenes/ItemTerrian/Item.tscn",
			"PackedScene",
			ResourceLoader.CACHE_MODE_REPLACE_DEEP
		)
		as PackedScene
	)
	var item: Node2D = item_scene.instantiate() as Node2D
	var item_marker_controller: Node = item.get_node("MarkerController")
	assert_true(item_marker_controller.get_node_or_null("MarkerPoint") is Node2D)
	assert_eq(
		item_marker_controller.get_script().resource_path,
		"res://scripts/map_scripts/UIMapMarkerController.gd"
	)
	item.free()

	var marker_controller: Node2D = MARKER_CONTROLLER_SCRIPT.new() as Node2D
	var marker_point := Node2D.new()
	marker_point.name = &"MarkerPoint"
	marker_controller.add_child(marker_point)
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	tree.root.add_child(marker_controller)
	marker_controller.set(
		"marker_config", load("res://resources/map/markers/room_marker_blue.tres")
	)
	assert_true(bool(marker_controller.call("bind_map_model", model)))
	marker_controller.call("set_room_identity", Vector2i(2, 3))
	assert_eq(model.get_marker_snapshot().size(), 0, "未探索房间的预加载 Item 不得提前泄露标记。")

	assert_true(model.discover(Vector2i(2, 3)))
	assert_eq(model.get_marker_snapshot().size(), 1, "房间探索后 Item 标记应注册到 Model。")
	marker_controller.call("set_room_identity", Vector2i(2, 3))
	assert_eq(model.get_marker_snapshot().size(), 1, "同一稳定来源重复注册不得生成重复标记。")

	marker_controller.free()
	assert_eq(model.get_marker_snapshot().size(), 1, "来源节点卸载后，已发现标记仍应由 Model 保留。")


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
		track(
			(
				(
					ResourceLoader.load(
						"res://scenes/map_scenes/map_view/MiniMap.tscn",
						"PackedScene",
						ResourceLoader.CACHE_MODE_REPLACE
					)
					as PackedScene
				)
				. instantiate()
			)
		)
		as Node
	)
	var large: Node = (
		track(
			(
				(
					ResourceLoader.load(
						"res://scenes/map_scenes/map_view/LargeMap.tscn",
						"PackedScene",
						ResourceLoader.CACHE_MODE_REPLACE
					)
					as PackedScene
				)
				. instantiate()
			)
		)
		as Node
	)
	var room_template: Node = (
		track(
			(
				(
					ResourceLoader.load(
						"res://scenes/map_scenes/map_view/RoomTemplate.tscn",
						"PackedScene",
						ResourceLoader.CACHE_MODE_REPLACE
					)
					as PackedScene
				)
				. instantiate()
			)
		)
		as Node
	)
	var map_control: Node = (
		track(
			(
				(
					ResourceLoader.load(
						"res://scenes/map_scenes/map_control.tscn",
						"PackedScene",
						ResourceLoader.CACHE_MODE_REPLACE
					)
					as PackedScene
				)
				. instantiate()
			)
		)
		as Node
	)
	assert_true(mini.get_node_or_null("MaskContainer/CanvasViewport/WorldMapCanvas") != null)
	assert_true(large.get_node_or_null("ViewportControl/WorldMapCanvas") != null)
	assert_true(large.get_node_or_null("LegendUI/Margin/Content/OptionsScroll") is ScrollContainer)
	assert_true(large.get_node("ViewportControl").has_method("set_zoom"))
	assert_true(mini.get_script().resource_path.ends_with("UIMiniMap.gd"))
	assert_true(room_template.has_method("configure_room"))
	assert_true(room_template.get_node_or_null("RoomView") is Sprite2D)
	assert_true(room_template.get_node_or_null("RoomView").has_method("set_current_room"))
	assert_true(room_template.get_node_or_null("BridgeContainer") is Node2D)
	assert_true(room_template.get_node_or_null("BridgeContainer").has_method("configure_bridges"))
	assert_true(map_control.get_node_or_null("CanvasLayer/MiniMap") != null)
	assert_true(map_control.get_node_or_null("LargeMap") != null)
	assert_true(map_control.get_node_or_null("MapLittle") != null)
	assert_true(map_control.get_node_or_null("CanvasLayer") is CanvasLayer)
	assert_true(
		FileAccess.get_file_as_string("res://scripts/map_scripts/UIMiniMap.gd").contains(
			"create_tween()"
		)
	)
	var old_adapter: Node = MAP_LITTLE_SCRIPT.new()
	track(old_adapter)
	for method_name: StringName in [
		&"build_little_map",
		&"change_this_cell_color",
		&"return_this_cell_color",
		&"update_current_position",
	]:
		assert_true(old_adapter.has_method(method_name), "旧动态入口必须保留：%s" % method_name)


## 大地图输入、暂停和地图设置页必须保留稳定的生产接线。
## @return 无返回值。
func test_map_interaction_and_option_panel_contracts() -> void:
	var project_config: String = FileAccess.get_file_as_string("res://project.godot")
	var open_map_start: int = project_config.find("open_map={")
	var open_map_end: int = project_config.find("\n}\n", open_map_start)
	var open_map_block: String = project_config.substr(
		open_map_start, open_map_end - open_map_start
	)
	assert_true(open_map_block.contains('"physical_keycode":84'), "open_map 必须绑定物理 T 键。")
	assert_false(open_map_block.contains('"physical_keycode":77'), "open_map 不得继续占用物理 M 键。")

	var large_source: String = FileAccess.get_file_as_string(
		"res://scripts/map_scripts/UILargeMap.gd"
	)
	assert_true(large_source.contains('@export var open_map_action: StringName = &"open_map"'))
	assert_true(large_source.contains("event.is_action_pressed(open_map_action)"))
	assert_false(large_source.contains("KEY_T"), "大地图脚本不得硬编码 T 键。")
	assert_false(large_source.contains("physical_keycode"), "大地图脚本不得读取物理键码。")
	assert_true(large_source.contains("_was_paused_before_open = tree.paused"))
	assert_true(large_source.contains("tree.paused = true"))
	assert_true(large_source.contains("remove_nearest_player_marker"))

	var option_scene := load("res://scenes/ui_scenes/option_panel.tscn") as PackedScene
	var option_panel: Control = track(option_scene.instantiate()) as Control
	assert_true(option_panel.get_node_or_null("Center/Panel") is PanelContainer)
	assert_true(option_panel.get_node_or_null("%MapCategoryButton") is Button)
	assert_true(option_panel.get_node_or_null("%MiniMapZoomSlider") is HSlider)
	assert_true(option_panel.get_node_or_null("%ResetMapButton") is Button)
	assert_true(option_panel.get_node_or_null("%BackButton") is Button)


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
