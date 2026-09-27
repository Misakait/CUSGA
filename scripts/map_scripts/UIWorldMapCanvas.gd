extends Control

## 共用地图画布 View。
##
## 该组件只把 MapWorldModel 的已探索房间与双向连接转换为轻量地图图元。
## MiniMap 与 LargeMap 各自实例化一份本场景，但读取同一个 Model。

const ROOM_DISCOVERED_SIGNAL: StringName = &"room_discovered"
const CURRENT_ROOM_CHANGED_SIGNAL: StringName = &"current_room_changed"
const DIRECTION_OFFSETS: Array[Vector2i] = [
	Vector2i(-1, 0),
	Vector2i(0, 1),
	Vector2i(1, 0),
	Vector2i(0, -1),
]

@export_group("地图图元")
## 相邻房间中心在画布中的像素间距。
@export var room_step: Vector2 = Vector2(32.0, 32.0)
## 已探索普通房间使用的临时纹理。
@export var room_texture: Texture2D = preload("res://res/room_icon/Room.png")
## 玩家当前所在房间使用的临时纹理。
@export var current_room_texture: Texture2D = preload("res://res/room_icon/Room-With-Me.png")
## 两个已探索互通房间之间使用的桥纹理。
@export var room_bridge_texture: Texture2D = preload("res://res/room_icon/Room_Bridge.png")

var _map_model: Node = null
var _room_nodes: Dictionary = {}
var _bridge_nodes: Dictionary = {}
var _current_room: Vector2i = Vector2i.ZERO

@onready var rooms_container: Control = $RoomsContainer
@onready var pines_container: Control = $PinesContainer
@onready var player_marker: Node2D = $PlayerMarker


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	rooms_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pines_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 本轮用红色房间图标表示当前位置；精确房间内坐标留给后续指南针功能。
	player_marker.visible = false


func _exit_tree() -> void:
	_disconnect_model()


## 绑定地图事实来源并按当前探索状态刷新画布。
##
## @param model 必须提供探索查询、连接查询和当前房间信号的 MapWorldModel。
## @return 协议完整并成功绑定时返回 true；依赖缺失时返回 false。
func bind_model(model: Node) -> bool:
	if model == _map_model:
		refresh_discovered_rooms()
		return model != null
	_disconnect_model()
	if not _has_required_model_protocol(model):
		push_error("UIWorldMapCanvas 收到的 Model 缺少地图探索协议。")
		return false
	_map_model = model
	var discovered_callable: Callable = Callable(self, "_on_room_discovered")
	if not _map_model.is_connected(ROOM_DISCOVERED_SIGNAL, discovered_callable):
		_map_model.connect(ROOM_DISCOVERED_SIGNAL, discovered_callable)
	var current_callable: Callable = Callable(self, "_on_current_room_changed")
	if not _map_model.is_connected(CURRENT_ROOM_CHANGED_SIGNAL, current_callable):
		_map_model.connect(CURRENT_ROOM_CHANGED_SIGNAL, current_callable)
	refresh_discovered_rooms()
	var current_value: Variant = _map_model.get(&"current_position")
	if current_value is Vector2i:
		update_current_room(current_value)
	return true


## 按 Model 的已探索集合增删房间与桥，重复调用保持节点数量不变。
##
## @return 无返回值。
func refresh_discovered_rooms() -> void:
	if _map_model == null:
		return
	var discovered_value: Variant = _map_model.call(&"get_discovered_positions")
	if not discovered_value is Array:
		push_error("UIWorldMapCanvas 无法读取已探索房间数组。")
		return
	var discovered_positions: Array = discovered_value
	var desired_rooms: Dictionary = {}
	for position_value: Variant in discovered_positions:
		if position_value is Vector2i:
			desired_rooms[position_value] = true
	for position_value: Variant in _room_nodes.keys():
		if not desired_rooms.has(position_value):
			_remove_room(position_value)
	for position_value: Variant in desired_rooms.keys():
		_ensure_room(position_value)

	var desired_bridges: Dictionary = {}
	for position_value: Variant in desired_rooms.keys():
		var room_position: Vector2i = position_value
		for offset: Vector2i in DIRECTION_OFFSETS:
			var neighbor: Vector2i = room_position + offset
			if not desired_rooms.has(neighbor):
				continue
			if not bool(_map_model.call(&"are_rooms_connected", room_position, neighbor)):
				continue
			var bridge_key: String = _bridge_key(room_position, neighbor)
			desired_bridges[bridge_key] = [room_position, neighbor]
	for bridge_key_value: Variant in _bridge_nodes.keys():
		if not desired_bridges.has(bridge_key_value):
			_remove_bridge(String(bridge_key_value))
	for bridge_key_value: Variant in desired_bridges.keys():
		var endpoints: Array = desired_bridges[bridge_key_value]
		_ensure_bridge(endpoints[0], endpoints[1])
	update_current_room(_current_room)


## 增量显示一个新探索房间及其与已探索邻居之间的桥。
##
## @param room_position 新探索的地图坐标。
## @return 无返回值。
func reveal_room(room_position: Vector2i) -> void:
	if _map_model == null or not bool(_map_model.call(&"is_room_discovered", room_position)):
		return
	_ensure_room(room_position)
	for offset: Vector2i in DIRECTION_OFFSETS:
		var neighbor: Vector2i = room_position + offset
		if not bool(_map_model.call(&"is_room_discovered", neighbor)):
			continue
		if bool(_map_model.call(&"are_rooms_connected", room_position, neighbor)):
			_ensure_bridge(room_position, neighbor)


## 把旧当前位置恢复为普通图标，并把新当前位置切换为红色图标。
##
## @param room_position 当前房间地图坐标。
## @return 无返回值。
func update_current_room(room_position: Vector2i) -> void:
	var previous_node: Sprite2D = _room_nodes.get(_current_room, null) as Sprite2D
	if previous_node != null and is_instance_valid(previous_node):
		previous_node.texture = room_texture
	_current_room = room_position
	var current_node: Sprite2D = _room_nodes.get(room_position, null) as Sprite2D
	if current_node != null and is_instance_valid(current_node):
		current_node.texture = current_room_texture


## 将 row/column 地图坐标转换成画布局部坐标。
##
## @param room_position 地图坐标；x 为 row，y 为 column。
## @return 房间图片中心在 WorldMapCanvas 中的位置。
func get_room_canvas_position(room_position: Vector2i) -> Vector2:
	return Vector2(float(room_position.y) * room_step.x, float(room_position.x) * room_step.y)


## 返回当前已生成的房间图元数量。
##
## @return 房间节点数量。
func get_generated_room_count() -> int:
	return _room_nodes.size()


## 返回当前已生成且已去重的桥图元数量。
##
## @return 桥节点数量。
func get_generated_bridge_count() -> int:
	return _bridge_nodes.size()


## 返回指定房间当前使用的纹理路径，供测试与运行诊断使用。
##
## @param room_position 地图坐标。
## @return 房间已生成时返回纹理资源路径，否则返回空字符串。
func get_room_texture_path(room_position: Vector2i) -> String:
	var room_node: Sprite2D = _room_nodes.get(room_position, null) as Sprite2D
	if room_node == null or not is_instance_valid(room_node) or room_node.texture == null:
		return ""
	return room_node.texture.resource_path


func _on_room_discovered(room_position: Vector2i) -> void:
	reveal_room(room_position)


func _on_current_room_changed(room_position: Vector2i) -> void:
	update_current_room(room_position)


func _ensure_room(room_position: Vector2i) -> void:
	var existing: Sprite2D = _room_nodes.get(room_position, null) as Sprite2D
	if existing != null and is_instance_valid(existing):
		return
	var room_node := Sprite2D.new()
	room_node.name = "Room_%d_%d" % [room_position.x, room_position.y]
	room_node.texture = current_room_texture if room_position == _current_room else room_texture
	room_node.position = get_room_canvas_position(room_position)
	room_node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	room_node.z_index = 1
	rooms_container.add_child(room_node)
	_room_nodes[room_position] = room_node


func _ensure_bridge(first: Vector2i, second: Vector2i) -> void:
	var key: String = _bridge_key(first, second)
	var existing: Sprite2D = _bridge_nodes.get(key, null) as Sprite2D
	if existing != null and is_instance_valid(existing):
		return
	var bridge_node := Sprite2D.new()
	bridge_node.name = "RoomBridge_%s" % key.replace(",", "_").replace("-", "m")
	bridge_node.texture = room_bridge_texture
	bridge_node.position = (
		(get_room_canvas_position(first) + get_room_canvas_position(second)) / 2.0
	)
	bridge_node.rotation = PI / 2.0 if first.y == second.y else 0.0
	bridge_node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bridge_node.z_index = 0
	rooms_container.add_child(bridge_node)
	rooms_container.move_child(bridge_node, 0)
	_bridge_nodes[key] = bridge_node


func _remove_room(room_position: Vector2i) -> void:
	var room_node: Sprite2D = _room_nodes.get(room_position, null) as Sprite2D
	_room_nodes.erase(room_position)
	if room_node != null and is_instance_valid(room_node):
		room_node.queue_free()


func _remove_bridge(key: String) -> void:
	var bridge_node: Sprite2D = _bridge_nodes.get(key, null) as Sprite2D
	_bridge_nodes.erase(key)
	if bridge_node != null and is_instance_valid(bridge_node):
		bridge_node.queue_free()


func _bridge_key(first: Vector2i, second: Vector2i) -> String:
	var before: Vector2i = first
	var after: Vector2i = second
	if second.x < first.x or (second.x == first.x and second.y < first.y):
		before = second
		after = first
	return "%d,%d-%d,%d" % [before.x, before.y, after.x, after.y]


func _has_required_model_protocol(model: Node) -> bool:
	if model == null:
		return false
	for method_name: StringName in [
		&"get_discovered_positions",
		&"is_room_discovered",
		&"are_rooms_connected",
	]:
		if not model.has_method(method_name):
			return false
	return (
		model.has_signal(ROOM_DISCOVERED_SIGNAL) and model.has_signal(CURRENT_ROOM_CHANGED_SIGNAL)
	)


func _disconnect_model() -> void:
	if _map_model == null or not is_instance_valid(_map_model):
		_map_model = null
		return
	var discovered_callable: Callable = Callable(self, "_on_room_discovered")
	if (
		_map_model.has_signal(ROOM_DISCOVERED_SIGNAL)
		and _map_model.is_connected(ROOM_DISCOVERED_SIGNAL, discovered_callable)
	):
		_map_model.disconnect(ROOM_DISCOVERED_SIGNAL, discovered_callable)
	var current_callable: Callable = Callable(self, "_on_current_room_changed")
	if (
		_map_model.has_signal(CURRENT_ROOM_CHANGED_SIGNAL)
		and _map_model.is_connected(CURRENT_ROOM_CHANGED_SIGNAL, current_callable)
	):
		_map_model.disconnect(CURRENT_ROOM_CHANGED_SIGNAL, current_callable)
	_map_model = null
