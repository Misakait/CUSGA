class_name ItemSlot
extends Button

## 物品显示字段的跨语言读取边界。
const ITEM_DATA_COMPAT: GDScript = preload("res://resources/item/item_data_compat.gd")

## 通用物品格子的表现脚本，商店与局外仓库共用。
##
## 只负责「显示什么」和「被谁点了」两件事。选中态由使用它的界面脚本统一持有，
## 因为同一界面里的多个列表必须互斥选中：把选中态存在各自格子里会让每个列表各持一份状态，
## 需要在多处同步，任何一处漏改都会出现「多处同时亮着」的错觉。
##
## 常态与悬停直接复用 `背包格子-未选中-选中的样子.png` 的上下两帧，由 `.tscn` 里的
## StyleBoxTexture 驱动，因此这里不写任何 mouse_entered/exited 逻辑。

## 玩家点击该格子时发出。
## @param slot 被点击的格子自身，便于控制脚本知道点的是哪一个。
signal slot_clicked(slot: Button)

## 该格子当前展示的物品；为 null 表示空格子。
var item_data: Resource = null

## 该格子代表的数量，只在出售侧显示。
var item_count: int = 0

## 价格语义：&"buy" 表示这是商店商品，&"sell" 表示这是仓库物品。
## 由控制脚本在绑定时注入，让同一个格子场景能同时服务多个界面。
var price_kind: StringName = &"buy"

## 悬停时图标的提亮倍率。
## 为什么悬停不只提亮边框：格子素材的常态帧亮度 132、选中帧 157，两者只差约 19%，
## 提亮必须夹在中间才既看得出来又不至于比「选中」还亮，可调空间极窄（实测 1.12 倍几乎不可辨）。
## 图标是彩色像素画，同样的倍率肉眼立刻可辨，因此由图标承担悬停的主要可见度，
## 边框仍保持「只提亮」且严格暗于选中帧。
const HOVER_ICON_BOOST := Color(1.25, 1.25, 1.25, 1.0)

# 刻意不用 @onready：SceneManager 会在初始场景还没进树时就调用 init()，
# 那一刻格子被 add_child 到同样还没进树的网格里，不会触发 _ready，@onready 变量仍是 null。
# 子节点在 instantiate() 之后就已经存在，因此在真正用到之前按需解析一次即可。
var _icon: TextureRect = null
var _count_label: Label = null
var _name_label: Label = null
var _price_label: Label = null


func _ready() -> void:
	# 用 Button 自己的切换态承载「选中」：素材只有未选中/选中两帧，
	# 让按钮保持按下就能直接复用主题里的 pressed 样式，不必在代码里手写样式切换。
	toggle_mode = true
	pressed.connect(_on_pressed)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	clear_slot()


## 解析子节点引用。
## 幂等：已解析过就直接返回，因此可以在每个入口无脑调用。
func _resolve_nodes() -> void:
	if _icon != null:
		return

	_icon = get_node_or_null("Icon")
	_count_label = get_node_or_null("CountLabel")
	_name_label = get_node_or_null("NameLabel")
	_price_label = get_node_or_null("PriceLabel")

	if _icon == null or _count_label == null or _name_label == null or _price_label == null:
		push_error(
			"ShopSlot: 场景节点结构与脚本预期不符，请检查 Icon / CountLabel / NameLabel / PriceLabel。"
		)


## 把物品绑定到格子上。
## @param item 要展示的 GDScript 或 C# 物品 Resource；为 null 时等价于清空格子。
## @param amount 数量，出售侧会显示出来。
## @param price 该侧对应的单价；小于等于 0 时不显示价格标签。
## @param kind 价格语义，&"buy" 或 &"sell"。
func bind(item: Resource, amount: int, price: int, kind: StringName) -> void:
	if item == null:
		clear_slot()
		return

	_resolve_nodes()

	item_data = item
	item_count = amount
	price_kind = kind

	_icon.texture = ITEM_DATA_COMPAT.call("get_display_icon", item, null) as Texture2D
	_name_label.text = _resolve_display_name(item)
	disabled = false

	# 商品侧是无限库存，数量对玩家没有决策价值；只有出售侧需要显示持有量。
	if kind == &"sell":
		_count_label.text = "x%d" % amount
		_count_label.visible = true
		_price_label.text = "卖 %d" % price
	else:
		_count_label.visible = false
		_price_label.text = "买 %d" % price

	_price_label.visible = price > 0


## 清空格子并让它不可交互。
func clear_slot() -> void:
	_resolve_nodes()

	item_data = null
	item_count = 0
	_icon.texture = null
	_icon.modulate = Color.WHITE
	_name_label.text = ""
	_count_label.visible = false
	_price_label.visible = false
	button_pressed = false
	# 空格子必须禁用：否则玩家可以「选中空气」，动作区会随之出现无意义的可购买状态。
	disabled = true


## 设置选中态。
## @param selected 是否选中。
func set_selected(selected: bool) -> void:
	button_pressed = selected


## 读取该格子当前是否处于选中态。
## @return bool 选中时为 true。
func is_selected() -> bool:
	return button_pressed


## 读取格子上要显示的物品名。
## @param item 物品数据。
## @return String 显示名；CardName 为空时回退到 CardId。
## @remarks
## 既有数据里存在 CardName 为空的物品（例如 items/tool/IronSword.tres）。
## 回退到 CardId 而不是留空，是为了让这类物品在界面上仍可辨认——
## 空白格子会让玩家以为那是个坏掉的格子，也会掩盖数据问题。
func _resolve_display_name(item: Resource) -> String:
	var card_id: StringName = ITEM_DATA_COMPAT.call("get_card_id", item, &"")
	return String(ITEM_DATA_COMPAT.call("get_display_name", item, String(card_id)))


func _on_pressed() -> void:
	# 空格子已被禁用，正常不会走到这里；仍做一次防空判断，避免把空格子报给控制脚本。
	if item_data == null:
		return

	slot_clicked.emit(self)


## 鼠标进入格子：提亮图标，让「鼠标正指着这里」一目了然。
func _on_mouse_entered() -> void:
	if item_data == null:
		return
	_icon.modulate = HOVER_ICON_BOOST


## 鼠标离开格子：恢复图标原色。
func _on_mouse_exited() -> void:
	_icon.modulate = Color.WHITE
