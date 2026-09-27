extends Control

## 左上角小地图 View。
##
## 组件只负责遮罩内的缩放和居中；房间与桥的生成由 WorldMapCanvas 负责。

const CURRENT_ROOM_CHANGED_SIGNAL: StringName = &"current_room_changed"

## 小地图独立缩放倍率，不会影响大地图的画布实例。
@export_range(0.25, 4.0, 0.05) var zoom_level: float = 2.0

var _map_model: Node = null

@onready var mask_container: PanelContainer = $MaskContainer
@onready var map_canvas: Control = $MaskContainer/CanvasViewport/WorldMapCanvas


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	mask_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_canvas.scale = Vector2.ONE * zoom_level
	var resized_callable: Callable = Callable(self, "focus_current_room")
	if not mask_container.is_connected(&"resized", resized_callable):
		mask_container.connect(&"resized", resized_callable)


func _exit_tree() -> void:
	_disconnect_model()


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
		push_error("UIMiniMap 收到的 Model 缺少 current_room_changed 信号。")
		return false
	if not map_canvas.has_method(&"bind_model") or not bool(map_canvas.call(&"bind_model", model)):
		push_error("UIMiniMap 无法绑定内部 WorldMapCanvas。")
		return false
	_map_model = model
	var callable: Callable = Callable(self, "_on_current_room_changed")
	if not _map_model.is_connected(CURRENT_ROOM_CHANGED_SIGNAL, callable):
		_map_model.connect(CURRENT_ROOM_CHANGED_SIGNAL, callable)
	call_deferred("focus_current_room")
	return true


## 让当前房间保持在小地图遮罩中心。
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
	map_canvas.position = mask_container.size / 2.0 - room_position * zoom_level


func _on_current_room_changed(_position: Vector2i) -> void:
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
