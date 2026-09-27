@tool
extends Control

## 世界地图标记渲染容器。
##
## 该组件只把 MapWorldModel 的只读标记快照转换为 Sprite2D。逻辑坐标中的 x 是
## column、y 是 row；乘以房间步长后得到 WorldMapCanvas 的局部像素坐标。

const MARKERS_CHANGED_SIGNAL: StringName = &"markers_changed"

var _map_model: Node = null
var _room_step: Vector2 = Vector2(32.0, 32.0)
var _marker_nodes: Dictionary = {}


func _exit_tree() -> void:
	_disconnect_model()


## 绑定标记事实来源并立即刷新。
##
## @param model 提供 get_marker_snapshot 与 markers_changed 的地图 Model。
## @param room_step 房间中心之间的画布像素间距。
## @return 协议完整并完成绑定时返回 true。
func bind_model(model: Node, room_step: Vector2) -> bool:
	if model == _map_model:
		set_room_step(room_step)
		refresh_markers()
		return model != null
	_disconnect_model()
	if (
		model == null
		or not model.has_method(&"get_marker_snapshot")
		or not model.has_signal(MARKERS_CHANGED_SIGNAL)
	):
		return false
	_map_model = model
	set_room_step(room_step)
	var callable := Callable(self, "refresh_markers")
	if not _map_model.is_connected(MARKERS_CHANGED_SIGNAL, callable):
		_map_model.connect(MARKERS_CHANGED_SIGNAL, callable)
	refresh_markers()
	return true


## 更新逻辑坐标到画布局部坐标的换算步长。
##
## @param room_step 新的房间中心像素间距。
## @return 无返回值。
func set_room_step(room_step: Vector2) -> void:
	if room_step.x <= 0.0 or room_step.y <= 0.0:
		return
	_room_step = room_step
	refresh_markers()


## 按 Model 快照增删并更新所有标记 Sprite2D。
##
## @return 无返回值。
func refresh_markers() -> void:
	if _map_model == null or not is_instance_valid(_map_model):
		return
	var snapshot_value: Variant = _map_model.call(&"get_marker_snapshot")
	if not snapshot_value is Array:
		return
	var active_ids: Dictionary = {}
	for record_value: Variant in snapshot_value:
		if not record_value is Dictionary:
			continue
		var record: Dictionary = record_value
		var marker_id: StringName = StringName(str(record.get("id", "")))
		var config: Resource = record.get("config", null) as Resource
		var logical_position: Variant = record.get("logical_position", null)
		if marker_id == &"" or config == null or not logical_position is Vector2:
			continue
		if not _config_is_visible(config):
			continue
		var marker_node: Sprite2D = _ensure_marker(marker_id)
		marker_node.texture = config.get("icon") as Texture2D
		marker_node.position = logical_to_canvas(logical_position)
		var marker_scale: float = maxf(float(config.get("marker_scale")), 0.1)
		marker_node.scale = Vector2.ONE * marker_scale
		marker_node.visible = true
		active_ids[marker_id] = true
	for marker_id_value: Variant in _marker_nodes.keys().duplicate():
		var marker_id := StringName(str(marker_id_value))
		if active_ids.has(marker_id):
			continue
		var marker_node: Sprite2D = _marker_nodes.get(marker_id, null) as Sprite2D
		_marker_nodes.erase(marker_id)
		if marker_node != null and is_instance_valid(marker_node):
			marker_node.queue_free()


## 将逻辑地图坐标换算为 WorldMapCanvas 局部坐标。
##
## @param logical_position x 为 column、y 为 row，整数点代表房间中心。
## @return 标记在画布中的像素位置。
func logical_to_canvas(logical_position: Vector2) -> Vector2:
	return Vector2(logical_position.x * _room_step.x, logical_position.y * _room_step.y)


## 返回当前有效标记节点数量。
##
## @return PinesContainer 的标记 Sprite2D 数量。
func get_generated_marker_count() -> int:
	return _marker_nodes.size()


func _ensure_marker(marker_id: StringName) -> Sprite2D:
	var marker_node: Sprite2D = _marker_nodes.get(marker_id, null) as Sprite2D
	if marker_node != null and is_instance_valid(marker_node):
		return marker_node
	marker_node = Sprite2D.new()
	marker_node.name = "MapMarker_%s" % str(marker_id).validate_node_name()
	marker_node.centered = true
	marker_node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	marker_node.z_index = 10
	add_child(marker_node)
	_marker_nodes[marker_id] = marker_node
	return marker_node


func _config_is_visible(config: Resource) -> bool:
	return (
		bool(config.get("allow_map_display"))
		and bool(config.get("active"))
		and config.get("icon") is Texture2D
	)


func _disconnect_model() -> void:
	if _map_model != null and is_instance_valid(_map_model):
		var callable := Callable(self, "refresh_markers")
		if (
			_map_model.has_signal(MARKERS_CHANGED_SIGNAL)
			and _map_model.is_connected(MARKERS_CHANGED_SIGNAL, callable)
		):
			_map_model.disconnect(MARKERS_CHANGED_SIGNAL, callable)
	_map_model = null
