extends Button

## item_slot2 的内容和输入适配；不覆盖场景已经配置的按钮样式。
const ITEM_COMPAT: GDScript = preload("res://resources/item/item_data_compat.gd")

signal slot_clicked(slot: Button)
signal drag_started

var side: StringName
var slot_index: int = -1
var _controller: Node
var _item: Resource
var _amount: int = 0

func _ready() -> void:
	pressed.connect(func() -> void: slot_clicked.emit(self))
	for child: Node in get_children():
		if child is Control:
			(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE

## 绑定位置和交互协调者。参数 controller 为根控制器、new_side 为区域、index 为位置；返回无。
func configure(controller: Node, new_side: StringName, index: int) -> void:
	_controller = controller
	side = new_side
	slot_index = index

## 刷新内容。参数 item 为原资源、amount 为数量；返回无，空槽仍可接收拖放。
func bind_content(item: Resource, amount: int) -> void:
	_item = item
	_amount = amount
	var occupied: bool = item != null and amount > 0
	(get_node("Icon") as TextureRect).texture = ITEM_COMPAT.call("get_display_icon", item, null) as Texture2D if occupied else null
	(get_node("NameLabel") as Label).text = String(ITEM_COMPAT.call("get_display_name", item, "")) if occupied else ""
	(get_node("CountLabel") as Label).text = "x%d" % amount if occupied else ""

## 设置原生切换按钮的选中状态。参数 selected 为是否选中；返回无。
func set_selected(selected: bool) -> void:
	set_pressed_no_signal(selected)

## 查询选中状态；返回原生按钮状态。
func is_selected() -> bool:
	return button_pressed

func _get_drag_data(_at_position: Vector2) -> Variant:
	if _item == null or _amount <= 0 or not is_instance_valid(_controller):
		return null
	var data: Dictionary = _controller.call("create_drag_data", side, slot_index)
	if data.is_empty():
		return null
	drag_started.emit()
	var preview := TextureRect.new()
	preview.texture = (get_node("Icon") as TextureRect).texture
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.custom_minimum_size = Vector2(56, 56)
	set_drag_preview(preview)
	return data

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return is_instance_valid(_controller) and data is Dictionary and bool(_controller.call("can_drop_item", data, side, slot_index))

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if data is Dictionary and is_instance_valid(_controller):
		_controller.call("drop_item", data, side, slot_index)
