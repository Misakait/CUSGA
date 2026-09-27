extends Node

## 无缝地图世界模型。
##
## 该节点只保存地图坐标、邻接关系、房间资源缓存和世界坐标换算参数。
## 它不负责实例化场景，也不处理玩家输入，保证生成规则与表现层解耦。

@export var map_position_create_path: NodePath = ^"../MapPositionCreate"

const MAP_SCENE_RESOURCE_SCRIPT := preload("res://resources/map/map_scene_resource.gd")
const ROOM_CONTEXT_SCRIPT := preload("res://core/map/room_context.gd")
const DIRECTION_OFFSETS: Array[Vector2i] = [
	Vector2i(-1, 0),
	Vector2i(0, 1),
	Vector2i(1, 0),
	Vector2i(0, -1),
]
const OPPOSITE_DIRECTIONS: Array[int] = [2, 3, 0, 1]

## 当前房间坐标发生变化时广播；View 监听后刷新显示。
signal current_room_changed(position: Vector2i)
## 房间第一次加入已探索集合时广播；地图 View 据此增量生成房间图元。
signal room_discovered(position: Vector2i)
## 玩家或场景来源标记发生变化时广播；两个地图画布据此同步刷新。
signal markers_changed
## 首次为坐标创建资源配置时广播；View 不需要依赖具体缓存实现。
signal map_resource_created(position: Vector2i, resource: Resource)

## 生成器提供的二维地图名称数组。
var map: Array = []
## 生成器提供的四方向邻接表。
var scene_to_scene: Dictionary = {}
## 地图坐标到场景路径的查询表。
var map_road_in_map: Dictionary = {}
## 地图坐标到房间资源配置的缓存；这里不保存运行时 Node2D。
var scene_resource_cache: Dictionary = {}
## 场景路径到 PackedScene 的缓存，避免相同完整场景被重复加载。
var packed_scene_cache: Dictionary = {}
## 当前玩家所在的有效地图坐标。
var current_position: Vector2i = Vector2i.ZERO
## 本局已经成功进入过的房间集合；键为地图坐标，值固定为 true。
var discovered_rooms: Dictionary = {}
## 本局地图标记记录；键是稳定 ID，值是只含配置与逻辑坐标的字典。
var map_markers: Dictionary = {}
var _next_player_marker_id: int = 1
## 地图生成器给出的起始坐标，用于把起始房间放在世界原点。
var start_position: Vector2i = Vector2i.ZERO
## 单个完整房间场景在世界中的固定步长；normal 群系统一按 1280x720 拼接。
var room_size: Vector2 = Vector2(1280.0, 720.0)

@onready var _map_position_create: Node = get_node_or_null(map_position_create_path)


func _ready() -> void:
	add_to_group(&"map_world_model")
	_refresh_from_generator()


## 从现有地图生成器复制只读运行数据。
##
## @return 无返回值。
func _refresh_from_generator() -> void:
	if _map_position_create == null:
		push_error("MapWorldModel 未找到 MapPositionCreate，无法建立地图世界状态。")
		return

	map = _map_position_create.get(&"map")
	scene_to_scene = _map_position_create.get(&"scene_to_scene")
	start_position = _map_position_create.get(&"start_position")
	current_position = start_position
	discovered_rooms.clear()
	var run_snapshot: Node = get_node_or_null("../../RuntimeState/RunSnapshot")
	if run_snapshot != null:
		var restored: Variant = run_snapshot.call("GetCurrentRoomOrNull")
		if restored is Vector2i and has_room(restored):
			current_position = restored
		if run_snapshot.has_method(&"GetDiscoveredRooms"):
			var restored_rooms: Variant = run_snapshot.call(&"GetDiscoveredRooms")
			if restored_rooms is Array:
				for room_value: Variant in restored_rooms:
					if room_value is Vector2i and has_room(room_value):
						discovered_rooms[room_value] = true
	# 旧存档没有探索字段时，至少保留玩家当前房间，避免继续本局后地图为空。
	discovered_rooms[current_position] = true
	scene_resource_cache.clear()
	packed_scene_cache.clear()
	map_markers.clear()
	_next_player_marker_id = 1


## 注册一个由场景或物品提供的稳定来源标记。
##
## @param source_id 来源场景、房间和锚点共同组成的稳定 ID。
## @param config 地图标记配置 Resource。
## @param logical_position x 为 column、y 为 row 的逻辑地图坐标。
## @return 首次加入或已有记录发生变化时返回 true；无效或完全重复时返回 false。
func register_source_marker(
	source_id: StringName, config: Resource, logical_position: Vector2
) -> bool:
	if source_id == &"" or not _is_marker_config_visible(config):
		return false
	var record := {
		"id": source_id,
		"source_kind": &"source",
		"marker_type": StringName(str(config.get("marker_type"))),
		"logical_position": logical_position,
		"config": config,
	}
	if map_markers.has(source_id) and map_markers[source_id] == record:
		return false
	map_markers[source_id] = record
	markers_changed.emit()
	return true


## 新增一个玩家在大地图自由放置的标记。
##
## @param config 允许玩家放置的地图标记配置。
## @param logical_position x 为 column、y 为 row 的逻辑地图坐标。
## @return 成功时返回新标记的稳定运行时 ID；配置无效时返回空 StringName。
func add_player_marker(config: Resource, logical_position: Vector2) -> StringName:
	if not _is_marker_config_visible(config) or not bool(config.get("player_placeable")):
		return &""
	var marker_id := StringName("player:%d" % _next_player_marker_id)
	_next_player_marker_id += 1
	map_markers[marker_id] = {
		"id": marker_id,
		"source_kind": &"player",
		"marker_type": StringName(str(config.get("marker_type"))),
		"logical_position": logical_position,
		"config": config,
	}
	markers_changed.emit()
	return marker_id


## 删除指定逻辑位置附近最近的玩家标记。
##
## @param logical_position 点击换算后的逻辑地图坐标。
## @param radius 允许删除的逻辑坐标半径。
## @return 找到并删除玩家标记时返回 true。
func remove_nearest_player_marker(logical_position: Vector2, radius: float) -> bool:
	if radius < 0.0:
		return false
	var nearest_id: StringName = &""
	var nearest_distance: float = radius
	for marker_id_value: Variant in map_markers.keys():
		var record: Dictionary = map_markers[marker_id_value]
		if StringName(str(record.get("source_kind", &""))) != &"player":
			continue
		var marker_position: Variant = record.get("logical_position", null)
		if not marker_position is Vector2:
			continue
		var distance: float = logical_position.distance_to(marker_position)
		if distance <= nearest_distance:
			nearest_distance = distance
			nearest_id = StringName(str(marker_id_value))
	if nearest_id == &"":
		return false
	map_markers.erase(nearest_id)
	markers_changed.emit()
	return true


## 查询 Model 是否已经持有指定稳定标记。
##
## @param marker_id 玩家或来源标记 ID。
## @return 记录存在时返回 true。
func has_marker(marker_id: StringName) -> bool:
	return map_markers.has(marker_id)


## 返回地图标记的只读排序快照。
##
## @return 按稳定 ID 排序的记录副本；修改返回字典不会改写 Model。
func get_marker_snapshot() -> Array[Dictionary]:
	var marker_ids: Array = map_markers.keys()
	marker_ids.sort_custom(
		func(left: Variant, right: Variant) -> bool: return str(left) < str(right)
	)
	var snapshot: Array[Dictionary] = []
	for marker_id: Variant in marker_ids:
		var record: Dictionary = map_markers[marker_id]
		snapshot.append(record.duplicate())
	return snapshot


func _is_marker_config_visible(config: Resource) -> bool:
	if config == null:
		return false
	return (
		bool(config.get("allow_map_display"))
		and bool(config.get("active"))
		and config.get("icon") is Texture2D
		and not str(config.get("marker_type")).is_empty()
	)


## 将一个有效房间加入本局探索集合。
##
## @param position 要揭示的地图坐标。
## @return 房间首次加入时返回 true；无效坐标或已经探索时返回 false。
func discover_room(position: Vector2i) -> bool:
	if not has_room(position) or discovered_rooms.has(position):
		return false
	discovered_rooms[position] = true
	room_discovered.emit(position)
	return true


## 返回指定房间是否已经被玩家进入过。
##
## @param position 要查询的地图坐标。
## @return 房间存在于探索集合时返回 true。
func is_room_discovered(position: Vector2i) -> bool:
	return bool(discovered_rooms.get(position, false))


## 返回已探索房间的稳定排序副本。
##
## @return 按行、列升序排列的地图坐标；调用方修改数组不会影响 Model。
func get_discovered_positions() -> Array[Vector2i]:
	var positions: Array[Vector2i] = []
	for position_value: Variant in discovered_rooms.keys():
		if position_value is Vector2i and bool(discovered_rooms[position_value]):
			positions.append(position_value)
	positions.sort_custom(
		func(left: Vector2i, right: Vector2i) -> bool:
			return left.x < right.x or (left.x == right.x and left.y < right.y)
	)
	return positions


## 返回指定地图坐标是否存在可进入的房间。
##
## @param position 要检查的地图坐标。
## @return 坐标对应的格子不是 void 且在生成网格范围内时返回 true。
func has_room(position: Vector2i) -> bool:
	if position.x < 0 or position.x >= map.size():
		return false
	var column: Array = map[position.x]
	if position.y < 0 or position.y >= column.size():
		return false
	return String(column[position.y]) != "void"


## 返回指定地图坐标的资源配置；第一次访问时创建并缓存。
##
## @param position 要查询的地图坐标。
## @return 坐标有效且资源加载成功时返回 MapSceneResource，否则返回 null。
func get_scene_resource(position: Vector2i) -> Resource:
	if scene_resource_cache.has(position):
		return scene_resource_cache[position] as Resource
	if not has_room(position) or not map_road_in_map.has(position):
		return null

	var scene_path := String(map_road_in_map[position])
	var packed_scene := _get_packed_scene(scene_path)
	if packed_scene == null:
		return null

	var resource: Resource = MAP_SCENE_RESOURCE_SCRIPT.new()
	resource.set("scene_name", String(map[position.x][position.y]))
	resource.set("scene_path", scene_path)
	resource.set("packed_scene", packed_scene)
	resource.set("room_size", room_size)
	scene_resource_cache[position] = resource
	emit_signal("map_resource_created", position, resource)
	return resource


## 返回房间四个方向上经过双向连接校验的掩码。
##
## @param position 要查询的房间坐标。
## @return 按上、右、下、左分别映射到低四位的方向掩码。
func get_connection_mask(position: Vector2i) -> int:
	if not has_room(position):
		return 0

	var mask: int = 0
	for direction in range(DIRECTION_OFFSETS.size()):
		var neighbor: Vector2i = position + DIRECTION_OFFSETS[direction]
		if are_rooms_connected(position, neighbor):
			mask |= 1 << direction
	return mask


## 返回房间的纯数据上下文；不把场景节点放入 Model/View 边界。
##
## @param position 要查询的房间坐标。
## @return 房间和场景资源都有效时返回 RoomContext，否则返回 null。
func get_room_context(position: Vector2i) -> RoomContext:
	var scene_resource: MapSceneResource = get_scene_resource(position) as MapSceneResource
	if scene_resource == null:
		return null

	var context: RoomContext = ROOM_CONTEXT_SCRIPT.new() as RoomContext
	context.room_position = position
	context.connection_mask = get_connection_mask(position)
	context.room_size = room_size
	context.scene_resource = scene_resource
	return context


## 检查两个房间是否在生成数据中以双向连接相连。
##
## @param from_position 起始房间坐标。
## @param to_position 目标房间坐标。
## @return 两个坐标正好相邻且双方都声明对应连接时返回 true。
func are_rooms_connected(from_position: Vector2i, to_position: Vector2i) -> bool:
	if not has_room(from_position) or not has_room(to_position):
		return false

	var direction: int = _direction_between(from_position, to_position)
	if direction < 0:
		return false
	var opposite_direction: int = OPPOSITE_DIRECTIONS[direction]
	return (
		_has_declared_connection(from_position, direction)
		and _has_declared_connection(to_position, opposite_direction)
	)


## 返回同一路径共享的 PackedScene，避免重复加载完整房间资源。
##
## @param scene_path 完整房间场景路径。
## @return 加载成功时返回 PackedScene，否则返回 null。
func _get_packed_scene(scene_path: String) -> PackedScene:
	if packed_scene_cache.has(scene_path):
		return packed_scene_cache[scene_path] as PackedScene
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path, "PackedScene"):
		return null
	var packed_scene := load(scene_path) as PackedScene
	if packed_scene == null:
		push_error("MapWorldModel 无法加载房间场景资源：%s" % scene_path)
		return null
	packed_scene_cache[scene_path] = packed_scene
	return packed_scene


## 返回当前坐标周围 3×3 范围内的有效地图坐标。
##
## @param center 当前房间坐标。
## @return 按行列顺序排列的有效房间坐标数组；void 坐标不会返回。
func get_window_positions(center: Vector2i) -> Array[Vector2i]:
	var positions: Array[Vector2i] = []
	for row_offset in range(-1, 2):
		for column_offset in range(-1, 2):
			var position := center + Vector2i(row_offset, column_offset)
			if has_room(position):
				positions.append(position)
	return positions


## 由 Controller 调用，验证并更新当前地图坐标。
##
## @param position 玩家希望进入的地图坐标。
## @return 目标是有效房间并完成更新时返回 true，否则返回 false。
func try_enter_room(position: Vector2i) -> bool:
	if not has_room(position):
		return false
	if current_position != position and not are_rooms_connected(current_position, position):
		return false
	if get_scene_resource(position) == null:
		return false
	if current_position == position:
		discover_room(position)
		return true
	discover_room(position)
	current_position = position
	emit_signal("current_room_changed", position)
	return true


func _direction_between(from_position: Vector2i, to_position: Vector2i) -> int:
	var offset: Vector2i = to_position - from_position
	return DIRECTION_OFFSETS.find(offset)


func _has_declared_connection(position: Vector2i, direction: int) -> bool:
	var connection_value: Variant = scene_to_scene.get(position, null)
	if not connection_value is Array:
		return false

	var connections: Array = connection_value
	if direction < 0 or direction >= connections.size():
		return false
	return int(connections[direction]) == 1


## 返回地图坐标对应的世界原点。
##
## @param position 地图坐标。
## @return 以起始房间为世界原点的房间左上角位置。
func world_origin_for(position: Vector2i) -> Vector2:
	return Vector2(
		float(position.y - start_position.y) * room_size.x,
		float(position.x - start_position.x) * room_size.y
	)


## 将玩家世界坐标换算为所在的地图坐标。
##
## @param world_position 玩家在地图 View 节点下的本地坐标，调用方负责转换全局坐标。
## @return 对应的地图网格坐标；负坐标使用向下取整，保证跨越左/上边界时连续。
func map_position_for_world(world_position: Vector2) -> Vector2i:
	if room_size.x <= 0.0 or room_size.y <= 0.0:
		return current_position

	return Vector2i(
		start_position.x + floori(world_position.y / room_size.y),
		start_position.y + floori(world_position.x / room_size.x)
	)


## 设置运行时测得的房间世界步长。
##
## @param measured_size 完整房间场景采用的固定世界尺寸。
## @return 无返回值。
func set_room_size(measured_size: Vector2) -> void:
	if measured_size.x > 0.0 and measured_size.y > 0.0:
		room_size = measured_size
		for resource_value in scene_resource_cache.values():
			var resource := resource_value as Resource
			if resource != null:
				resource.set("room_size", room_size)
