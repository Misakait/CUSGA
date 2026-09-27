extends Control

## 大地图视口的拖拽、缩放与点击坐标控制器。
##
## 该组件只修改 LargeMap 自己的 WorldMapCanvas 变换，不读取或修改地图 Model。

signal canvas_left_clicked(canvas_position: Vector2)
signal canvas_right_clicked(canvas_position: Vector2)

## WorldMapCanvas 相对于本节点的路径。
@export var map_canvas_path: NodePath = ^"WorldMapCanvas"
## 大地图最小缩放倍率。
@export_range(0.05, 8.0, 0.05) var minimum_zoom: float = 0.5
## 大地图最大缩放倍率。
@export_range(0.05, 8.0, 0.05) var maximum_zoom: float = 4.0
## 每格滚轮改变的缩放倍率。
@export_range(0.01, 2.0, 0.01) var zoom_step: float = 0.25
## 鼠标移动超过该像素距离后才把按压视为拖拽。
@export_range(0.0, 64.0, 0.5) var drag_threshold: float = 6.0
## 初次显示大地图时使用的缩放倍率。
@export_range(0.05, 8.0, 0.05) var initial_zoom: float = 1.5

var _map_canvas: Control = null
var _drag_origin: Vector2 = Vector2.ZERO
var _canvas_origin: Vector2 = Vector2.ZERO
var _left_pressed: bool = false
var _dragging: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	_map_canvas = get_node_or_null(map_canvas_path) as Control
	set_zoom(initial_zoom, size / 2.0)


func _gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null:
		_handle_mouse_button(button)
		accept_event()
		return
	var motion := event as InputEventMouseMotion
	if motion != null and _left_pressed:
		if not _dragging and motion.position.distance_to(_drag_origin) >= drag_threshold:
			_dragging = true
		if _dragging and _map_canvas != null:
			_map_canvas.position = _canvas_origin + motion.position - _drag_origin
		accept_event()


## 围绕视口内指定点设置缩放，保持鼠标下的画布点不漂移。
##
## @param requested_zoom 希望使用的缩放倍率，会被导出上下限夹取。
## @param viewport_point 需要保持稳定的视口局部坐标。
## @return 实际应用的缩放倍率。
func set_zoom(requested_zoom: float, viewport_point: Vector2) -> float:
	if _map_canvas == null:
		_map_canvas = get_node_or_null(map_canvas_path) as Control
	if _map_canvas == null:
		return 1.0
	var lower: float = minf(minimum_zoom, maximum_zoom)
	var upper: float = maxf(minimum_zoom, maximum_zoom)
	var new_zoom: float = clampf(requested_zoom, lower, upper)
	var old_zoom: float = maxf(_map_canvas.scale.x, 0.0001)
	var canvas_point: Vector2 = (viewport_point - _map_canvas.position) / old_zoom
	_map_canvas.scale = Vector2.ONE * new_zoom
	_map_canvas.position = viewport_point - canvas_point * new_zoom
	return new_zoom


## 把指定画布局部点移动到视口中心。
##
## @param canvas_position WorldMapCanvas 内的像素坐标。
## @return 无返回值。
func focus_canvas_position(canvas_position: Vector2) -> void:
	if _map_canvas == null:
		return
	_map_canvas.position = size / 2.0 - canvas_position * _map_canvas.scale.x


## 返回当前实际缩放倍率。
##
## @return WorldMapCanvas 的统一 x/y 缩放。
func get_zoom() -> float:
	return _map_canvas.scale.x if _map_canvas != null else 1.0


## 将视口局部坐标换算为画布局部坐标。
##
## @param viewport_position ViewportControl 内的鼠标位置。
## @return WorldMapCanvas 内的局部坐标。
func viewport_to_canvas(viewport_position: Vector2) -> Vector2:
	if _map_canvas == null:
		return Vector2.ZERO
	return (viewport_position - _map_canvas.position) / maxf(_map_canvas.scale.x, 0.0001)


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
		set_zoom(get_zoom() + zoom_step, event.position)
		return
	if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
		set_zoom(get_zoom() - zoom_step, event.position)
		return
	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_left_pressed = true
			_dragging = false
			_drag_origin = event.position
			_canvas_origin = _map_canvas.position if _map_canvas != null else Vector2.ZERO
		else:
			if _left_pressed and not _dragging:
				canvas_left_clicked.emit(viewport_to_canvas(event.position))
			_left_pressed = false
			_dragging = false
		return
	if event.button_index == MOUSE_BUTTON_RIGHT and not event.pressed:
		canvas_right_clicked.emit(viewport_to_canvas(event.position))
