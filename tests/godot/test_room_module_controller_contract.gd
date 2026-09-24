@tool
extends McpTestSuite

## normal 房间模块契约，锁定真实资源的方向状态、碰撞与重复配置行为。
const ROOM_ROOT: String = "res://scenes/map_scenes/map_env/normal/"
const ROOM_PATHS: Array[String] = [
	"main/clear_creek.tscn", "main/common_forest.tscn", "main/rolling_hills.tscn",
	"main/tranquil_lakeside.tscn", "main/vast_grassland.tscn", "market/ordinary_market.tscn",
	"secondary/abandoned_farmland.tscn", "secondary/forest_path.tscn",
	"secondary/ordinary_wetland.tscn", "secondary/riverside_meadow.tscn",
	"secondary/valley_pass.tscn", "transmitting/gate_of_ordinariness.tscn",
]
const DIRECTIONS: Array[String] = ["Up", "Right", "Down", "Left"]
const MODULES: Array[String] = [
	"Ground", "Obstack", "BridgeContainer", "BridgeWithBoundary", "BridgeBoundary", "Boundary",
]

## 返回编辑器测试入口名称。
## @return 房间模块契约套件名称。
func suite_name() -> String:
	return "room_module_controller_contract"


func _context(mask: int, path: String) -> RoomContext:
	var context := RoomContext.new()
	context.connection_mask = mask
	context.scene_resource = MapSceneResource.new()
	context.scene_resource.scene_path = path
	context.scene_resource.packed_scene = load(path) as PackedScene
	return context


func _room(relative_path: String) -> Node2D:
	var packed := load(ROOM_ROOT + relative_path) as PackedScene
	assert_true(packed != null, "房间必须可加载：%s" % relative_path)
	if packed == null:
		return null
	return track(packed.instantiate()) as Node2D


func _fixed_snapshot(container: Node) -> Array:
	var result: Array = []
	for module_name in ["Ground", "Obstack", "Boundary"]:
		for child in container.get_node(NodePath(module_name)).get_children():
			if child is TileMapLayer:
				var layer := child as TileMapLayer
				result.append([layer.get_instance_id(), layer.visible, layer.collision_enabled,
					layer.tile_set, layer.tile_map_data, layer.get_child_count()])
	return result


## 所有实际房间逐一覆盖 16 种连接组合；固定模块和瓦片布局不得被重写。
## @return 无返回值。
func test_all_normal_rooms_direction_states_and_idempotence() -> void:
	# 非工具脚本在编辑器里只是占位实例，模块方法必须由游戏进程验证。
	if Engine.is_editor_hint():
		skip("房间模块需要真实脚本实例；请在运行中的游戏通过 game_eval await 执行本用例。")
		return
	for relative_path in ROOM_PATHS:
		var room: Node2D = _room(relative_path)
		if room == null:
			continue
		var container := room.get_node("MapContainer")
		var fixed_before: Array = _fixed_snapshot(container)
		var count_before: int = container.get_child_count()
		for mask in range(16):
			var context: RoomContext = _context(mask, ROOM_ROOT + relative_path)
			for module_name in MODULES:
				assert_true(container.get_node(NodePath(module_name)).has_method("validate_room_context"),
					"各模块必须支持无副作用预检：%s/%s" % [relative_path, module_name])
			assert_true(bool(room.call("configure_room_context", context)), "房间根入口必须成功转发。")
			assert_eq(container.call("get_room_context"), context, "必须保存 Model 传入的同一上下文。")
			assert_true(bool(room.call("configure_room_context", context)), "重复配置必须成功。")
			assert_eq(container.get_child_count(), count_before, "重复配置不得创建新节点。")
			assert_eq(_fixed_snapshot(container), fixed_before, "固定边界、地面、障碍不随连接变化。")
			for direction in range(4):
				var connected: bool = (mask & (1 << direction)) != 0
				for module_name in ["BridgeContainer", "BridgeWithBoundary", "BridgeBoundary"]:
					var suffix: String = "Bridge" if module_name == "BridgeContainer" else module_name
					var layer := container.get_node(NodePath("%s/%s%s" % [module_name, DIRECTIONS[direction], suffix])) as TileMapLayer
					var active: bool = not connected if module_name == "BridgeWithBoundary" else connected
					assert_eq(layer.visible, active, "%s/%s 方向显示错误。" % [relative_path, layer.name])
					assert_eq(layer.collision_enabled, active if module_name != "BridgeContainer" else false,
						"桥口与桥侧同步碰撞，桥面本身不能封路。")
		room.free()


## 逐瓦片检查阻挡资源与玩家碰撞层相配，可走地面及桥面无碰撞。
## @return 无返回值。
func test_all_normal_room_tiles_have_role_specific_collision() -> void:
	var player := load("res://scenes/player_scenes/PlayerChar.tscn") as PackedScene
	var player_body := track(player.instantiate()) as CharacterBody2D
	for relative_path in ROOM_PATHS:
		var room: Node2D = _room(relative_path)
		if room == null:
			continue
		for module_name in MODULES:
			var module := room.get_node(NodePath("MapContainer/" + module_name))
			var blocks_player: bool = module_name in ["Boundary", "BridgeBoundary", "BridgeWithBoundary", "Obstack"]
			for child in module.get_children():
				if not child is TileMapLayer:
					continue
				var layer := child as TileMapLayer
				var tile_set: TileSet = layer.tile_set
				if blocks_player:
					assert_gt(tile_set.get_physics_layers_count(), 0, "%s/%s 缺少物理层。" % [relative_path, module_name])
					if tile_set.get_physics_layers_count() == 0:
						continue
					assert_true((tile_set.get_physics_layer_collision_layer(0) & player_body.collision_mask) != 0,
						"阻挡层必须匹配玩家实际碰撞掩码。")
				for cell in layer.get_used_cells():
					var data: TileData = layer.get_cell_tile_data(cell)
					assert_true(data != null, "实际瓦片必须有 TileData。")
					if data == null:
						continue
					var polygons: int = 0
					for physics_layer in range(tile_set.get_physics_layers_count()):
						polygons += data.get_collision_polygons_count(physics_layer)
					if blocks_player:
						assert_gt(polygons, 0, "%s/%s 的 %s 缺少阻挡。" % [relative_path, module_name, cell])
					else:
						assert_eq(polygons, 0, "%s/%s 的可走瓦片不能封路。" % [relative_path, module_name])
		room.free()


## 预检不得改变桥状态；只检查直接子层，不接管嵌套或其他模块。
## @return 无返回值。
func test_validation_rejects_missing_direction_without_mutating_modules() -> void:
	# 编辑器占位实例无法调用模块方法，不能据此判断配置协议失败。
	if Engine.is_editor_hint():
		skip("模块预检需要真实脚本实例；请在运行中的游戏通过 game_eval await 执行本用例。")
		return
	var room: Node2D = _room("main/clear_creek.tscn")
	var context: RoomContext = _context(15, ROOM_ROOT + "main/clear_creek.tscn")
	var module := room.get_node("MapContainer/BridgeBoundary")
	var layer := module.get_node("RightBridgeBoundary") as TileMapLayer
	var old_visible: bool = layer.visible
	var old_collision: bool = layer.collision_enabled
	assert_false(bool(module.call("validate_room_context", null)), "空上下文必须拒绝。")
	# 临时移出场景分支前清除归属，恢复后再归还，避免夹具产生无关所有权警告。
	var old_owner: Node = layer.owner
	layer.owner = null
	module.remove_child(layer)
	assert_false(bool(module.call("validate_room_context", context)), "缺少一个真实方向必须拒绝。")
	assert_eq(layer.visible, old_visible, "预检不得改变可见性。")
	assert_eq(layer.collision_enabled, old_collision, "预检不得改变碰撞。")
	module.add_child(layer)
	layer.owner = old_owner
	assert_true(bool(module.call("validate_room_context", context)), "恢复后预检应通过。")
	var ground := room.get_node("MapContainer/Ground")
	var nested := Node2D.new()
	nested.add_child(TileMapLayer.new())
	ground.add_child(nested)
	assert_true(bool(ground.call("validate_room_context", context)), "Ground 不得跨层访问非直属 TileMap。")


## 在独立物理世界中使用玩家实际矩形尺寸，检查四向桥中心与侧边。
## @return 无返回值。
func test_real_player_shape_passes_bridge_centers_and_hits_sides() -> void:
	# 真实物理世界需要跨帧同步，不能让编辑器同步测试器提前释放夹具。
	if Engine.is_editor_hint():
		skip("物理同步需要跨帧；请在运行中的游戏通过 game_eval await 执行本用例。")
		return
	var tree := Engine.get_main_loop() as SceneTree
	var viewport := track(SubViewport.new()) as SubViewport
	viewport.world_2d = World2D.new()
	tree.root.add_child(viewport)
	var room: Node2D = _room("main/clear_creek.tscn")
	assert_true(bool(room.call("configure_room_context", _context(15, ROOM_ROOT + "main/clear_creek.tscn"))))
	viewport.add_child(room)
	var body := CharacterBody2D.new()
	body.collision_layer = 16
	body.collision_mask = 32
	var collision := CollisionShape2D.new()
	var player := load("res://scenes/player_scenes/PlayerChar.tscn") as PackedScene
	var source := player.instantiate()
	collision.shape = (source.get_node("CollisionShape2D") as CollisionShape2D).shape.duplicate()
	source.free()
	body.add_child(collision)
	viewport.add_child(body)
	for layer in room.find_children("*", "TileMapLayer", true, false):
		(layer as TileMapLayer).update_internals()
	await tree.physics_frame
	await tree.physics_frame
	var centers: Array[Vector2] = [Vector2(592, 48), Vector2(1248, 352), Vector2(592, 704), Vector2(32, 352)]
	var forward: Array[Vector2] = [Vector2(0, -100), Vector2(100, 0), Vector2(0, 100), Vector2(-100, 0)]
	for direction in range(4):
		var transform := Transform2D(0.0, centers[direction])
		assert_false(body.test_move(transform, forward[direction]), "玩家尺寸必须能通过 %s 桥中心。" % DIRECTIONS[direction])
		var sideways := Vector2(100, 0) if direction % 2 == 0 else Vector2(0, 100)
		assert_true(body.test_move(transform, sideways), "%s 桥正侧必须阻挡。" % DIRECTIONS[direction])
		assert_true(body.test_move(transform, -sideways), "%s 桥负侧必须阻挡。" % DIRECTIONS[direction])
	assert_true(bool(room.call("configure_room_context", _context(0, ROOM_ROOT + "main/clear_creek.tscn"))))
	for layer in room.find_children("*", "TileMapLayer", true, false):
		(layer as TileMapLayer).update_internals()
	await tree.physics_frame
	await tree.physics_frame
	var inside: Array[Vector2] = [Vector2(592, 160), Vector2(1136, 352), Vector2(592, 560), Vector2(144, 352)]
	for direction in range(4):
		assert_true(body.test_move(Transform2D(0.0, inside[direction]), forward[direction] * 2.0),
			"无连接的 %s 桥口必须阻挡玩家。" % DIRECTIONS[direction])
	assert_true(body.test_move(Transform2D(0.0, Vector2(224, 160)), Vector2(0, -200)), "地形固定边界必须阻挡。")
	room.free()


## 两个真实房间按 720 步长相接，玩家矩形应跨过拼接处且不能从侧面离桥。
## @return 无返回值。
func test_vertical_room_join_keeps_player_sized_passage() -> void:
	# 接缝验证必须等待物理空间更新，避免只运行到第一个 await 就被误报通过。
	if Engine.is_editor_hint():
		skip("物理同步需要跨帧；请在运行中的游戏通过 game_eval await 执行本用例。")
		return
	var tree := Engine.get_main_loop() as SceneTree
	var viewport := track(SubViewport.new()) as SubViewport
	viewport.world_2d = World2D.new()
	tree.root.add_child(viewport)
	var first: Node2D = _room("main/clear_creek.tscn")
	var second: Node2D = _room("secondary/ordinary_wetland.tscn")
	assert_true(bool(first.call("configure_room_context", _context(4, ROOM_ROOT + "main/clear_creek.tscn"))))
	assert_true(bool(second.call("configure_room_context", _context(1, ROOM_ROOT + "secondary/ordinary_wetland.tscn"))))
	second.position = Vector2(0, 720)
	viewport.add_child(first)
	viewport.add_child(second)
	var body := CharacterBody2D.new()
	body.collision_layer = 16
	body.collision_mask = 32
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(100, 140)
	collision.shape = shape
	body.add_child(collision)
	viewport.add_child(body)
	for room in [first, second]:
		for layer in room.find_children("*", "TileMapLayer", true, false):
			(layer as TileMapLayer).update_internals()
	await tree.physics_frame
	await tree.physics_frame
	assert_false(body.test_move(Transform2D(0.0, Vector2(592, 630)), Vector2(0, 180)),
		"上下桥在 720 像素拼接处必须连续可通行。")
	assert_true(body.test_move(Transform2D(0.0, Vector2(592, 720)), Vector2(100, 0)),
		"拼接处桥侧不能留下离桥缺口。")
	assert_true(body.test_move(Transform2D(0.0, Vector2(592, 720)), Vector2(-100, 0)),
		"拼接处另一侧也必须封闭。")
	first.free()
	second.free()
