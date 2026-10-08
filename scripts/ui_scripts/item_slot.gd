class_name ItemSlot
extends Button

## 物品显示字段的跨语言读取边界。
const ITEM_DATA_COMPAT: GDScript = preload("res://resources/item/item_data_compat.gd")
## 背包与装备拖拽载荷。
const DRAGGABLE_DATA_SCRIPT: GDScript = preload("res://core/ui/draggable/draggable_data.gd")
## 共享提示框 Presenter。
const ITEM_TOOLTIP_PRESENTER_SCRIPT: GDScript = preload("res://core/ui/item_tooltip_presenter.gd")

## 玩家点击该格子时发出。
## @param slot 被点击的格子自身。
signal slot_clicked(slot: Button)

## Shift 单击快捷类型；数值保持旧 C# SlotShortcutKind 协议。
enum SlotShortcutKind { ShiftClick = 0, AltClick = 1 }

## 拖拽载荷字段协议。
const DRAG_PAYLOAD_SOURCE_FIELD: StringName = &"SourceSystem"
## 装备拖拽来源标识。
const EQUIPMENT_DRAG_SOURCE: StringName = &"SystemEquipment"

## 当前展示的物品；空格为 null。
var item_data: Resource = null
## 当前展示的数量。
var item_count: int = 0
## 仓库/商店兼容的价格语义。
var price_kind: StringName = &"buy"

## 当前绑定的库存组件；没有绑定时为 null。
var _inventory_component: Node = null
## 当前绑定的装备组件；没有绑定时为 null。
var _equipment_component: Node = null
## 当前库存槽位索引。
var _slot_index: int = -1
## 当前装备槽位索引。
var _equipment_slot: int = -1
## 当前 ItemStack 引用。
var _current_stack: Variant = null
## 左键快捷处理器。
var _shortcut_handler: Callable = Callable()
## 普通左键菜单处理器。
var _use_handler: Callable = Callable()
## 共享 Tooltip Presenter。
var _tooltip_presenter: RefCounted = ITEM_TOOLTIP_PRESENTER_SCRIPT.call("Empty") as RefCounted
## 是否显示数量。
var _show_count: bool = true
## 是否显示价格。
var _show_price: bool = true
## 空格是否仍可接收拖拽。
var _allow_empty_drop: bool = false
## 普通点击等待状态，避免拖拽结束误弹菜单。
var _item_click_pending: bool = false
## 鼠标是否停留在格子上。
var _is_pointer_inside: bool = false

var _icon: TextureRect = null
var _count_label: Label = null
var _name_label: Label = null
var _price_label: Label = null
var _empty_label: String = ""

## 当前库存槽位索引。
## @return int 绑定的库存索引。
var SlotIndex: int:
	get:
		return _slot_index

## 当前绑定的库存组件。
## @return Node 背包或出战卡组组件。
var Inventory: Node:
	get:
		return _inventory_component

## 当前渲染的 ItemStack。
## @return Variant 原始堆叠引用。
var CurrentStack: Variant:
	get:
		return _current_stack

## 绑定到库存组件，启用库存拖拽和快捷输入。
## @param index 库存槽位索引。
## @param stack 当前堆叠，可以为空。
## @param inventory 拥有该堆叠的组件。
## @param shortcut_handler Shift/Alt 快捷回调。
## @param use_handler 普通左键菜单回调。
## @param tooltip_presenter 共享提示框 Presenter。
func bind_inventory(index: int, stack: Variant, inventory: Node, shortcut_handler: Callable = Callable(), use_handler: Callable = Callable(), tooltip_presenter: Variant = null) -> void:
	_disconnect_stack_signal()
	_inventory_component = inventory
	_equipment_component = null
	_slot_index = index
	_equipment_slot = -1
	_current_stack = stack
	_shortcut_handler = shortcut_handler
	_use_handler = use_handler
	_allow_empty_drop = inventory != null
	_set_tooltip_presenter(tooltip_presenter)
	_connect_stack_signal()
	_bind_stack_visual(stack)

## 绑定到装备组件，启用装备拖拽与装备槽互换。
## @param equipment 装备组件。
## @param slot 装备槽位稳定整数值。
## @param tooltip_presenter 共享提示框 Presenter。
func bind_equipment(equipment: Node, slot: int, tooltip_presenter: Variant = null) -> void:
	_disconnect_stack_signal()
	_inventory_component = null
	_equipment_component = equipment
	_slot_index = -1
	_equipment_slot = slot
	_shortcut_handler = Callable()
	_use_handler = Callable()
	_allow_empty_drop = equipment != null
	_set_tooltip_presenter(tooltip_presenter)
	_current_stack = _read_equipped_stack()
	_connect_stack_signal()
	_bind_stack_visual(_current_stack)

## 保留局外仓库与商店使用的旧绑定签名。
## @param item 要显示的物品。
## @param amount 物品数量。
## @param price 价格；小于等于 0 时隐藏价格。
## @param kind `buy` 或 `sell`。
func bind(item: Resource, amount: int, price: int, kind: StringName) -> void:
	_disconnect_stack_signal()
	_inventory_component = null
	_equipment_component = null
	_slot_index = -1
	_equipment_slot = -1
	_current_stack = null
	_allow_empty_drop = false
	price_kind = kind
	if item == null:
		clear_slot()
		return
	_resolve_nodes()
	item_data = item
	item_count = amount
	_icon.texture = ITEM_DATA_COMPAT.call("get_display_icon", item, null) as Texture2D
	_name_label.text = _resolve_display_name(item)
	disabled = false
	_count_label.text = "x%d" % amount
	_count_label.visible = _show_count and kind == &"sell"
	_price_label.text = ("卖 %d" % price) if kind == &"sell" else ("买 %d" % price)
	_price_label.visible = _show_price and price > 0

## 配置数量和价格标签的可见性。
## @param show_count 是否显示 CountLabel。
## @param show_price 是否显示 PriceLabel。
func configure_display(show_count: bool, show_price: bool) -> void:
	_show_count = show_count
	_show_price = show_price
	_resolve_nodes()
	_count_label.visible = _show_count and item_data != null and price_kind == &"sell"
	_price_label.visible = _show_price and item_data != null and _price_label.text != ""

## 设置当前界面的紧凑布局比例。
## @param scale_factor 相对于仓库/商店默认格子尺寸的比例；背包使用 0.5。
func configure_compact_layout(scale_factor: float) -> void:
	var factor: float = clampf(scale_factor, 0.25, 1.0)
	custom_minimum_size = Vector2(96.0, 104.0) * factor
	# 直接收缩子控件，避免根节点的缩放和 GridContainer 的布局尺寸不一致。
	scale = Vector2.ONE
	_resolve_nodes()
	_icon.position = Vector2(16.0, 2.0) * factor
	_icon.size = Vector2(64.0, 64.0) * factor
	_count_label.position = Vector2(50.0, 1.0) * factor
	_count_label.size = Vector2(42.0, 20.0) * factor
	_name_label.position = Vector2(1.0, 66.0) * factor
	_name_label.size = Vector2(94.0, 19.0) * factor
	_price_label.position = Vector2(1.0, 84.0) * factor
	_price_label.size = Vector2(94.0, 18.0) * factor
	_count_label.add_theme_font_size_override("font_size", maxi(roundi(13.0 * factor), 1))
	_name_label.add_theme_font_size_override("font_size", maxi(roundi(18.0 * factor), 1))
	_price_label.add_theme_font_size_override("font_size", maxi(roundi(16.0 * factor), 1))

## 设置提示框 Presenter；空值使用空 Presenter。
## @param tooltip_presenter Presenter 或 null。
func set_tooltip_presenter(tooltip_presenter: Variant) -> void:
	_set_tooltip_presenter(tooltip_presenter)

## 兼容旧 SlotUI 的大写入口。
## @param tooltip_presenter Presenter 或 null。
func SetTooltipPresenter(tooltip_presenter: Variant) -> void:
	set_tooltip_presenter(tooltip_presenter)

## 设置 Shift/Alt 快捷处理器。
## @param shortcut_handler 接收当前 ItemSlot 和快捷类型整数。
func set_shortcut_handler(shortcut_handler: Callable) -> void:
	_shortcut_handler = shortcut_handler

## 兼容旧 SlotUI 的大写入口。
## @param shortcut_handler 接收当前 ItemSlot 和快捷类型整数。
func SetShortcutHandler(shortcut_handler: Callable) -> void:
	set_shortcut_handler(shortcut_handler)

## 设置普通左键菜单处理器。
## @param use_handler 接收当前 ItemSlot 并返回是否已处理。
func set_use_handler(use_handler: Callable) -> void:
	_use_handler = use_handler

## 兼容旧 SlotUI 的大写入口。
## @param use_handler 接收当前 ItemSlot 并返回是否已处理。
func SetUseHandler(use_handler: Callable) -> void:
	set_use_handler(use_handler)

## 设置空槽位的占位文字；用于角色装备区标注装备类型。
## @param text 空槽位显示文字。
func set_empty_label(label_text: String) -> void:
	_empty_label = label_text
	if item_data == null:
		_resolve_nodes()
		_name_label.text = label_text

## 清空格子并根据绑定模式决定是否保留拖拽接收能力。
func clear_slot() -> void:
	_resolve_nodes()
	item_data = null
	item_count = 0
	_icon.texture = null
	_icon.modulate = Color.WHITE
	_name_label.text = _empty_label
	_count_label.visible = false
	_price_label.visible = false
	button_pressed = false
	disabled = not _allow_empty_drop

## 设置选中态。
## @param selected 是否选中。
func set_selected(selected: bool) -> void:
	button_pressed = selected

## 读取选中态。
## @return bool 是否选中。
func is_selected() -> bool:
	return button_pressed

func _ready() -> void:
	toggle_mode = true
	if not pressed.is_connected(_on_pressed):
		pressed.connect(_on_pressed)
	if not mouse_entered.is_connected(_on_mouse_entered):
		mouse_entered.connect(_on_mouse_entered)
	if not mouse_exited.is_connected(_on_mouse_exited):
		mouse_exited.connect(_on_mouse_exited)
	clear_slot()

func _resolve_nodes() -> void:
	if _icon != null:
		return
	_icon = get_node_or_null("Icon") as TextureRect
	_count_label = get_node_or_null("CountLabel") as Label
	_name_label = get_node_or_null("NameLabel") as Label
	_price_label = get_node_or_null("PriceLabel") as Label
	if _icon == null or _count_label == null or _name_label == null or _price_label == null:
		push_error("ItemSlot: 场景节点结构与脚本预期不符，请检查 Icon / CountLabel / NameLabel / PriceLabel。")

func _bind_stack_visual(stack: Variant) -> void:
	_resolve_nodes()
	if _stack_is_empty(stack):
		clear_slot()
		return
	var item: Resource = _stack_item(stack)
	if item == null:
		clear_slot()
		return
	price_kind = &"sell"
	item_data = item
	item_count = int((stack as Object).get("Amount"))
	_icon.texture = ITEM_DATA_COMPAT.call("get_display_icon", item, null) as Texture2D
	_name_label.text = _resolve_display_name(item)
	_count_label.text = "x%d" % item_count
	_count_label.visible = _show_count
	_price_label.visible = false
	disabled = false

func _on_pressed() -> void:
	if item_data != null:
		slot_clicked.emit(self)

func _gui_input(event: InputEvent) -> void:
	if _handle_shortcut_input(event):
		_item_click_pending = false
		accept_event()
		return
	if not (event is InputEventMouseButton) or event.button_index != MOUSE_BUTTON_LEFT:
		return
	if event.pressed:
		_item_click_pending = not event.ctrl_pressed and not event.meta_pressed
		return
	var open_menu: bool = _item_click_pending and not get_viewport().gui_is_dragging() \
		and Rect2(Vector2.ZERO, size).has_point(event.position)
	_item_click_pending = false
	if open_menu and _use_handler.is_valid() and bool(_use_handler.call(self)):
		_tooltip_presenter.call("Hide")
		accept_event()

func _get_drag_data(_at_position: Vector2) -> Variant:
	_item_click_pending = false
	var payload: Variant = _build_drag_data()
	if payload == null:
		return null
	set_drag_preview(_create_drag_preview())
	_icon.modulate = Color(1.0, 1.0, 1.0, 0.3)
	_tooltip_presenter.call("Hide")
	return payload

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if not _is_draggable_data(data):
		return false
	var drag_data: Object = data as Object
	if _inventory_component != null:
		var source_inventory: Variant = drag_data.get("SourceInventory")
		if source_inventory != null:
			return bool(_inventory_component.call("CanReceiveItemFrom", source_inventory, int(drag_data.get("FromIndex")), _slot_index))
		var source_equipment: Variant = drag_data.get("SourceEquipment")
		if source_equipment != null:
			return bool(source_equipment.call("CanUnequipToInventory", int(drag_data.get("FromEquipmentSlot")), _inventory_component, _slot_index))
	if _equipment_component != null:
		var source_inventory: Variant = drag_data.get("SourceInventory")
		if source_inventory != null:
			return bool(_equipment_component.call("CanEquipFromInventory", source_inventory, int(drag_data.get("FromIndex")), _equipment_slot))
		var source_equipment: Variant = drag_data.get("SourceEquipment")
		return source_equipment == _equipment_component and bool(_equipment_component.call("CanMoveEquipment", int(drag_data.get("FromEquipmentSlot")), _equipment_slot))
	return false

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if not _is_draggable_data(data):
		return
	var drag_data: Object = data as Object
	if _inventory_component != null:
		var source_inventory: Variant = drag_data.get("SourceInventory")
		if source_inventory != null:
			_inventory_component.call("MoveItemFrom", source_inventory, int(drag_data.get("FromIndex")), _slot_index)
			return
		var source_equipment: Variant = drag_data.get("SourceEquipment")
		if source_equipment != null:
			source_equipment.call("UnequipToInventory", int(drag_data.get("FromEquipmentSlot")), _inventory_component, _slot_index)
			return
	if _equipment_component != null:
		var source_inventory: Variant = drag_data.get("SourceInventory")
		if source_inventory != null:
			_equipment_component.call("EquipFromInventory", source_inventory, int(drag_data.get("FromIndex")), _equipment_slot)
			return
		var source_equipment: Variant = drag_data.get("SourceEquipment")
		if source_equipment == _equipment_component:
			_equipment_component.call("MoveEquipment", int(drag_data.get("FromEquipmentSlot")), _equipment_slot)

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_BEGIN:
		_item_click_pending = false
	if what == NOTIFICATION_DRAG_END:
		_bind_stack_visual(_current_stack)

func _handle_shortcut_input(event: InputEvent) -> bool:
	if not (event is InputEventMouseButton) or not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
		return false
	if event.alt_pressed:
		if _shortcut_handler.is_valid():
			_shortcut_handler.call(self, int(SlotShortcutKind.AltClick))
		return true
	if event.shift_pressed:
		if _shortcut_handler.is_valid():
			_shortcut_handler.call(self, int(SlotShortcutKind.ShiftClick))
		return true
	return false

func _build_drag_data() -> Variant:
	if _stack_is_empty(_current_stack):
		return null
	var payload: RefCounted = DRAGGABLE_DATA_SCRIPT.new()
	if _inventory_component != null:
		var source_system: Variant = _inventory_component.get("DragSourceSystem")
		payload.set("SourceSystem", &"SystemInventory" if source_system == null else StringName(source_system))
		payload.set("FromIndex", _slot_index)
		payload.set("SourceInventory", _inventory_component)
	else:
		payload.set("SourceSystem", EQUIPMENT_DRAG_SOURCE)
		payload.set("SourceEquipment", _equipment_component)
		payload.set("FromEquipmentSlot", _equipment_slot)
	payload.set("HeldStack", _current_stack)
	return payload

func _create_drag_preview() -> Control:
	var preview_icon := TextureRect.new()
	preview_icon.texture = _stack_icon(_current_stack)
	preview_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview_icon.custom_minimum_size = Vector2(64.0, 64.0)
	preview_icon.modulate = Color(1.0, 1.0, 1.0, 0.8)
	preview_icon.position = -preview_icon.custom_minimum_size / 2.0
	var wrapper := Control.new()
	wrapper.add_child(preview_icon)
	return wrapper

func _read_equipped_stack() -> Variant:
	if _equipment_component == null:
		return null
	if _equipment_component.has_method("GetEquippedStack"):
		return _equipment_component.call("GetEquippedStack", _equipment_slot)
	if _equipment_component.has_method("TryGetEquippedStack"):
		return _equipment_component.call("TryGetEquippedStack", _equipment_slot)
	return null

func _connect_stack_signal() -> void:
	if not (_current_stack is Object) or not (_current_stack as Object).has_signal("OnStackChanged"):
		return
	var callback := Callable(self, "_on_stack_changed")
	if not (_current_stack as Object).is_connected("OnStackChanged", callback):
		(_current_stack as Object).connect("OnStackChanged", callback)

func _disconnect_stack_signal() -> void:
	if not (_current_stack is Object) or not (_current_stack as Object).has_signal("OnStackChanged"):
		return
	var callback := Callable(self, "_on_stack_changed")
	if (_current_stack as Object).is_connected("OnStackChanged", callback):
		(_current_stack as Object).disconnect("OnStackChanged", callback)

func _on_stack_changed(_value: Variant = null) -> void:
	_bind_stack_visual(_current_stack)

func _on_mouse_entered() -> void:
	_is_pointer_inside = true
	if item_data != null:
		_tooltip_presenter.call("Show", _current_stack if _current_stack != null else item_data)

func _on_mouse_exited() -> void:
	_is_pointer_inside = false
	_item_click_pending = false
	_tooltip_presenter.call("Hide")
	if _icon != null:
		_icon.modulate = Color.WHITE

func _set_tooltip_presenter(tooltip_presenter: Variant) -> void:
	_tooltip_presenter = tooltip_presenter as RefCounted
	if _tooltip_presenter == null:
		_tooltip_presenter = ITEM_TOOLTIP_PRESENTER_SCRIPT.call("Empty") as RefCounted

func _resolve_display_name(item: Resource) -> String:
	var card_id: StringName = ITEM_DATA_COMPAT.call("get_card_id", item, &"")
	return String(ITEM_DATA_COMPAT.call("get_display_name", item, String(card_id)))

func _stack_is_empty(stack: Variant) -> bool:
	return stack == null or not (stack is Object) or bool((stack as Object).get("IsEmpty"))

func _stack_item(stack: Variant) -> Resource:
	if _stack_is_empty(stack):
		return null
	return (stack as Object).get("Item") as Resource

func _stack_icon(stack: Variant) -> Texture2D:
	var item: Resource = _stack_item(stack)
	return null if item == null else ITEM_DATA_COMPAT.call("get_display_icon", item, null) as Texture2D

func _is_draggable_data(value: Variant) -> bool:
	return value is Object and typeof((value as Object).get(DRAG_PAYLOAD_SOURCE_FIELD)) == TYPE_STRING_NAME

func _exit_tree() -> void:
	_disconnect_stack_signal()
	_tooltip_presenter.call("Hide")
