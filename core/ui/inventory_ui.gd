extends Control

## 玩家背包、装备与出战卡组的 GDScript 生产父面板。
##
## 面板只负责绑定组件、维护三组槽位和转发快捷请求；堆叠、装备与卡组规则继续由对应
## 组件处理，并通过稳定方法与信号兼容当前 C# 和后续 GDScript 组件。

## 共享提示框 Presenter 实现。
const ITEM_TOOLTIP_PRESENTER_SCRIPT: GDScript = preload("res://core/ui/item_tooltip_presenter.gd")
## 装备槽位的稳定整数协议。
const EQUIPMENT_TYPES: GDScript = preload("res://core/constants/equipment_types.gd")

## Shift 单击快捷类型；数值保持 C# SlotShortcutKind.ShiftClick。
const SHORTCUT_SHIFT_CLICK: int = 0
## Alt 单击快捷类型；数值保持 C# SlotShortcutKind.AltClick。
const SHORTCUT_ALT_CLICK: int = 1
## 建筑放置菜单项的稳定标识，后续物品操作可分配独立标识。
const ACTION_PLACE_BUILDING: int = 1

## 普通库存槽位场景；字段名保持现有 .tscn 序列化键。
@export var SlotPrefab: PackedScene
## 装备槽位场景；字段名保持现有 .tscn 序列化键。
@export var EquipmentSlotPrefab: PackedScene
## GameplayPort 相对路径；由 Main.tscn 实例覆盖。
@export var GameplayPortPath: NodePath
## 全局 TooltipPanel 相对路径；保持旧默认值。
@export var TooltipPanelPath: NodePath = NodePath("../../TooltipPanel")

## 角色属性摘要视图。
var _attribute_summary: Node = null
## 玩家背包槽位容器。
var _slot_grid: GridContainer = null
## 装备槽位容器。
var _equipment_slot_grid: GridContainer = null
## 出战卡组槽位容器。
var _deck_slot_grid: GridContainer = null
## UI 与游戏组件之间的请求端口。
var _gameplay_port: Node = null
## 标题栏合成按钮。
var _crafting_button: Button = null
## 所有物品槽位共享的提示框 Presenter。
var _tooltip_presenter: RefCounted = ITEM_TOOLTIP_PRESENTER_SCRIPT.call("Empty") as RefCounted
## 当前绑定的玩家背包组件。
var _player_inventory: Node = null
## 当前绑定的装备组件。
var _equipment: Node = null
## 当前绑定的出战卡组组件。
var _battle_deck: Node = null
## 玩家背包槽位是否完成首次结构同步。
var _is_inventory_initialized: bool = false
## 装备槽位是否完成首次结构同步。
var _is_equipment_initialized: bool = false
## 出战卡组槽位是否完成首次结构同步。
var _is_deck_initialized: bool = false
## 玩家背包的普通槽位视图。
var _slot_views: Array[Control] = []
## 角色装备槽位视图。
var _equipment_slot_views: Array[Control] = []
## 出战卡组的普通槽位视图。
var _deck_slot_views: Array[Control] = []
## 复用的物品操作弹窗；随背包生命周期释放。
var _item_action_menu: PopupMenu
## 打开菜单时的物品身份，确认操作时须与当前槽位再次比对。
var _menu_item: Resource
## 打开菜单时的玩家库存槽位索引；负数表示无选择。
var _menu_slot_index: int = -1


## 解析场景依赖、连接请求和按钮并保持面板初始隐藏。
## 返回值：无。
func _ready() -> void:
	var close_button := get_node("%CloseButton") as Button
	if not close_button.pressed.is_connected(Close):
		close_button.pressed.connect(Close)
	_crafting_button = get_node("%CraftingButton") as Button
	if not _crafting_button.pressed.is_connected(_on_crafting_button_pressed):
		_crafting_button.pressed.connect(_on_crafting_button_pressed)
	_attribute_summary = get_node("%AttributeSummaryUI")
	_slot_grid = get_node("%SlotGrid") as GridContainer
	_equipment_slot_grid = get_node("%EquipmentSlotGrid") as GridContainer
	_deck_slot_grid = get_node("%DeckSlotGrid") as GridContainer
	_gameplay_port = get_node(GameplayPortPath) as Node
	_tooltip_presenter = ITEM_TOOLTIP_PRESENTER_SCRIPT.new(get_node_or_null(TooltipPanelPath))
	_item_action_menu = PopupMenu.new()
	_item_action_menu.name = "ItemActionMenu"
	add_child(_item_action_menu)
	_item_action_menu.id_pressed.connect(_on_item_action_selected)
	visibility_changed.connect(_on_panel_visibility_changed)
	_connect_signal(_gameplay_port, &"InventoryToggleRequested", Callable(self, "_handle_inventory_toggle_request"))
	_connect_signal(_gameplay_port, &"InventoryNodeToggleRequested", Callable(self, "_handle_inventory_toggle_request"))
	hide()


## 响应 GameplayPort 的背包切换请求。
## 参数 inventory：请求展示的玩家背包组件。
## 返回值：无。
func _handle_inventory_toggle_request(inventory: Node) -> void:
	if inventory == null:
		push_error("InventoryUI 收到空 InventoryComponent。")
		return
	if visible:
		Close()
	else:
		Open(inventory)


## 绑定玩家组件、同步三组槽位并显示面板。
## 参数 inventory：玩家背包组件。
## 返回值：无。
func Open(inventory: Node) -> void:
	if inventory == null:
		push_error("InventoryUI.Open 收到空 InventoryComponent。")
		return
	_bind_player_inventory(inventory)
	var player: Variant = _gameplay_port.get("Player")
	if not (player is Object):
		push_error("InventoryUI 未找到 Player。")
		return
	var attributes: Variant = (player as Object).get("Attributes")
	if _attribute_summary != null and _attribute_summary.has_method("Bind"):
		_attribute_summary.call("Bind", attributes)
	_bind_equipment((player as Object).get("Equipment") as Node)
	_bind_battle_deck(_gameplay_port.get("PlayerBattleDeck") as Node)
	if _equipment == null or _battle_deck == null:
		return

	if not _is_inventory_initialized:
		_generate_slots(_slot_grid, _slot_views, _player_inventory)
		_is_inventory_initialized = true
	if not _is_equipment_initialized:
		_generate_equipment_slots()
		_is_equipment_initialized = true
	if not _is_deck_initialized:
		_generate_slots(_deck_slot_grid, _deck_slot_views, _battle_deck)
		_is_deck_initialized = true

	_rebind_inventory_slots()
	_rebind_equipment_slots()
	_rebind_deck_slots()
	show()


## 隐藏背包面板。
## 返回值：无。
func Close() -> void:
	_clear_item_menu()
	hide()


## 关闭背包后经 GameplayPort 请求打开合成界面。
func _on_crafting_button_pressed() -> void:
	Close()
	if _gameplay_port != null and _gameplay_port.has_method("RequestOpenCrafting"):
		_gameplay_port.call("RequestOpenCrafting")


## 切换玩家背包绑定并维护 InventoryChanged 连接。
func _bind_player_inventory(inventory: Node) -> void:
	if _player_inventory == inventory:
		return
	_disconnect_inventory_signal()
	_player_inventory = inventory
	_connect_signal(_player_inventory, &"InventoryChanged", Callable(self, "_on_inventory_changed"))
	_is_inventory_initialized = false


## 切换装备组件绑定并维护 EquipmentChanged 连接。
func _bind_equipment(equipment: Node) -> void:
	if equipment == null:
		push_error("InventoryUI 未找到 EquipmentComponent。")
		return
	if _equipment == equipment:
		return
	_disconnect_equipment_signal()
	_equipment = equipment
	_connect_signal(_equipment, &"EquipmentChanged", Callable(self, "_on_equipment_changed"))
	_is_equipment_initialized = false


## 切换出战卡组绑定并维护 InventoryChanged 连接。
func _bind_battle_deck(battle_deck: Node) -> void:
	if battle_deck == null:
		push_error("InventoryUI 未找到 BattleDeckComponent。")
		return
	if _battle_deck == battle_deck:
		return
	_disconnect_battle_deck_signal()
	_battle_deck = battle_deck
	_connect_signal(_battle_deck, &"InventoryChanged", Callable(self, "_on_battle_deck_changed"))
	_is_deck_initialized = false


## 重新生成全部装备槽并按稳定枚举值顺序绑定。
func _generate_equipment_slots() -> void:
	for child in _equipment_slot_grid.get_children():
		child.queue_free()
	_equipment_slot_views.clear()
	for slot_value in EQUIPMENT_TYPES.EquipmentSlot.values():
		var slot_ui := EquipmentSlotPrefab.instantiate() as Control
		_equipment_slot_grid.add_child(slot_ui)
		slot_ui.call("SetTooltipPresenter", _tooltip_presenter)
		slot_ui.call("Bind", _equipment, int(slot_value))
		_equipment_slot_views.append(slot_ui)


## 让普通槽位数量匹配库存容量；扩容时保留既有节点身份。
func _generate_slots(slot_grid: GridContainer, slot_views: Array[Control], inventory: Node) -> void:
	var capacity: int = maxi(int(inventory.get("Capacity")), 0)
	while slot_views.size() > capacity:
		var surplus_slot: Control = slot_views.pop_back()
		surplus_slot.queue_free()
	for _index in range(slot_views.size(), capacity):
		var slot_ui := SlotPrefab.instantiate() as Control
		slot_grid.add_child(slot_ui)
		slot_ui.call("SetTooltipPresenter", _tooltip_presenter)
		slot_ui.call("SetShortcutHandler", Callable(self, "_handle_slot_shortcut"))
		if slot_ui.has_method("SetUseHandler"):
			slot_ui.call("SetUseHandler", Callable(self, "_handle_slot_use"))
		slot_views.append(slot_ui)


## 重新绑定玩家背包槽位。
func _rebind_inventory_slots() -> void:
	_rebind_slots(_slot_grid, _slot_views, _player_inventory)


## 重新绑定装备槽位。
func _rebind_equipment_slots() -> void:
	var slot_values: Array = EQUIPMENT_TYPES.EquipmentSlot.values()
	if _equipment_slot_views.size() != slot_values.size():
		_generate_equipment_slots()
		return
	for index in slot_values.size():
		_equipment_slot_views[index].call("Bind", _equipment, int(slot_values[index]))


## 重新绑定出战卡组槽位。
func _rebind_deck_slots() -> void:
	_rebind_slots(_deck_slot_grid, _deck_slot_views, _battle_deck)


## 让一组普通槽位同步当前容量和 ItemStack 引用。
func _rebind_slots(slot_grid: GridContainer, slot_views: Array[Control], inventory: Node) -> void:
	if inventory == null:
		return
	var capacity: int = maxi(int(inventory.get("Capacity")), 0)
	if slot_views.size() != capacity:
		_generate_slots(slot_grid, slot_views, inventory)
	for index in slot_views.size():
		slot_views[index].call("Bind", index, inventory.call("GetStackAt", index), inventory)


## 玩家背包变化后重绑排序或替换后的堆叠引用。
func _on_inventory_changed() -> void:
	# 库存移动或排序会使弹窗中的槽位快照失效，关闭后要求重新选择。
	_clear_item_menu()
	_rebind_inventory_slots()


## 装备变化后重绑全部装备槽。
func _on_equipment_changed() -> void:
	_rebind_equipment_slots()


## 卡组变化后同步扩容与堆叠引用。
func _on_battle_deck_changed() -> void:
	_rebind_deck_slots()


## 根据来源库存和快捷类型把移动委托给组件。
func _handle_slot_shortcut(slot_ui: Variant, shortcut_kind: int) -> void:
	if not (slot_ui is Object) or _player_inventory == null or _battle_deck == null or _equipment == null:
		return
	var source_inventory := (slot_ui as Object).get("Inventory") as Node
	if source_inventory == null:
		return
	if shortcut_kind == SHORTCUT_ALT_CLICK:
		_handle_alt_click_shortcut(slot_ui, source_inventory)
		return
	_handle_shift_click_shortcut(slot_ui, source_inventory)


## 打开玩家背包物品操作菜单；slot_ui 为当前槽位，返回是否显示菜单。
func _handle_slot_use(slot_ui: Object) -> bool:
	if not is_visible_in_tree() or not is_instance_valid(_player_inventory) \
		or slot_ui.get("Inventory") != _player_inventory:
		return false
	# 重新按槽位读取库存，防止排序或移动后的旧视图使用失效堆叠。
	var stack: Variant = _player_inventory.call("GetStackAt", int(slot_ui.get("SlotIndex")))
	# 保留原物品资源身份，以便最终放置从同一种库存物品中扣牌。
	var item: Resource = _stack_item(stack)
	if item == null or _stack_is_empty(stack):
		return false
	_clear_item_menu()
	_menu_item = item
	_menu_slot_index = int(slot_ui.get("SlotIndex"))
	_item_action_menu.clear()
	_item_action_menu.add_separator(String(item.get("CardName")))
	if item.has_method("IsBuildingCard") and bool(item.call("IsBuildingCard")):
		_item_action_menu.add_item("放置", ACTION_PLACE_BUILDING)
	else:
		_item_action_menu.add_item("暂无可用操作")
		_item_action_menu.set_item_disabled(1, true)
	_item_action_menu.add_item("取消", 0)
	_tooltip_presenter.call("Hide")
	# PopupMenu 使用窗口坐标；嵌入弹窗需扣除宿主窗口屏幕原点。
	var popup_position: Vector2 = get_screen_transform() * get_local_mouse_position()
	if get_viewport().gui_embed_subwindows:
		popup_position -= Vector2(get_window().position)
	_item_action_menu.popup(Rect2i(Vector2i(popup_position), Vector2i.ZERO))
	return true


## 执行所选操作；action_id 为菜单标识，无返回值。
func _on_item_action_selected(action_id: int) -> void:
	# 捕获后立即清理，防止关闭弹窗或库存信号再次提交旧操作。
	var item: Resource = _menu_item
	# 固定原槽位索引，清理菜单快照后仍能检查当前库存身份。
	var slot_index: int = _menu_slot_index
	_clear_item_menu()
	if action_id != ACTION_PLACE_BUILDING or not is_visible_in_tree() \
		or not is_instance_valid(_player_inventory) or item == null or slot_index < 0:
		return
	# 不允许菜单打开后的移动、消耗或资源替换产生错误放置意图。
	var stack: Variant = _player_inventory.call("GetStackAt", slot_index)
	if _stack_is_empty(stack) or _stack_item(stack) != item:
		return
	if not item.has_method("IsBuildingCard") or not bool(item.call("IsBuildingCard")):
		return
	# 关闭 UI 后才请求放置，确保建筑模态门禁已解除。
	Close()
	_gameplay_port.call("RequestPlaceBuilding", item)


## 清理菜单快照并关闭弹窗，不触碰库存。
func _clear_item_menu() -> void:
	_menu_item = null
	_menu_slot_index = -1
	if is_instance_valid(_item_action_menu):
		_item_action_menu.hide()


## 外部隐藏背包时同步关闭独立弹窗。
func _on_panel_visibility_changed() -> void:
	if not is_visible_in_tree():
		_clear_item_menu()


## Alt 单击在玩家背包与出战卡组之间批量移动所有技能卡。
func _handle_alt_click_shortcut(slot_ui: Object, source_inventory: Node) -> void:
	if source_inventory == _battle_deck:
		_battle_deck.call("MoveAllMatchingStacksTo", _player_inventory, Callable(self, "_is_skill_card"))
		return
	var current_stack: Variant = slot_ui.get("CurrentStack")
	if source_inventory == _player_inventory and _is_skill_card(_stack_item(current_stack)):
		_player_inventory.call("MoveAllMatchingStacksTo", _battle_deck, Callable(self, "_is_skill_card"))


## Shift 单击移动单个技能堆叠，或把普通装备交给最佳槽位选择。
func _handle_shift_click_shortcut(slot_ui: Object, source_inventory: Node) -> void:
	var current_stack: Variant = slot_ui.get("CurrentStack")
	if _stack_is_empty(current_stack):
		return
	var item: Resource = _stack_item(current_stack)
	var slot_index: int = int(slot_ui.get("SlotIndex"))
	if source_inventory == _battle_deck and _is_skill_card(item):
		_battle_deck.call("TryMoveStackToFirstAvailableSlot", _player_inventory, slot_index)
		return
	if source_inventory != _player_inventory:
		return
	if _is_skill_card(item):
		_player_inventory.call("TryMoveStackToFirstAvailableSlot", _battle_deck, slot_index)
		return
	_equipment.call("EquipFromInventoryToBestSlot", _player_inventory, slot_index)


## 通过出战卡组的接收规则统一识别旧 C# 或并行 GDScript 技能卡。
func _is_skill_card(item: Resource) -> bool:
	return item != null and _battle_deck != null and bool(_battle_deck.call("CanAddItem", item, 1))


## 读取跨语言 ItemStack 的空状态。
func _stack_is_empty(stack: Variant) -> bool:
	return stack == null or bool(stack.get("IsEmpty"))


## 读取跨语言 ItemStack 保存的原始物品 Resource。
func _stack_item(stack: Variant) -> Resource:
	return null if stack == null else stack.get("Item") as Resource


## 解除玩家背包变化信号。
func _disconnect_inventory_signal() -> void:
	_disconnect_signal(_player_inventory, &"InventoryChanged", Callable(self, "_on_inventory_changed"))


## 解除装备变化信号。
func _disconnect_equipment_signal() -> void:
	_disconnect_signal(_equipment, &"EquipmentChanged", Callable(self, "_on_equipment_changed"))


## 解除出战卡组变化信号。
func _disconnect_battle_deck_signal() -> void:
	_disconnect_signal(_battle_deck, &"InventoryChanged", Callable(self, "_on_battle_deck_changed"))


## 退出场景时解除请求、按钮和组件信号。
## 返回值：无。
func _exit_tree() -> void:
	_disconnect_signal(_gameplay_port, &"InventoryToggleRequested", Callable(self, "_handle_inventory_toggle_request"))
	_disconnect_signal(_gameplay_port, &"InventoryNodeToggleRequested", Callable(self, "_handle_inventory_toggle_request"))
	if _crafting_button != null and _crafting_button.pressed.is_connected(_on_crafting_button_pressed):
		_crafting_button.pressed.disconnect(_on_crafting_button_pressed)
	_disconnect_inventory_signal()
	_disconnect_equipment_signal()
	_disconnect_battle_deck_signal()


## 在新旧 Godot Node 上安全连接指定信号。
func _connect_signal(source: Node, signal_name: StringName, callback: Callable) -> void:
	if source != null and source.has_signal(signal_name) and not source.is_connected(signal_name, callback):
		source.connect(signal_name, callback)


## 在新旧 Godot Node 上安全解除指定信号。
func _disconnect_signal(source: Node, signal_name: StringName, callback: Callable) -> void:
	if source != null and source.has_signal(signal_name) and source.is_connected(signal_name, callback):
		source.disconnect(signal_name, callback)
