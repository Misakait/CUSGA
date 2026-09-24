extends PanelContainer

## 背包、仓库和出战卡组共用的 GDScript 生产槽位视图。
##
## 槽位只展示当前 ItemStack、生成拖拽载荷并转发快捷输入；库存接收、移动和装备卸下
## 规则继续由 InventoryComponent / EquipmentComponent 权威处理。

const DRAGGABLE_DATA_SCRIPT: GDScript = preload("res://core/ui/draggable/draggable_data.gd")
const ITEM_DATA_COMPAT: GDScript = preload("res://resources/item/item_data_compat.gd")
const ITEM_TOOLTIP_PRESENTER_SCRIPT: GDScript = preload("res://core/ui/item_tooltip_presenter.gd")

## 拖拽载荷协议字段：载荷必须暴露 StringName 类型的来源系统标签。
## 用字段协议而不是脚本路径判定，使 GDScript 生产载荷与旧 C# DraggableData 垫片都能通过。
const DRAG_PAYLOAD_SOURCE_FIELD: StringName = &"SourceSystem"

## 快捷点击类型；整数值保持 C# SlotShortcutKind 的 0、1 协议。
enum SlotShortcutKind {
	ShiftClick = 0,
	AltClick = 1,
}

var _my_index: int = 0
var _item_stack_in_this_slot: RefCounted = null
var _inventory_component: Node = null
var _tooltip_presenter: RefCounted = ITEM_TOOLTIP_PRESENTER_SCRIPT.call("Empty") as RefCounted
var _shortcut_handler: Callable = Callable()
## 可选左键菜单回调，由拥有槽位的 UI 决定可用操作。
var _use_handler: Callable = Callable()
## 仅在普通左键按下后等待松开，避免菜单抢占拖拽和快捷键。
var _item_click_pending: bool = false
var _is_pointer_inside: bool = false
var _icon: TextureRect = null
var _amount_label: Label = null

## 当前绑定的库存槽位索引。
## 返回值：InventoryComponent 中的稳定槽位索引。
var SlotIndex: int:
	get:
		return _my_index

## 当前绑定的库存组件。
## 返回值：背包、仓库或出战卡组组件；尚未绑定时为空。
var Inventory: Node:
	get:
		return _inventory_component

## 当前渲染的 ItemStack。
## 返回值：原始堆叠引用；尚未绑定时为空。
var CurrentStack: RefCounted:
	get:
		return _item_stack_in_this_slot


## 解析生产场景中的图标和数量节点，并建立尺寸与悬停连接。
## 返回值：无。
func _ready() -> void:
	_icon = get_node("ItemIcon") as TextureRect
	_amount_label = get_node("AmountLabel") as Label
	if not resized.is_connected(_on_resized):
		resized.connect(_on_resized)
	if not mouse_entered.is_connected(_on_mouse_entered):
		mouse_entered.connect(_on_mouse_entered)
	if not mouse_exited.is_connected(_on_mouse_exited):
		mouse_exited.connect(_on_mouse_exited)


## 将槽位绑定到库存索引、堆叠与其所属组件。
## 参数 index：库存中的真实槽位索引。
## 参数 stack：该索引当前持有的新旧 ItemStack。
## 参数 inventory：拥有该堆叠的 InventoryComponent。
## 返回值：无。
func Bind(index: int, stack: Variant, inventory: Node) -> void:
	if _my_index == index and _item_stack_in_this_slot == stack and _inventory_component == inventory:
		return
	_disconnect_stack_signal()
	_my_index = index
	_item_stack_in_this_slot = stack as RefCounted
	_inventory_component = inventory
	_connect_stack_signal()
	_update_visuals(_item_stack_in_this_slot)


## 设置物品提示框 Presenter；空值回退到共享空 Presenter。
## 参数 tooltip_presenter：并行 ItemTooltipPresenter 或空值。
## 返回值：无。
func SetTooltipPresenter(tooltip_presenter: Variant) -> void:
	_tooltip_presenter = tooltip_presenter as RefCounted
	if _tooltip_presenter == null:
		_tooltip_presenter = ITEM_TOOLTIP_PRESENTER_SCRIPT.call("Empty") as RefCounted


## 设置 Shift/Alt 左键快捷处理器。
## 参数 shortcut_handler：接收当前 SlotUI 与 SlotShortcutKind 整数值的 Callable。
## 返回值：无。
func SetShortcutHandler(shortcut_handler: Callable) -> void:
	_shortcut_handler = shortcut_handler


## 设置左键菜单处理器；handler 接收当前 SlotUI 并返回是否处理，无返回值。
func SetUseHandler(handler: Callable) -> void:
	_use_handler = handler


## 解除本视图建立的信号连接并隐藏提示框。
## 返回值：无。
func _exit_tree() -> void:
	if resized.is_connected(_on_resized):
		resized.disconnect(_on_resized)
	if mouse_entered.is_connected(_on_mouse_entered):
		mouse_entered.disconnect(_on_mouse_entered)
	if mouse_exited.is_connected(_on_mouse_exited):
		mouse_exited.disconnect(_on_mouse_exited)
	_disconnect_stack_signal()
	_tooltip_presenter.call("Hide")


## 处理 Shift/Alt 左键并把已处理事件交给 Godot 停止传播。
## 参数 event：槽位收到的 GUI 输入事件。
## 返回值：无。
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
	# 松开才打开菜单；拖拽开始时会撤销标记，避免拖动结束误弹菜单。
	var open_menu: bool = _item_click_pending and not get_viewport().gui_is_dragging() \
		and Rect2(Vector2.ZERO, size).has_point(event.position)
	_item_click_pending = false
	if open_menu and _use_handler.is_valid() and bool(_use_handler.call(self)):
		_tooltip_presenter.call("Hide")
		accept_event()


## 创建库存拖拽载荷和预览；空槽位不开始拖拽。
## 参数 _at_position：Godot 提供的局部鼠标坐标。
## 返回值：DraggableData；空槽返回 null。
func _get_drag_data(_at_position: Vector2) -> Variant:
	_item_click_pending = false
	var payload: Variant = _build_drag_data()
	if payload == null:
		return null
	set_drag_preview(_create_drag_preview())
	_icon.modulate = Color(1.0, 1.0, 1.0, 0.3)
	_tooltip_presenter.call("Hide")
	return payload


## 把库存接收或装备卸下合法性委托给对应组件。
## 参数 _at_position：Godot 提供的局部鼠标坐标。
## 参数 data：旧 C# 或并行 GDScript DraggableData。
## 返回值：目标库存能够接收载荷时为 true。
func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if _inventory_component == null or not _is_draggable_data(data):
		return false
	var drag_data: Object = data as Object
	var source_inventory: Variant = drag_data.get("SourceInventory")
	if source_inventory != null:
		return bool(_inventory_component.call("CanReceiveItemFrom", source_inventory, int(drag_data.get("FromIndex")), _my_index))
	var source_equipment: Variant = drag_data.get("SourceEquipment")
	if source_equipment != null:
		return bool(source_equipment.call("CanUnequipToInventory", int(drag_data.get("FromEquipmentSlot")), _inventory_component, _my_index))
	return false


## 把库存移动或装备卸下操作委托给对应组件。
## 参数 _at_position：Godot 提供的局部鼠标坐标。
## 参数 data：已经通过 `_can_drop_data` 检查的拖拽载荷。
## 返回值：无。
func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if _inventory_component == null or not _is_draggable_data(data):
		return
	var drag_data: Object = data as Object
	var source_inventory: Variant = drag_data.get("SourceInventory")
	if source_inventory != null:
		_inventory_component.call("MoveItemFrom", source_inventory, int(drag_data.get("FromIndex")), _my_index)
		return
	var source_equipment: Variant = drag_data.get("SourceEquipment")
	if source_equipment != null:
		source_equipment.call("UnequipToInventory", int(drag_data.get("FromEquipmentSlot")), _inventory_component, _my_index)


## 拖拽结束后恢复图标透明度和当前内容。
func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_BEGIN:
		_item_click_pending = false
	if what == NOTIFICATION_DRAG_END:
		_update_visuals(_item_stack_in_this_slot)


## 保持格子高度等于当前宽度。
func _on_resized() -> void:
	if not is_equal_approx(custom_minimum_size.y, size.x):
		custom_minimum_size = Vector2(custom_minimum_size.x, size.x)


## 识别并转发 Shift/Alt 左键；供 GUI 入口与聚焦契约共同验证。
func _handle_shortcut_input(event: InputEvent) -> bool:
	if not (event is InputEventMouseButton):
		return false
	var mouse_event: InputEventMouseButton = event as InputEventMouseButton
	if not mouse_event.pressed or mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return false
	if mouse_event.alt_pressed:
		if _shortcut_handler.is_valid():
			_shortcut_handler.call(self, int(SlotShortcutKind.AltClick))
		return true
	if mouse_event.shift_pressed:
		if _shortcut_handler.is_valid():
			_shortcut_handler.call(self, int(SlotShortcutKind.ShiftClick))
		return true
	return false


## 创建当前库存格载荷；不复制堆叠或物品 Resource。
func _build_drag_data() -> Variant:
	if _inventory_component == null or _stack_is_empty(_item_stack_in_this_slot):
		return null
	var payload: RefCounted = DRAGGABLE_DATA_SCRIPT.new()
	var source_system: Variant = _inventory_component.get("DragSourceSystem")
	payload.set("SourceSystem", &"SystemInventory" if source_system == null else StringName(source_system))
	payload.set("FromIndex", _my_index)
	payload.set("SourceInventory", _inventory_component)
	payload.set("HeldStack", _item_stack_in_this_slot)
	return payload


## 创建保持旧尺寸、居中方式和透明度的拖拽图标。
func _create_drag_preview() -> Control:
	var preview_icon := TextureRect.new()
	preview_icon.texture = _stack_icon(_item_stack_in_this_slot)
	preview_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview_icon.custom_minimum_size = Vector2(64.0, 64.0)
	preview_icon.modulate = Color(1.0, 1.0, 1.0, 0.8)
	preview_icon.position = -preview_icon.custom_minimum_size / 2.0
	var preview_wrapper := Control.new()
	preview_wrapper.add_child(preview_icon)
	return preview_wrapper


## 刷新图标、数量和悬停提示框。
func _update_visuals(stack: Variant = null) -> void:
	if _icon == null or _amount_label == null:
		return
	if _stack_is_empty(stack):
		_icon.texture = null
		_amount_label.text = ""
	else:
		_icon.texture = _stack_icon(stack)
		var amount: int = int((stack as Object).get("Amount"))
		_amount_label.text = str(amount) if amount > 1 else ""
	_icon.modulate = Color.WHITE
	if _is_pointer_inside:
		_tooltip_presenter.call("Show", stack)


## 鼠标进入时立即显示当前堆叠提示。
func _on_mouse_entered() -> void:
	_is_pointer_inside = true
	_tooltip_presenter.call("Show", _item_stack_in_this_slot)


## 鼠标离开时隐藏提示框。
func _on_mouse_exited() -> void:
	_is_pointer_inside = false
	_item_click_pending = false
	_tooltip_presenter.call("Hide")


## 连接 GDScript ItemStack 的变化信号；没有 Godot 信号的兼容对象仍可在 Bind 时刷新。
func _connect_stack_signal() -> void:
	if _item_stack_in_this_slot == null or not _item_stack_in_this_slot.has_signal("OnStackChanged"):
		return
	var callback := Callable(self, "_update_visuals")
	if not _item_stack_in_this_slot.is_connected("OnStackChanged", callback):
		_item_stack_in_this_slot.connect("OnStackChanged", callback)


## 解除当前 ItemStack 变化信号。
func _disconnect_stack_signal() -> void:
	if _item_stack_in_this_slot == null or not _item_stack_in_this_slot.has_signal("OnStackChanged"):
		return
	var callback := Callable(self, "_update_visuals")
	if _item_stack_in_this_slot.is_connected("OnStackChanged", callback):
		_item_stack_in_this_slot.disconnect("OnStackChanged", callback)


## 判断对象是否为新旧 DraggableData，避免读取其他系统的任意拖拽对象。
##
## 判定只看字段协议：载荷暴露 StringName 类型的 SourceSystem。C# DraggableData 的
## 属性不出现在 get_property_list() 里，但按名 get() 依然可用，因此这里必须用
## 取值类型探测而不是属性表扫描；缺失字段的普通对象取值为 null。
##
## @param value 待判断的对象。
## @return 属于拖拽载荷协议时返回 true。
func _is_draggable_data(value: Variant) -> bool:
	if not (value is Object):
		return false

	return typeof((value as Object).get(DRAG_PAYLOAD_SOURCE_FIELD)) == TYPE_STRING_NAME


## 判断 ItemStack 当前是否为空。
func _stack_is_empty(stack: Variant) -> bool:
	return stack == null or not (stack is Object) or bool((stack as Object).get("IsEmpty"))


## 读取 ItemStack 的物品图标，兼容新旧 ItemData。
func _stack_icon(stack: Variant) -> Texture2D:
	if _stack_is_empty(stack):
		return null
	var item: Variant = (stack as Object).get("Item")
	return ITEM_DATA_COMPAT.call("get_display_icon", item, null) as Texture2D
