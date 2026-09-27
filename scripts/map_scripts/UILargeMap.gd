extends CanvasLayer

## 全屏的大地图 View。
##
## 本轮只实现 M 键开关和当前房间聚焦；拖拽、滚轮缩放、图钉与迷雾留给后续功能。

const CURRENT_ROOM_CHANGED_SIGNAL: StringName = &"current_room_changed"
const OPEN_MAP_ACTION: StringName = &"open_map"

## 大地图独立缩放倍率，不会影响小地图的画布实例。
@export_range(0.25, 4.0, 0.05) var zoom_level: float = 1.5

var _map_model: Node = null

@onready var viewport_control: Control = $ViewportControl
@onready var map_canvas: Control = $ViewportControl/WorldMapCanvas


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	map_canvas.scale = Vector2.ONE * zoom_level
	var resized_callable: Callable = Callable(self, "focus_current_room")
	if not viewport_control.is_connected(&"resized", resized_callable):
		viewport_control.connect(&"resized", resized_callable)


func _exit_tree() -> void:
	_disconnect_model()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).echo:
		return
	if not event.is_action_pressed(OPEN_MAP_ACTION):
		return
	var map_owner: CanvasItem = get_parent() as CanvasItem
	if map_owner != null and not map_owner.visible:
		return
	toggle_map()
	get_viewport().set_input_as_handled()


## 绑定地图 Model，并把同一 Model 传给内部 WorldMapCanvas。
##
## @param model 地图世界 Model。
## @return 画布与信号都绑定成功时返回 true。
func bind_model(model: Node) -> bool:
	if model == _map_model:
		focus_current_room()
		return model != null
	_disconnect_model()
	if model == null or not model.has_signal(CURRENT_ROOM_CHANGED_SIGNAL):
		push_error("UILargeMap 收到的 Model 缺少 current_room_changed 信号。")
		return false
	if not map_canvas.has_method(&"bind_model") or not bool(map_canvas.call(&"bind_model", model)):
		push_error("UILargeMap 无法绑定内部 WorldMapCanvas。")
		return false
	_map_model = model
	var callable: Callable = Callable(self, "_on_current_room_changed")
	if not _map_model.is_connected(CURRENT_ROOM_CHANGED_SIGNAL, callable):
		_map_model.connect(CURRENT_ROOM_CHANGED_SIGNAL, callable)
	return true


## 显示大地图并聚焦玩家当前房间。
##
## @return 无返回值。
func show_map() -> void:
	visible = true
	call_deferred("focus_current_room")


## 隐藏大地图。
##
## @return 无返回值。
func hide_map() -> void:
	visible = false


## 切换大地图的显示状态。
##
## @return 无返回值。
func toggle_map() -> void:
	if visible:
		hide_map()
	else:
		show_map()


## 把当前房间移动到大地图可视区域中心。
##
## @return 无返回值。
func focus_current_room() -> void:
	if _map_model == null or not map_canvas.has_method(&"get_room_canvas_position"):
		return
	var current_value: Variant = _map_model.get(&"current_position")
	if not current_value is Vector2i:
		return
	map_canvas.scale = Vector2.ONE * zoom_level
	var room_position: Vector2 = map_canvas.call(&"get_room_canvas_position", current_value)
	map_canvas.position = viewport_control.size / 2.0 - room_position * zoom_level


func _on_current_room_changed(_position: Vector2i) -> void:
	if visible:
		focus_current_room()


func _disconnect_model() -> void:
	if _map_model == null or not is_instance_valid(_map_model):
		_map_model = null
		return
	var callable: Callable = Callable(self, "_on_current_room_changed")
	if (
		_map_model.has_signal(CURRENT_ROOM_CHANGED_SIGNAL)
		and _map_model.is_connected(CURRENT_ROOM_CHANGED_SIGNAL, callable)
	):
		_map_model.disconnect(CURRENT_ROOM_CHANGED_SIGNAL, callable)
	_map_model = null
