extends Node2D

## 地图世界 View。
##
## View 只把 MapWorldModel 提供的资源配置转换为场景树中的显示节点。
## Model 长期缓存 MapSceneResource/PackedScene，View 只保留当前房间周围
## 3×3 范围内的 Node2D，避免窗口外的完整瓦片地图长期占用场景树。

const ORIGINAL_BACKGROUND_SELF_MODULATE_META := &"original_background_self_modulate"
const DEFAULT_ROOM_SIZE := Vector2(1280.0, 720.0)

signal on_entered_room(position: Vector2i, scene: Node2D)

@export var night_background_tint: Color = Color(0.45, 0.45, 0.55, 1.0)

@onready var map_position: Node = get_node_or_null("../MapPositionCreate")
@onready var map_types: Node = get_node_or_null("../MapTypes")
@onready var map_world_model: Node = get_node_or_null("../MapWorldModel")
@onready var time_system: Node = get_node_or_null("/root/TimeSystem")

## 玩家当前所在房间，供棋盘和背景解析器读取。
var current_scene: Node2D = null
## 玩家当前所在地图坐标。
var current_position: Vector2i = Vector2i.ZERO
## 地图坐标到场景路径的兼容查询表。
var map_road_in_map: Dictionary = {}
## 当前 3×3 活跃窗口中的运行时节点；窗口外节点不保留。
var active_instances: Dictionary = {}
## 旧调用方仍使用 map_scene，指向同一份活跃实例字典。
var map_scene: Dictionary = active_instances
var _is_night: bool = false

func _ready() -> void:
	_bind_time_system()
	if map_position == null or map_types == null or map_world_model == null:
		push_error("UIMapWorldView 缺少 MapPositionCreate、MapTypes 或 MapWorldModel，无法显示无缝地图。")
		return

	map_world_model.connect(&"current_room_changed", Callable(self, "_on_model_current_room_changed"))
	create_map_road()
	map_world_model.call(&"set_room_size", DEFAULT_ROOM_SIZE)

	var start_position: Vector2i = map_position.get(&"start_position")
	_activate_window(start_position)
	_set_current_scene(start_position, false)

func _exit_tree() -> void:
	if map_world_model != null and map_world_model.has_signal(&"current_room_changed"):
		var callable := Callable(self, "_on_model_current_room_changed")
		if map_world_model.is_connected(&"current_room_changed", callable):
			map_world_model.disconnect(&"current_room_changed", callable)
	if time_system != null and time_system.has_signal(&"DayNightToggled"):
		var callable := Callable(self, "_on_day_night_toggled")
		if time_system.is_connected(&"DayNightToggled", callable):
			time_system.disconnect(&"DayNightToggled", callable)

## 根据地图生成结果建立坐标到场景路径的查询表。
##
## @return 无返回值。
func create_map_road() -> void:
	map_road_in_map.clear()
	var map_grid: Array = map_position.get(&"map")
	for row in range(map_grid.size()):
		for column in range(map_grid[row].size()):
			var room_position := Vector2i(row, column)
			var scene_name := String(map_grid[row][column])
			if scene_name == "void":
				continue
			map_road_in_map[room_position] = String(map_types.call(&"from_name_get_road", scene_name))
	map_world_model.set(&"map_road_in_map", map_road_in_map)

## 预热所有有效坐标的资源，不实例化全部房间节点。
##
## @return 无返回值。
func load_all_rooms() -> void:
	for position_value in map_road_in_map.keys():
		map_world_model.call(&"get_scene_resource", position_value as Vector2i)

## 兼容旧调用方：预加载中心周围的 3×3 显示窗口。
##
## @param room_position 当前房间坐标。
## @return 无返回值。
func _preload_adjacent_rooms(room_position: Vector2i) -> void:
	_activate_window(room_position)

## 确保指定坐标有一个活跃房间实例，并返回该实例。
##
## @param room_position 地图坐标。
## @return 已缓存或新创建的房间节点；无效坐标或资源加载失败时返回 null。
func ensure_scene_at(room_position: Vector2i) -> Node2D:
	if active_instances.has(room_position):
		var cached := active_instances[room_position] as Node2D
		if cached != null and is_instance_valid(cached):
			return cached
		active_instances.erase(room_position)

	var context := map_world_model.call(&"get_room_context", room_position) as RoomContext
	if context == null or context.scene_resource == null:
		push_warning("UIMapWorldView 收到没有资源配置的房间坐标：%s。" % str(room_position))
		return null
	var resource: MapSceneResource = context.scene_resource
	var packed_scene := resource.packed_scene
	if packed_scene == null:
		push_error("UIMapWorldView 的房间资源缺少 PackedScene：%s" % str(room_position))
		return null

	var room_scene := packed_scene.instantiate() as Node2D
	if room_scene == null:
		push_error("UIMapWorldView 加载的房间根节点不是 Node2D：%s" % resource.get("scene_path"))
		return null

	room_scene.position = map_world_model.call(&"world_origin_for", room_position)
	if not room_scene.has_method(&"configure_room_context"):
		push_error("房间根节点缺少 configure_room_context(context)：%s" % resource.scene_path)
		room_scene.free()
		return null
	# 子模块先收到统一连接数据，旧初始化与观察者才会看到一致的桥口状态。
	# 配置失败的实例不能进入场景树，避免残缺桥口产生一帧可穿透空隙。
	if not bool(room_scene.call(&"configure_room_context", context)):
		push_error("房间模块配置失败：%s" % resource.scene_path)
		room_scene.free()
		return null
	active_instances[room_position] = room_scene
	add_child(room_scene)
	if room_scene.has_method(&"initialize_scene"):
		room_scene.call(&"initialize_scene")
	_apply_background_time_tint(room_scene)
	return room_scene

## 兼容旧门和按钮的进入房间入口；真正的状态修改交给 Controller/Model。
##
## @param room_position 目标地图坐标。
## @return 目标是有效房间并完成请求时返回 true。
func load_scene_at(room_position: Vector2i) -> bool:
	var controller := get_node_or_null("../UIMapWorldController")
	if controller == null:
		controller = get_node_or_null("../MapWorldController")
	if controller != null and controller.has_method(&"request_room_transition"):
		return bool(controller.call(&"request_room_transition", room_position))
	return bool(map_world_model.call(&"try_enter_room", room_position))

## 返回当前 3×3 活跃窗口中的坐标，供测试和调试读取。
##
## @return 活跃房间坐标数组。
func get_active_positions() -> Array[Vector2i]:
	var positions: Array[Vector2i] = []
	for position_value in active_instances.keys():
		positions.append(position_value as Vector2i)
	return positions

func _on_model_current_room_changed(room_position: Vector2i) -> void:
	_activate_window(room_position)
	_set_current_scene(room_position, true)

func _activate_window(center: Vector2i) -> void:
	var target_positions: Array[Vector2i] = map_world_model.call(&"get_window_positions", center)
	for room_position in target_positions:
		ensure_scene_at(room_position)
	_position_all_rooms()

	# 先完成新窗口的实例化，再释放旧节点，避免玩家跨界时看到空白帧。
	for position_value in active_instances.keys().duplicate():
		var room_position := position_value as Vector2i
		if target_positions.has(room_position):
			continue
		var room_scene := active_instances[room_position] as Node2D
		active_instances.erase(room_position)
		if room_scene != null and is_instance_valid(room_scene):
			room_scene.queue_free()

func _set_current_scene(room_position: Vector2i, emit_room_signal: bool) -> void:
	var room_scene := active_instances.get(room_position, null) as Node2D
	if room_scene == null or not is_instance_valid(room_scene):
		return
	current_scene = room_scene
	current_position = room_position
	if emit_room_signal:
		emit_signal(&"on_entered_room", room_position, room_scene)

func _position_all_rooms() -> void:
	for position_value in active_instances.keys():
		var room_scene := active_instances[position_value] as Node2D
		if room_scene != null and is_instance_valid(room_scene):
			room_scene.position = map_world_model.call(&"world_origin_for", position_value as Vector2i)

func _bind_time_system() -> void:
	if time_system == null:
		push_warning("UIMapWorldView 未找到 TimeSystem，地图背景不会随昼夜状态变暗。")
		return

	_is_night = bool(time_system.get("IsNight"))
	if not time_system.has_signal(&"DayNightToggled"):
		push_warning("TimeSystem 缺少 DayNightToggled 信号，地图背景不会实时响应昼夜切换。")
		return
	var callable := Callable(self, "_on_day_night_toggled")
	if not time_system.is_connected(&"DayNightToggled", callable):
		time_system.connect(&"DayNightToggled", callable)

func _on_day_night_toggled(is_night: bool) -> void:
	_is_night = is_night
	for room_scene_value in active_instances.values():
		var room_scene := room_scene_value as Node
		if room_scene != null and is_instance_valid(room_scene):
			_apply_background_time_tint(room_scene)

func _apply_background_time_tint(room_scene: Node) -> void:
	var background := _find_background(room_scene)
	if background == null:
		return
	var day_self_modulate := _get_day_background_self_modulate(background)
	background.self_modulate = _multiply_color(day_self_modulate, night_background_tint) if _is_night else day_self_modulate

func _find_background(room_scene: Node) -> Sprite2D:
	if room_scene == null:
		return null
	return room_scene.get_node_or_null("Background") as Sprite2D

func _get_day_background_self_modulate(background: Sprite2D) -> Color:
	if not background.has_meta(ORIGINAL_BACKGROUND_SELF_MODULATE_META):
		background.set_meta(ORIGINAL_BACKGROUND_SELF_MODULATE_META, background.self_modulate)
	return background.get_meta(ORIGINAL_BACKGROUND_SELF_MODULATE_META)

func _multiply_color(base_color: Color, tint: Color) -> Color:
	return Color(
		base_color.r * tint.r,
		base_color.g * tint.g,
		base_color.b * tint.b,
		base_color.a * tint.a
	)
