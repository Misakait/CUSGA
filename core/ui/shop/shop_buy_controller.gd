extends RefCounted

## 购买区拥有商品详情和数量输入，只在现有购买按钮发出提交意图。
const COMPAT: GDScript = preload("res://resources/item/item_data_compat.gd")

signal purchase_requested(item: Resource, quantity: int)

var _view: Node
var _item: Resource
var _quantity: SpinBox
var _button: Button
var _icon: TextureRect

## 绑定现有购买区。参数 view 为 BuyArea；返回无，仅首次绑定时连接按钮。
func bind(view: Node) -> void:
	if _view == view:
		return
	if is_instance_valid(_button) and _button.pressed.is_connected(request_purchase):
		_button.pressed.disconnect(request_purchase)
	if is_instance_valid(_icon) and _icon.gui_input.is_connected(_on_icon_gui_input):
		_icon.gui_input.disconnect(_on_icon_gui_input)
	_view = view
	_quantity = view.get_node("BuyCount/SpinBox") as SpinBox
	_button = view.get_node("Buy/BuyButton") as Button
	_button.pressed.connect(request_purchase)
	_icon = view.get_node("ItemIcon") as TextureRect
	_icon.mouse_filter = Control.MOUSE_FILTER_STOP
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if not _icon.gui_input.is_connected(_on_icon_gui_input):
		_icon.gui_input.connect(_on_icon_gui_input)
	clear()

## 显示所选商品。参数 item 为原资源、unit_price 为原桥接单价；返回无，不触发购买。
func show_item(item: Resource, unit_price: int) -> void:
	_item = item
	(_view.get_node("ItemIcon") as TextureRect).texture = COMPAT.call("get_display_icon", item, null) as Texture2D
	(_view.get_node("NameContainer/NameLabel") as Label).text = String(COMPAT.call("get_display_name", item, "请选择商品"))
	(_view.get_node("PriceContainer/PriceLabel") as Label).text = "单价：%d" % unit_price if item != null else "单价：—"
	(_view.get_node("DescriptionContainer/DescriptionLabel") as Label).text = String(COMPAT.call("get_display_description", item, ""))
	_button.disabled = item == null or unit_price <= 0

## 清除临时商品和数量；返回无。
func clear() -> void:
	if not is_instance_valid(_view):
		return
	_quantity.value = 0
	show_item(null, 0)

## 提交购买意图；返回无，先吸收尚未失焦的文本，数量为零也交给协调者显示提示。
func request_purchase() -> void:
	_quantity.apply()
	purchase_requested.emit(_item, int(_quantity.value))

## 处理购买区图标右键；右键只清除待购买详情，不影响左侧仓库选中状态。
func _on_icon_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT and (event as InputEventMouseButton).pressed:
		clear()
		_icon.accept_event()
