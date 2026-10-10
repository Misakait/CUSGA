extends TextureRect

## 待售图标只报告独立点击和拖放；纹理切换不产生交易意图。
const CAN_DROP: StringName = &"can_accept"
const ACCEPT_DROP: StringName = &"accept_drop"
const REQUEST_SALE: StringName = &"request_sale"

var _region: RefCounted
var _click_armed: bool = false

## 绑定出售区域。参数 region 为区域控制器；返回无。
func bind(region: RefCounted) -> void:
	_region = region
	mouse_filter = Control.MOUSE_FILTER_STOP
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED

## 清除未完成点击；返回无，离开或接收拖放时不能复用旧按下事件。
func cancel_click() -> void:
	_click_armed = false

func _gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button.button_index == MOUSE_BUTTON_RIGHT and button.pressed:
		if is_instance_valid(_region) and _region.has_method("clear"):
			_region.call("clear")
		accept_event()
		return
	if button.button_index != MOUSE_BUTTON_LEFT:
		return
	if button.pressed:
		_click_armed = not get_viewport().gui_is_dragging()
	else:
		var submit: bool = _click_armed and not get_viewport().gui_is_dragging() and Rect2(Vector2.ZERO, size).has_point(button.position)
		_click_armed = false
		if submit and is_instance_valid(_region) and _region.has_method(REQUEST_SALE):
			_region.call(REQUEST_SALE)
	accept_event()

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_BEGIN or what == NOTIFICATION_DRAG_END or what == NOTIFICATION_EXIT_TREE:
		cancel_click()

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return data is Dictionary and is_instance_valid(_region) and _region.has_method(CAN_DROP) and bool(_region.call(CAN_DROP, data))

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	# 拖放结束的松手没有在图标上独立按下，因此必须取消所有点击资格。
	cancel_click()
	if data is Dictionary and is_instance_valid(_region) and _region.has_method(ACCEPT_DROP):
		_region.call(ACCEPT_DROP, data)
