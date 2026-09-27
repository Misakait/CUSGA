@tool
extends Control

## 大小地图共用画布 View。
##
## 该组件只绑定 MapWorldModel，并把探索集合与当前房间转交给 RoomsContainer。
## RoomTemplate 生命周期、房间纹理与方向桥均由下层组件负责。

const ROOM_DISCOVERED_SIGNAL: StringName = &"room_discovered"
const CURRENT_ROOM_CHANGED_SIGNAL: StringName = &"current_room_changed"
var _map_model: Node = null
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
	var current_value: Variant = _map_model.get(&"current_position")
	if current_value is Vector2i:
		_current_room = current_value
	refresh_discovered_rooms()
	return true


## 按 Model 的已探索集合增删 RoomTemplate，并刷新每个模板的桥与纹理。
##
## @return 无返回值。
func refresh_discovered_rooms() -> void:
	if _map_model == null:
		return
	var discovered_value: Variant = _map_model.call(&"get_discovered_positions")
	if not discovered_value is Array:
		push_error("UIWorldMapCanvas 无法读取已探索房间数组。")
		return
	if not rooms_container.has_method(&"refresh_rooms"):
		push_error("UIWorldMapCanvas 的 RoomsContainer 缺少 refresh_rooms 接口。")
		return
	rooms_container.call(&"refresh_rooms", _map_model, discovered_value, _current_room)


## 增量显示一个新探索房间，并重新分配相邻连接桥的模板所有权。
##
## @param room_position 新探索的地图坐标。
## @return 无返回值。
func reveal_room(room_position: Vector2i) -> void:
	if _map_model == null or not bool(_map_model.call(&"is_room_discovered", room_position)):
		return
	refresh_discovered_rooms()


## 把旧当前位置恢复为普通图标，并把新当前位置切换为红色图标。
##
## @param room_position 当前房间地图坐标。
## @return 无返回值。
func update_current_room(room_position: Vector2i) -> void:
	_current_room = room_position
	if rooms_container.has_method(&"update_current_room"):
		rooms_container.call(&"update_current_room", room_position)


## 切换连接桥的显示策略并立即刷新现有房间模板。
##
## @param mode 0 显示通往未探索邻居的真实连接；1 只显示双方都已探索的桥。
## @return 模式合法并完成刷新时返回 true，否则返回 false。
func set_bridge_visibility_mode(mode: int) -> bool:
	if not rooms_container.has_method(&"set_bridge_visibility_mode"):
		return false
	var configured: bool = bool(rooms_container.call(&"set_bridge_visibility_mode", mode))
	if configured and _map_model != null:
		refresh_discovered_rooms()
	return configured


## 将 row/column 地图坐标转换成画布局部坐标。
##
## @param room_position 地图坐标；x 为 row，y 为 column。
## @return 房间图片中心在 WorldMapCanvas 中的位置。
func get_room_canvas_position(room_position: Vector2i) -> Vector2:
	if rooms_container.has_method(&"get_room_canvas_position"):
		var position_value: Variant = rooms_container.call(
			&"get_room_canvas_position", room_position
		)
		if position_value is Vector2:
			return position_value
	return Vector2.ZERO


## 返回当前已生成的 RoomTemplate 数量。
##
## @return 房间模板节点数量。
func get_generated_room_count() -> int:
	if rooms_container.has_method(&"get_generated_room_count"):
		return int(rooms_container.call(&"get_generated_room_count"))
	return 0


## 返回所有 RoomTemplate 当前生成且已经去重的桥数量。
##
## @return BridgeContainer 直接子桥节点的合计数量。
func get_generated_bridge_count() -> int:
	if rooms_container.has_method(&"get_generated_bridge_count"):
		return int(rooms_container.call(&"get_generated_bridge_count"))
	return 0


## 返回指定房间模板当前使用的方向桥掩码。
##
## @param room_position 地图坐标。
## @return 房间模板存在时返回上、右、下、左方向掩码，否则返回 0。
func get_room_bridge_mask(room_position: Vector2i) -> int:
	if rooms_container.has_method(&"get_room_bridge_mask"):
		return int(rooms_container.call(&"get_room_bridge_mask", room_position))
	return 0


## 返回指定房间当前使用的纹理路径，供测试与运行诊断使用。
##
## @param room_position 地图坐标。
## @return 房间已生成时返回纹理资源路径，否则返回空字符串。
func get_room_texture_path(room_position: Vector2i) -> String:
	if rooms_container.has_method(&"get_room_texture_path"):
		return String(rooms_container.call(&"get_room_texture_path", room_position))
	return ""


func _on_room_discovered(room_position: Vector2i) -> void:
	reveal_room(room_position)


func _on_current_room_changed(room_position: Vector2i) -> void:
	update_current_room(room_position)


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
