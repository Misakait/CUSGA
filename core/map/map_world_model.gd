extends Node

## 无缝地图世界模型。
##
## 该节点只保存地图坐标、邻接关系、房间资源缓存和世界坐标换算参数。
## 它不负责实例化场景，也不处理玩家输入，保证生成规则与表现层解耦。

@export var map_position_create_path: NodePath = ^"../MapPositionCreate"

const MAP_SCENE_RESOURCE_SCRIPT := preload("res://resources/map/map_scene_resource.gd")

## 当前房间坐标发生变化时广播；View 监听后刷新显示。
signal current_room_changed(position: Vector2i)
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
## 地图生成器给出的起始坐标，用于把起始房间放在世界原点。
var start_position: Vector2i = Vector2i.ZERO
## 单个完整房间场景在世界中的固定步长；normal 群系统一按 1280x720 拼接。
var room_size: Vector2 = Vector2(1280.0, 720.0)

@onready var _map_position_create: Node = get_node_or_null(map_position_create_path)

func _ready() -> void:
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
	scene_resource_cache.clear()
	packed_scene_cache.clear()

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

## 返回同一路径共享的 PackedScene，避免重复加载完整房间资源。
##
## @param scene_path 完整房间场景路径。
## @return 加载成功时返回 PackedScene，否则返回 null。
func _get_packed_scene(scene_path: String) -> PackedScene:
	if packed_scene_cache.has(scene_path):
		return packed_scene_cache[scene_path] as PackedScene
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
	if current_position == position:
		return true
	current_position = position
	emit_signal("current_room_changed", position)
	return true

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
## @param world_position 玩家在 MapControl 世界根节点下的全局坐标。
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
