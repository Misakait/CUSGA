extends RefCounted

## 出售区保存短期待售快照，接收拖放和改变数量只更新显示。
const COMPAT: GDScript = preload("res://resources/item/item_data_compat.gd")
const CAN_DROP: StringName = &"can_drop_item"
const GET_PRICE: StringName = &"get_sell_price"

signal sale_requested(source: Dictionary, quantity: int)

var _view: Node
var _controller: Node
var _icon: TextureRect
var _quantity: SpinBox
var _notice: Label
var _source: Dictionary = {}

## 绑定现有出售区。参数 view 为 SellArea、controller 为根；返回无。
func bind(view: Node, controller: Node) -> void:
	_view = view
	_controller = controller
	_icon = view.get_node("ItemIcon") as TextureRect
	_quantity = view.get_node("SpinBox") as SpinBox
	_notice = view.get_node("ScrollContainer/Notice") as Label
	_icon.call("bind", self)
	clear()

## 读取待售快照；返回独立字典，防止调用方修改区域状态。
func source() -> Dictionary:
	return _source.duplicate(true)

## 预检载荷。参数 data 为拖放快照；返回当前根协调者是否允许接收。
func can_accept(data: Dictionary) -> bool:
	return is_instance_valid(_controller) and _controller.has_method(CAN_DROP) and bool(_controller.call(CAN_DROP, data))

## 接收或更换图标。参数 data 为快照；返回是否接收成功，不扣库存也不发交易信号。
func accept_drop(data: Dictionary) -> bool:
	if not can_accept(data):
		show_notice("物品已变化，请重新拖入", true)
		return false
	_source = data.duplicate(true)
	var item: Resource = data.get("item") as Resource
	_icon.texture = COMPAT.call("get_display_icon", item, null) as Texture2D
	_icon.call("cancel_click")
	var unit_price: int = int(_controller.call(GET_PRICE, item)) if _controller.has_method(GET_PRICE) else 0
	(_view.get_node("PriceLabel") as Label).text = "售价：%d" % unit_price
	show_notice("选择数量后点击图标出售", false)
	return true

## 清除临时待售内容。参数 message 为清除后提示；返回无。
func clear(message: String = "拖进物品以售卖") -> void:
	_source.clear()
	if not is_instance_valid(_view):
		return
	_icon.call("cancel_click")
	_icon.texture = null
	_quantity.value = 0
	(_view.get_node("PriceLabel") as Label).text = "售价：—"
	show_notice(message, false)

## 显示交易反馈。参数 message 为文案、error 为是否失败；返回无。
func show_notice(message: String, error: bool = false) -> void:
	_notice.text = message
	_notice.modulate = Color(1.0, 0.45, 0.45) if error else Color.WHITE

## 发出独立图标点击的出售意图；返回无，读取已提交文本，不根据纹理变化推断点击。
func request_sale() -> void:
	_quantity.apply()
	sale_requested.emit(source(), int(_quantity.value))
