extends Control
## 在目标右下角绘制局外长按进度圆环的 HUD 表现组件。
class_name WorldHoldProgressIndicator

## 在目标右下角绘制局外长按进度圆环；目标失效时回退到鼠标位置。

## 圆环中心相对目标锚点的屏幕偏移，默认零值保证四分之一圆环位于目标内。
@export var cursor_offset: Vector2 = Vector2.ZERO

## 圆环半径，单位为屏幕像素。
@export_range(8.0, 96.0, 1.0, "or_greater") var ring_radius: float = 16.0

## 圆环轨道和进度弧线的宽度，单位为屏幕像素。
@export_range(1.0, 16.0, 0.5, "or_greater") var ring_width: float = 6.0

## 未完成轨道颜色。
@export var track_color: Color = Color(0.08, 0.10, 0.14, 0.72)

## 已完成进度颜色。
@export var progress_color: Color = Color(0.35, 0.95, 0.60, 0.96)

## 当前归一化进度。
var current_progress: float = 0.0

## 当前是否应该绘制圆环。
var is_hold_progress_visible: bool = false

## 当前长按的可见锚点。
var _hold_progress_target: CanvasItem

## 返回当前长按目标的屏幕空间右下角锚点。
##
## 返回值：目标有效时为其右下角屏幕坐标，否则为当前鼠标位置。
func get_current_hold_target_screen_position() -> Vector2:
	return _resolve_hold_target_screen_position()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clear_hold_progress()


func _process(_delta: float) -> void:
	queue_redraw()


## 更新并显示归一化长按进度。
##
## 参数 progress：完成比例，会被限制在 0 到 1 之间。
## 返回值：无。
func set_hold_progress(progress: float) -> void:
	current_progress = clampf(progress, 0.0, 1.0)
	is_hold_progress_visible = true
	visible = true
	set_process(true)
	queue_redraw()


## 设置本次长按使用的可见目标。
##
## 参数 target：交互目标或其可见子节点，非 CanvasItem 时回退到鼠标位置。
## 返回值：无。
func set_hold_progress_target(target: Node) -> void:
	_hold_progress_target = target as CanvasItem
	queue_redraw()


## 清空进度、目标和绘制状态。
##
## 返回值：无。
func clear_hold_progress() -> void:
	current_progress = 0.0
	is_hold_progress_visible = false
	_hold_progress_target = null
	visible = false
	set_process(false)
	queue_redraw()


func _draw() -> void:
	if not is_hold_progress_visible:
		return

	# 圆心落在目标右下角，使四分之一圆环覆盖目标，其余部分显示在目标外。
	var center := get_current_hold_target_screen_position() + cursor_offset
	var start_angle := -PI / 2.0
	draw_arc(center, ring_radius, start_angle, start_angle + TAU, 48, track_color, ring_width, true)
	if current_progress > 0.0:
		draw_arc(
			center,
			ring_radius,
			start_angle,
			start_angle + TAU * current_progress,
			48,
			progress_color,
			ring_width,
			true
		)


func _resolve_hold_target_screen_position() -> Vector2:
	if _hold_progress_target == null or not is_instance_valid(_hold_progress_target):
		return get_viewport().get_mouse_position()

	if _hold_progress_target is Sprite2D:
		var sprite := _hold_progress_target as Sprite2D
		return sprite.get_screen_transform() * sprite.get_rect().end

	if _hold_progress_target is Control:
		var control := _hold_progress_target as Control
		return control.get_screen_transform() * control.size

	return _hold_progress_target.get_screen_transform().origin
