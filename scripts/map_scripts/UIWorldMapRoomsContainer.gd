@tool
extends Control

## 世界地图房间模板集合。
##
## 该组件只管理 RoomsContainer 的直接 RoomTemplate 子节点：按探索集合增删模板、
## 计算模板位置，并决定每个模板应当持有哪些真实连接方向。

const BRIDGE_VISIBILITY_POLICY: GDScript = preload(
	"res://scripts/map_scripts/UIWorldMapBridgeVisibilityPolicy.gd"
)

## 相邻房间中心在画布中的像素间距。
@export var room_step: Vector2 = Vector2(32.0, 32.0)
## 单个地图房间使用的组合模板。
@export
var room_template_scene: PackedScene = preload("res://scenes/map_scenes/map_view/RoomTemplate.tscn")
## 默认显示已探索房间通往所有真实连接方向的桥。
@export_enum("显示全部真实连接", "仅显示双方已探索连接") var bridge_visibility_mode: int = 0

var _room_nodes: Dictionary = {}
var _current_room: Vector2i = Vector2i.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## 按探索集合对齐 RoomTemplate，并刷新房间纹理与方向桥。
##
## @param map_model 提供 is_room_discovered 与 are_rooms_connected 的地图 Model。
## @param discovered_positions 当前已探索房间坐标数组。
## @param current_room 玩家当前所在房间坐标。
## @return Model 与模板协议完整并成功刷新时返回 true，否则返回 false。
func refresh_rooms(map_model: Node, discovered_positions: Array, current_room: Vector2i) -> bool:
	if not _has_required_model_protocol(map_model):
		push_error("UIWorldMapRoomsContainer 收到的 Model 缺少地图查询协议。")
		return false
	_current_room = current_room
	var discovered_rooms: Dictionary = _to_room_set(discovered_positions)
	_remove_missing_rooms(discovered_rooms)
	for position_value: Variant in discovered_rooms.keys():
		_ensure_room(position_value)
	for position_value: Variant in discovered_rooms.keys():
		_configure_room(map_model, position_value, discovered_rooms)
	return true


## 更新当前房间纹理，不重建现有模板或桥。
##
## @param room_position 新的当前房间坐标。
## @return 无返回值。
func update_current_room(room_position: Vector2i) -> void:
	_set_template_current_state(_current_room, false)
	_current_room = room_position
	_set_template_current_state(_current_room, true)


## 切换连接桥显示策略；调用方随后应刷新房间集合。
##
## @param mode 0 显示通往未探索邻居的真实连接；1 只显示双方都已探索的桥。
## @return 模式合法并完成设置时返回 true，否则返回 false。
func set_bridge_visibility_mode(mode: int) -> bool:
	if not bool(BRIDGE_VISIBILITY_POLICY.call(&"is_valid_mode", mode)):
		return false
	bridge_visibility_mode = mode
	return true


## 将 row/column 地图坐标转换成 RoomsContainer 局部坐标。
##
## @param room_position 地图坐标；x 为 row，y 为 column。
## @return 房间模板中心在 RoomsContainer 中的位置。
func get_room_canvas_position(room_position: Vector2i) -> Vector2:
	return Vector2(float(room_position.y) * room_step.x, float(room_position.x) * room_step.y)


## 返回当前已生成的 RoomTemplate 数量。
##
## @return 房间模板节点数量。
func get_generated_room_count() -> int:
	return _room_nodes.size()


## 返回所有 RoomTemplate 当前生成且已去重的桥数量。
##
## @return 所有 BridgeContainer 的桥节点合计数量。
func get_generated_bridge_count() -> int:
	var bridge_count: int = 0
	for room_node_value: Variant in _room_nodes.values():
		var room_node: Node = room_node_value as Node
		if room_node != null and room_node.has_method(&"get_generated_bridge_count"):
			bridge_count += int(room_node.call(&"get_generated_bridge_count"))
	return bridge_count


## 返回指定房间模板当前持有的方向桥掩码。
##
## @param room_position 地图坐标。
## @return 模板存在时返回上、右、下、左方向掩码，否则返回 0。
func get_room_bridge_mask(room_position: Vector2i) -> int:
	var room_node: Node = _room_nodes.get(room_position, null) as Node
	if (
		room_node == null
		or not is_instance_valid(room_node)
		or not room_node.has_method(&"get_bridge_mask")
	):
		return 0
	return int(room_node.call(&"get_bridge_mask"))


## 返回指定房间 RoomView 当前使用的纹理路径。
##
## @param room_position 地图坐标。
## @return 模板存在时返回纹理资源路径，否则返回空字符串。
func get_room_texture_path(room_position: Vector2i) -> String:
	var room_node: Node = _room_nodes.get(room_position, null) as Node
	if (
		room_node == null
		or not is_instance_valid(room_node)
		or not room_node.has_method(&"get_room_texture_path")
	):
		return ""
	return String(room_node.call(&"get_room_texture_path"))


func _to_room_set(discovered_positions: Array) -> Dictionary:
	var discovered_rooms: Dictionary = {}
	for position_value: Variant in discovered_positions:
		if position_value is Vector2i:
			discovered_rooms[position_value] = true
	return discovered_rooms


func _remove_missing_rooms(discovered_rooms: Dictionary) -> void:
	for position_value: Variant in _room_nodes.keys():
		if discovered_rooms.has(position_value):
			continue
		var room_node: Node2D = _room_nodes.get(position_value, null) as Node2D
		_room_nodes.erase(position_value)
		if room_node != null and is_instance_valid(room_node):
			remove_child(room_node)
			room_node.queue_free()


func _ensure_room(room_position: Vector2i) -> void:
	var existing: Node2D = _room_nodes.get(room_position, null) as Node2D
	if existing != null and is_instance_valid(existing):
		return
	if room_template_scene == null:
		push_error("UIWorldMapRoomsContainer 缺少 RoomTemplate 场景。")
		return
	var room_node: Node2D = room_template_scene.instantiate() as Node2D
	if room_node == null:
		push_error("UIWorldMapRoomsContainer 无法实例化 RoomTemplate。")
		return
	room_node.name = "Room_%d_%d" % [room_position.x, room_position.y]
	add_child(room_node)
	_room_nodes[room_position] = room_node


func _configure_room(
	map_model: Node, room_position: Vector2i, discovered_rooms: Dictionary
) -> void:
	var room_node: Node = _room_nodes.get(room_position, null) as Node
	if room_node == null or not is_instance_valid(room_node):
		return
	if not room_node.has_method(&"configure_room"):
		push_error("UIWorldMapRoomsContainer 的 RoomTemplate 缺少 configure_room 接口。")
		return
	room_node.call(
		&"configure_room",
		room_position,
		get_room_canvas_position(room_position),
		int(
			BRIDGE_VISIBILITY_POLICY.call(
				&"get_owned_bridge_mask",
				map_model,
				room_position,
				discovered_rooms,
				bridge_visibility_mode
			)
		),
		room_step,
		room_position == _current_room
	)


func _set_template_current_state(room_position: Vector2i, is_current_room: bool) -> void:
	var room_node: Node = _room_nodes.get(room_position, null) as Node
	if (
		room_node != null
		and is_instance_valid(room_node)
		and room_node.has_method(&"set_current_room")
	):
		room_node.call(&"set_current_room", is_current_room)


func _has_required_model_protocol(map_model: Node) -> bool:
	return (
		map_model != null
		and map_model.has_method(&"is_room_discovered")
		and map_model.has_method(&"are_rooms_connected")
	)
