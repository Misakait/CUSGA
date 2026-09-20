extends PanelContainer

## 单个装备槽的 GDScript 生产 UI。
##
## 本视图只渲染堆叠、生成拖拽载荷并把合法性与状态修改委托给 EquipmentComponent；
## 不复制装备规则，并通过无 out 参数读取桥兼容当前 C# EquipmentComponent。

const DRAGGABLE_DATA_SCRIPT: GDScript = preload("res://core/ui/draggable/draggable_data.gd")
const ITEM_DATA_COMPAT: GDScript = preload("res://resources/item/item_data_compat.gd")
const ITEM_TOOLTIP_PRESENTER_SCRIPT: GDScript = preload("res://core/ui/item_tooltip_presenter.gd")

const LEGACY_DRAGGABLE_DATA_PATH: String = "res://core/ui/draggable/DraggableData.cs"
const GD_DRAGGABLE_DATA_PATH: String = "res://core/ui/draggable/draggable_data.gd"
const EQUIPMENT_DRAG_SOURCE: StringName = &"SystemEquipment"

var _slot: int = 0
var _equipment: Node = null
var _stack: RefCounted = null
var _icon: TextureRect = null
var _amount_label: Label = null
var _slot_label: Label = null
var _tooltip_presenter: RefCounted = ITEM_TOOLTIP_PRESENTER_SCRIPT.call("Empty") as RefCounted
var _is_ready: bool = false
var _is_pointer_inside: bool = false


## 解析原场景中的三个必需子节点并建立鼠标悬停连接。
## 返回值：无。
func _ready() -> void:
	_icon = get_node("MarginContainer/VBoxContainer/ItemIcon") as TextureRect
	_amount_label = get_node("MarginContainer/VBoxContainer/AmountLabel") as Label
	_slot_label = get_node("MarginContainer/VBoxContainer/SlotLabel") as Label
	if not mouse_entered.is_connected(_on_mouse_entered):
		mouse_entered.connect(_on_mouse_entered)
	if not mouse_exited.is_connected(_on_mouse_exited):
		mouse_exited.connect(_on_mouse_exited)
	_is_ready = true
	_refresh_view()


## 绑定装备组件和槽位，并读取该槽当前的 ItemStack。
## 参数 equipment：实现装备槽查询与拖拽操作的 EquipmentComponent。
## 参数 slot：EquipmentSlot 的稳定整数值。
## 返回值：无。
func Bind(equipment: Node, slot: int) -> void:
	_disconnect_stack_signal()
	_equipment = equipment
	_slot = slot
	_stack = _read_equipped_stack()
	_connect_stack_signal()
	_refresh_view()


## 设置物品提示框 Presenter；空值回退到共享空 Presenter。
## 参数 tooltip_presenter：GDScript ItemTooltipPresenter 或空值。
## 返回值：无。
func SetTooltipPresenter(tooltip_presenter: Variant) -> void:
	_tooltip_presenter = tooltip_presenter as RefCounted
	if _tooltip_presenter == null:
		_tooltip_presenter = ITEM_TOOLTIP_PRESENTER_SCRIPT.call("Empty") as RefCounted


## 解除本视图建立的信号连接并隐藏提示框。
## 返回值：无。
func _exit_tree() -> void:
	if mouse_entered.is_connected(_on_mouse_entered):
		mouse_entered.disconnect(_on_mouse_entered)
	if mouse_exited.is_connected(_on_mouse_exited):
		mouse_exited.disconnect(_on_mouse_exited)
	_disconnect_stack_signal()
	_tooltip_presenter.call("Hide")


## 创建装备拖拽载荷和预览；空槽位不开始拖拽。
## 参数 _at_position：Godot 提供的局部鼠标坐标，本视图无需参与规则判断。
## 返回值：DraggableData；空槽返回 null。
func _get_drag_data(_at_position: Vector2) -> Variant:
	var payload: Variant = _build_drag_data()
	if payload == null:
		return null
	set_drag_preview(_create_drag_preview())
	_icon.modulate = Color(1.0, 1.0, 1.0, 0.3)
	_tooltip_presenter.call("Hide")
	return payload


## 把拖拽合法性委托给绑定的 EquipmentComponent。
## 参数 _at_position：Godot 提供的局部鼠标坐标。
## 参数 data：旧 C# 或并行 GDScript DraggableData。
## 返回值：组件允许库存装备或装备槽互换时为 true。
func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if _equipment == null or not _is_draggable_data(data):
		return false
	var drag_data: Object = data as Object
	var source_inventory: Variant = drag_data.get("SourceInventory")
	if source_inventory != null:
		return bool(_equipment.call("CanEquipFromInventory", source_inventory, int(drag_data.get("FromIndex")), _slot))
	var source_equipment: Variant = drag_data.get("SourceEquipment")
	if source_equipment != null:
		return source_equipment == _equipment \
			and bool(_equipment.call("CanMoveEquipment", int(drag_data.get("FromEquipmentSlot")), _slot))
	return false


## 把库存装备或槽位互换操作委托给绑定的 EquipmentComponent。
## 参数 _at_position：Godot 提供的局部鼠标坐标。
## 参数 data：已经通过 `_can_drop_data` 检查的拖拽载荷。
## 返回值：无。
func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if _equipment == null or not _is_draggable_data(data):
		return
	var drag_data: Object = data as Object
	var source_inventory: Variant = drag_data.get("SourceInventory")
	if source_inventory != null:
		_equipment.call("EquipFromInventory", source_inventory, int(drag_data.get("FromIndex")), _slot)
		return
	var source_equipment: Variant = drag_data.get("SourceEquipment")
	if source_equipment == _equipment:
		_equipment.call("MoveEquipment", int(drag_data.get("FromEquipmentSlot")), _slot)


## 拖拽结束后恢复图标透明度和当前内容。
func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		_update_visuals(_stack)


## 创建当前装备槽的载荷；供引擎拖拽入口与聚焦契约共同验证。
func _build_drag_data() -> Variant:
	if _equipment == null or _stack_is_empty(_stack):
		return null
	var payload: RefCounted = DRAGGABLE_DATA_SCRIPT.new()
	payload.set("SourceSystem", EQUIPMENT_DRAG_SOURCE)
	payload.set("SourceEquipment", _equipment)
	payload.set("FromEquipmentSlot", _slot)
	payload.set("HeldStack", _stack)
	return payload


## 创建保持旧尺寸、居中方式和透明度的拖拽图标。
func _create_drag_preview() -> Control:
	var preview_icon := TextureRect.new()
	preview_icon.texture = _stack_icon(_stack)
	preview_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview_icon.custom_minimum_size = Vector2(64.0, 64.0)
	preview_icon.modulate = Color(1.0, 1.0, 1.0, 0.8)
	preview_icon.position = -preview_icon.custom_minimum_size / 2.0
	var preview_wrapper := Control.new()
	preview_wrapper.add_child(preview_icon)
	return preview_wrapper


## 从组件读取当前装备；优先使用无 out 参数桥，再兼容并行 GDScript 查询签名。
func _read_equipped_stack() -> RefCounted:
	if _equipment == null:
		return null
	if _method_accepts_argument_count(_equipment, &"GetEquippedStack", 1):
		return _equipment.call("GetEquippedStack", _slot) as RefCounted
	if _method_accepts_argument_count(_equipment, &"TryGetEquippedStack", 1):
		return _equipment.call("TryGetEquippedStack", _slot) as RefCounted
	return null


## 刷新图标、数量和悬停提示框。
func _update_visuals(stack: Variant = null) -> void:
	if not _is_ready:
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


## 刷新固定槽位文案和当前堆叠视觉。
func _refresh_view() -> void:
	if not _is_ready:
		return
	_slot_label.text = _get_slot_label(_slot)
	_update_visuals(_stack)


## 鼠标进入时立即显示当前堆叠提示。
func _on_mouse_entered() -> void:
	_is_pointer_inside = true
	_tooltip_presenter.call("Show", _stack)


## 鼠标离开时隐藏提示框。
func _on_mouse_exited() -> void:
	_is_pointer_inside = false
	_tooltip_presenter.call("Hide")


## 连接 GDScript ItemStack 的变化信号；没有 Godot 信号的兼容对象仍可在 Bind 时刷新。
func _connect_stack_signal() -> void:
	if _stack == null or not _stack.has_signal("OnStackChanged"):
		return
	var callback := Callable(self, "_update_visuals")
	if not _stack.is_connected("OnStackChanged", callback):
		_stack.connect("OnStackChanged", callback)


## 解除当前 ItemStack 变化信号。
func _disconnect_stack_signal() -> void:
	if _stack == null or not _stack.has_signal("OnStackChanged"):
		return
	var callback := Callable(self, "_update_visuals")
	if _stack.is_connected("OnStackChanged", callback):
		_stack.disconnect("OnStackChanged", callback)


## 判断对象是否为新旧 DraggableData，避免读取其他系统的任意拖拽对象。
func _is_draggable_data(value: Variant) -> bool:
	if not (value is Object):
		return false
	var script: Script = (value as Object).get_script() as Script
	if script == null:
		return false
	return script.resource_path == GD_DRAGGABLE_DATA_PATH or script.resource_path == LEGACY_DRAGGABLE_DATA_PATH


## 判断动态组件的方法是否具有当前可调用的参数数量。
func _method_accepts_argument_count(object: Object, method_name: StringName, count: int) -> bool:
	for method_info in object.get_method_list():
		if not (method_info is Dictionary) or StringName(method_info.get("name", "")) != method_name:
			continue
		var arguments: Variant = method_info.get("args")
		return arguments is Array and (arguments as Array).size() == count
	return false


## 判断 ItemStack 当前是否为空。
func _stack_is_empty(stack: Variant) -> bool:
	return stack == null or not (stack is Object) or bool((stack as Object).get("IsEmpty"))


## 读取 ItemStack 的物品图标，兼容新旧 ItemData。
func _stack_icon(stack: Variant) -> Texture2D:
	if _stack_is_empty(stack):
		return null
	var item: Variant = (stack as Object).get("Item")
	return ITEM_DATA_COMPAT.call("get_display_icon", item, null) as Texture2D


## 把稳定槽位整数转换为原界面中文标签。
func _get_slot_label(slot: int) -> String:
	match slot:
		0: return "头盔"
		1: return "胸甲"
		2: return "护腿"
		3: return "靴子"
		4: return "武器"
		5: return "斧头"
		6: return "镐子"
		7: return "鱼竿"
		8: return "左护手"
		9: return "右护手"
		10: return "火把"
		11: return "吊坠"
		12: return "戒指一"
		13: return "戒指二"
		14: return "腰带"
		15: return "魔法物品"
		_: return str(slot)
