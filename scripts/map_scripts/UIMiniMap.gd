extends Control

## 左上角小地图 View。
##
## 组件只负责遮罩内的缩放和居中；房间与桥的生成由 WorldMapCanvas 负责。

const CURRENT_ROOM_CHANGED_SIGNAL: StringName = &"current_room_changed"
const SETTINGS_SECTION: String = "map"
const MINIMAP_ZOOM_KEY: String = "minimap_zoom"

## 小地图独立缩放倍率，不会影响大地图的画布实例。
@export_range(0.25, 4.0, 0.05) var zoom_level: float = 2.0
## 换房时画布移动到新中心所需的秒数。
@export_range(0.0, 2.0, 0.01) var transition_duration: float = 0.28

var _map_model: Node = null
var _focus_tween: Tween = null

@onready var mask_container: PanelContainer = $MaskContainer
@onready var map_canvas: Control = $MaskContainer/CanvasViewport/WorldMapCanvas


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	mask_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_load_zoom_preference()
	map_canvas.scale = Vector2.ONE * zoom_level
	var resized_callable: Callable = Callable(self, "focus_current_room")
	if not mask_container.is_connected(&"resized", resized_callable):
		mask_container.connect(&"resized", resized_callable)
	if SettingsManager.has_signal(&"setting_changed"):
		var setting_callable := Callable(self, "_on_setting_changed")
		if not SettingsManager.is_connected(&"setting_changed", setting_callable):
			SettingsManager.connect(&"setting_changed", setting_callable)


func _exit_tree() -> void:
	_stop_focus_tween()
	var setting_callable := Callable(self, "_on_setting_changed")
	if (
		SettingsManager.has_signal(&"setting_changed")
		and SettingsManager.is_connected(&"setting_changed", setting_callable)
	):
		SettingsManager.disconnect(&"setting_changed", setting_callable)
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
## @param animated 是否使用导出的过渡时长平滑移动。
## @return 无返回值。
func focus_current_room(animated: bool = false) -> void:
	if _map_model == null or not map_canvas.has_method(&"get_room_canvas_position"):
		return
	var current_value: Variant = _map_model.get(&"current_position")
	if not current_value is Vector2i:
		return
	map_canvas.scale = Vector2.ONE * zoom_level
	var room_position: Vector2 = map_canvas.call(&"get_room_canvas_position", current_value)
	var target_position: Vector2 = mask_container.size / 2.0 - room_position * zoom_level
	_stop_focus_tween()
	if not animated or transition_duration <= 0.0 or not is_inside_tree():
		map_canvas.position = target_position
		return
	_focus_tween = create_tween()
	_focus_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_focus_tween.tween_property(map_canvas, "position", target_position, transition_duration)


func _on_current_room_changed(_position: Vector2i) -> void:
	focus_current_room(true)


func _load_zoom_preference() -> void:
	var saved_value: Variant = SettingsManager.get_setting(
		SETTINGS_SECTION, MINIMAP_ZOOM_KEY, zoom_level
	)
	if saved_value is float or saved_value is int:
		zoom_level = clampf(float(saved_value), 0.25, 4.0)


func _on_setting_changed(section: String, key: String, value: Variant) -> void:
	if section != SETTINGS_SECTION or key != MINIMAP_ZOOM_KEY:
		return
	if not (value is float or value is int):
		return
	zoom_level = clampf(float(value), 0.25, 4.0)
	focus_current_room(false)


func _stop_focus_tween() -> void:
	if _focus_tween != null and _focus_tween.is_valid():
		_focus_tween.kill()
	_focus_tween = null


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
