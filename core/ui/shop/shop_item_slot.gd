extends Button

## 商店独立的 item_slot2 适配，不更改共享仓库格子的样式或输入协议。
const COMPAT: GDScript = preload("res://resources/item/item_data_compat.gd")
const CREATE_DRAG: StringName = &"create_drag_data"

signal slot_clicked(slot: Button)
signal drag_started

var side: StringName
var slot_index: int = -1
var _controller: Node
var _item: Resource
var _amount: int = 0

func _ready() -> void:
	# 空格仍需禁用输入，但共享场景未定义禁用样式，沿用原底图以免回退为灰色按钮。
	add_theme_stylebox_override("disabled", get_theme_stylebox("normal"))
	pressed.connect(func() -> void: slot_clicked.emit(self))
	for child: Node in get_children():
		if child is Control:
			(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE

## 绑定来源。参数 controller 为根协调者、new_side 为区域、index 为槽位；返回无。
func configure(controller: Node, new_side: StringName, index: int) -> void:
	_controller = controller
	side = new_side
	slot_index = index

## 显示内容。参数 entry 为物品、数量和单价快照；返回无，商品只显示价格不伪造持有数量。
func bind_content(entry: Dictionary) -> void:
	_item = entry.get("item") as Resource
	_amount = int(entry.get("amount", 0))
	var occupied: bool = _item != null and (side == &"goods" or _amount > 0)
	(get_node("Icon") as TextureRect).texture = COMPAT.call("get_display_icon", _item, null) as Texture2D if occupied else null
	(get_node("NameLabel") as Label).text = String(COMPAT.call("get_display_name", _item, "")) if occupied else ""
	(get_node("CountLabel") as Label).text = "x%d" % _amount if occupied and side == &"warehouse" else ""
	var price: Label = get_node("PriceLabel") as Label
	price.visible = occupied and side == &"goods"
	price.text = "单价%d" % int(entry.get("price", 0))
	disabled = not occupied
	if side == &"goods":
		custom_minimum_size.y = 94.0

## 设置持续选择。参数 selected 为是否选中；返回无，保留原生按钮样式。
func set_selected(selected: bool) -> void:
	set_pressed_no_signal(selected)

## 读取持续选择；返回当前按钮切换状态。
func is_selected() -> bool:
	return button_pressed

func _get_drag_data(_at_position: Vector2) -> Variant:
	if side != &"warehouse" or _item == null or _amount <= 0 or not is_instance_valid(_controller) or not _controller.has_method(CREATE_DRAG):
		return null
	var data: Dictionary = _controller.call(CREATE_DRAG, side, slot_index)
	if data.is_empty():
		return null
	drag_started.emit()
	var preview: TextureRect = TextureRect.new()
	preview.texture = (get_node("Icon") as TextureRect).texture
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.custom_minimum_size = Vector2(56, 56)
	set_drag_preview(preview)
	return data
