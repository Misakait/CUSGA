extends Node2D

## 场景或物品的地图标记注册控制器。
##
## 控制器读取 MarkerPoint 的全局位置，换算成带房间内小数偏移的逻辑地图坐标。
## 未探索的预加载房间只等待 room_discovered；成功注册后的记录由 Model 长期持有，
## 不会因为 3×3 视图卸载来源节点而消失。

const ROOM_DISCOVERED_SIGNAL: StringName = &"room_discovered"

## Inspector 中配置的标记类型与表现；为空时不注册标记。
@export var marker_config: Resource
## 用于计算精确位置的锚点，相对于本控制器查找。
@export var marker_point_path: NodePath = ^"MarkerPoint"
## 可选的稳定来源前缀；留空时使用所属场景路径。
@export var source_key: String = ""

var _map_model: Node = null
var _room_position: Vector2i = Vector2i.ZERO
var _has_room_identity: bool = false
var _registered: bool = false


func _ready() -> void:
	_resolve_map_model()


func _exit_tree() -> void:
	_disconnect_discovery_signal()


## 显式注入地图 Model，供通用场景和测试使用。
##
## @param model 提供探索查询与来源标记注册接口的 MapWorldModel。
## @return 协议完整时返回 true。
func bind_map_model(model: Node) -> bool:
	_disconnect_discovery_signal()
	if (
		model == null
		or not model.has_method(&"is_room_discovered")
		or not model.has_method(&"register_source_marker")
		or not model.has_signal(ROOM_DISCOVERED_SIGNAL)
	):
		_map_model = null
		return false
	_map_model = model
	_try_register_or_wait()
	return true


## 接收来源节点所属房间；根 Item 只需转交这一事实。
##
## @param room_position 房间网格坐标，x 为 row、y 为 column。
## @return 无返回值。
func set_room_identity(room_position: Vector2i) -> void:
	_room_position = room_position
	_has_room_identity = true
	_registered = false
	if _map_model == null:
		_resolve_map_model()
	_try_register_or_wait()


## 使用显式房间原点注册标记，供不在标准 RoomContentRoot 下的场景复用。
##
## @param room_position 房间网格坐标。
## @param room_origin 房间左上角的全局坐标。
## @param room_size 房间在世界中的像素尺寸。
## @return 配置有效且 Model 接受注册时返回 true。
func register_with_room_geometry(
	room_position: Vector2i, room_origin: Vector2, room_size: Vector2
) -> bool:
	_room_position = room_position
	_has_room_identity = true
	if _map_model == null:
		_resolve_map_model()
	if _map_model == null or not _map_model.call(&"is_room_discovered", room_position):
		_connect_discovery_signal()
		return false
	return _register_marker(room_origin, room_size)


func _resolve_map_model() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var model := tree.get_first_node_in_group(&"map_world_model")
	if model is Node:
		bind_map_model(model)


func _try_register_or_wait() -> void:
	if not _has_room_identity or _registered or _map_model == null:
		return
	if not bool(_map_model.call(&"is_room_discovered", _room_position)):
		_connect_discovery_signal()
		return
	_disconnect_discovery_signal()
	var room_size_value: Variant = _map_model.get("room_size")
	var room_size: Vector2 = room_size_value if room_size_value is Vector2 else Vector2.ZERO
	var room_origin: Vector2 = _find_room_origin()
	_register_marker(room_origin, room_size)


func _register_marker(room_origin: Vector2, room_size: Vector2) -> bool:
	if marker_config == null or room_size.x <= 0.0 or room_size.y <= 0.0:
		return false
	var marker_point := get_node_or_null(marker_point_path) as Node2D
	if marker_point == null:
		push_warning("UIMapMarkerController 缺少 MarkerPoint，已跳过地图标记。")
		return false
	# 先换算成以房间中心为整数点的局部偏移，再加到 column/row 逻辑坐标。
	var room_offset: Vector2 = (
		(marker_point.global_position - room_origin) / room_size - Vector2(0.5, 0.5)
	)
	var logical_position := Vector2(float(_room_position.y), float(_room_position.x)) + room_offset
	var stable_id := StringName(_build_source_id(logical_position))
	_registered = bool(
		_map_model.call(&"register_source_marker", stable_id, marker_config, logical_position)
	)
	# 重复注册返回 false 也表示 Model 已经持有同一稳定来源；来源节点无需继续监听。
	if not _registered:
		_registered = (
			_map_model.call(&"has_marker", stable_id)
			if _map_model.has_method(&"has_marker")
			else false
		)
	return _registered


func _find_room_origin() -> Vector2:
	var ancestor: Node = get_parent()
	while ancestor != null:
		if ancestor.name == &"RoomContentRoot":
			var room_root := ancestor.get_parent() as Node2D
			if room_root != null:
				return room_root.global_position
		ancestor = ancestor.get_parent()
	if _map_model != null and _map_model.has_method(&"world_origin_for"):
		var local_origin: Variant = _map_model.call(&"world_origin_for", _room_position)
		var model_parent: Node = _map_model.get_parent()
		var map_view: Node2D = null
		if model_parent != null:
			map_view = model_parent.get_node_or_null("MapInstantiator") as Node2D
		if local_origin is Vector2 and map_view != null:
			return map_view.to_global(local_origin)
	return Vector2.ZERO


func _build_source_id(logical_position: Vector2) -> String:
	var prefix: String = source_key.strip_edges()
	if prefix.is_empty():
		var scene_owner: Node = owner
		prefix = scene_owner.scene_file_path if scene_owner != null else "runtime_scene_marker"
	var marker_type: String = (
		str(marker_config.get("marker_type")) if marker_config != null else "marker"
	)
	return (
		"%s|%s|%d,%d|%.4f,%.4f"
		% [
			prefix,
			marker_type,
			_room_position.x,
			_room_position.y,
			logical_position.x,
			logical_position.y,
		]
	)


func _on_room_discovered(room_position: Vector2i) -> void:
	if room_position == _room_position:
		_try_register_or_wait()


func _connect_discovery_signal() -> void:
	if _map_model == null:
		return
	var callable := Callable(self, "_on_room_discovered")
	if not _map_model.is_connected(ROOM_DISCOVERED_SIGNAL, callable):
		_map_model.connect(ROOM_DISCOVERED_SIGNAL, callable)


func _disconnect_discovery_signal() -> void:
	if _map_model == null or not is_instance_valid(_map_model):
		return
	var callable := Callable(self, "_on_room_discovered")
	if (
		_map_model.has_signal(ROOM_DISCOVERED_SIGNAL)
		and _map_model.is_connected(ROOM_DISCOVERED_SIGNAL, callable)
	):
		_map_model.disconnect(ROOM_DISCOVERED_SIGNAL, callable)
