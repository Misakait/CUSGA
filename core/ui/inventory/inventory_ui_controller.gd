extends Control

## 新美术背包场景的根 Controller。
## 根节点只协调生命周期、依赖和跨区域快捷操作；容量、装备和卡组规则仍由组件 Model 负责。

const ITEM_TOOLTIP_PRESENTER_SCRIPT: GDScript = preload("res://core/ui/item_tooltip_presenter.gd")
const TOOLTIP_PANEL_SCENE: PackedScene = preload("res://scenes/ui_scenes/TooltipPanel.tscn")
const EQUIPMENT_TYPES: GDScript = preload("res://core/constants/equipment_types.gd")

## Shift 单击快捷类型；数值保持旧协议。
const SHORTCUT_SHIFT_CLICK: int = 0
## Alt 单击快捷类型；数值保持旧协议。
const SHORTCUT_ALT_CLICK: int = 1
## 建筑放置菜单项标识。
const ACTION_PLACE_BUILDING: int = 1
const SETTINGS_SECTION: String = "inventory"
const SHOW_SELECTED_INFO_KEY: String = "show_selected_item_info"

## GameplayPort 相对路径；由 Main.tscn 实例覆盖。
@export var GameplayPortPath: NodePath
## HUDRoot 下共享 TooltipPanel 的相对路径。
@export var TooltipPanelPath: NodePath = NodePath("../../TooltipPanel")

var _attribute_summary: Node = null
var _slot_grid: GridContainer = null
var _equipment_slot_grid: GridContainer = null
var _deck_slot_grid: GridContainer = null
var _gameplay_port: Node = null
var _crafting_button: Button = null
var _inventory_section: Node = null
var _equipment_section: Node = null
var _deck_section: Node = null
var _tooltip_presenter: RefCounted = ITEM_TOOLTIP_PRESENTER_SCRIPT.call("Empty") as RefCounted
var _tooltip_panel: Node = null
var _selected_tooltip_panel: TooltipPanel = null
var _selected_tooltip_presenter: RefCounted = ITEM_TOOLTIP_PRESENTER_SCRIPT.call("Empty") as RefCounted
var _displayed_selected_slot: ItemSlot = null
var _displayed_selected_item: Resource = null
var _displayed_hover_slot: ItemSlot = null
var _displayed_hover_item: Resource = null
var _player_inventory: Node = null
var _equipment: Node = null
var _battle_deck: Node = null
var _settings_manager: Node = null
var _show_selected_item_info: bool = true
var _selected_slot: ItemSlot = null
var _hovered_slot: ItemSlot = null
var _suppressed_hover_slot: ItemSlot = null

## 兼容旧测试和迁移期调用方的三个视图数组。
var _slot_views: Array = []
var _equipment_slot_views: Array = []
var _deck_slot_views: Array = []

var _item_action_menu: PopupMenu = null
var _menu_item: Resource = null
var _menu_slot_index: int = -1

## 解析新场景节点，连接请求并保持初始隐藏。
func _ready() -> void:
	_slot_grid = get_node_or_null("Item/ScrollContainer/SlotGrid") as GridContainer
	_equipment_slot_grid = get_node_or_null("PlayerShow/ScrollContainer/EquipmentSlotGrid") as GridContainer
	_deck_slot_grid = get_node_or_null("Deck/ScrollContainer/DeckSlotGrid") as GridContainer
	_inventory_section = _slot_grid
	_equipment_section = _equipment_slot_grid
	_deck_section = _deck_slot_grid
	_attribute_summary = get_node_or_null("Other/AttributeSummaryUI")
	_gameplay_port = get_node_or_null(GameplayPortPath) if not GameplayPortPath.is_empty() else null
	_tooltip_panel = get_node_or_null(TooltipPanelPath)
	_tooltip_presenter = ITEM_TOOLTIP_PRESENTER_SCRIPT.new(_tooltip_panel)
	if _tooltip_panel != null:
		# 固定提示与全局悬停提示并存，仍复用同一个 TooltipPanel 场景和 Presenter 协议。
		_selected_tooltip_panel = TOOLTIP_PANEL_SCENE.instantiate() as TooltipPanel
		_selected_tooltip_panel.name = "InventorySelectedTooltipPanel"
		# 自己拥有固定面板，避免场景父节点在建立子节点期间拒绝添加兄弟节点。
		add_child(_selected_tooltip_panel)
		# 这个实例只归背包所有，不能被其它全局悬停组件当成共享提示框选中。
		_selected_tooltip_panel.remove_from_group("tooltip_panel")
		_selected_tooltip_presenter = ITEM_TOOLTIP_PRESENTER_SCRIPT.new(_selected_tooltip_panel)
	_settings_manager = get_node_or_null(^"/root/SettingsManager")
	if _settings_manager != null:
		var saved_value: Variant = _settings_manager.call("get_setting", SETTINGS_SECTION, SHOW_SELECTED_INFO_KEY, true)
		_show_selected_item_info = saved_value if saved_value is bool else true
		_connect_signal(_settings_manager, &"setting_changed", Callable(self, "_on_setting_changed"))
	_item_action_menu = PopupMenu.new()
	_item_action_menu.name = "ItemActionMenu"
	add_child(_item_action_menu)
	_item_action_menu.id_pressed.connect(_on_item_action_selected)
	_item_action_menu.popup_hide.connect(_refresh_tooltip)
	visibility_changed.connect(_on_panel_visibility_changed)
	var close_button: Button = get_node_or_null("CloseButton") as Button
	if close_button != null and not close_button.pressed.is_connected(Close):
		close_button.pressed.connect(Close)
	_crafting_button = get_node_or_null("CraftingButton") as Button
	if _crafting_button != null and not _crafting_button.pressed.is_connected(_on_crafting_button_pressed):
		_crafting_button.pressed.connect(_on_crafting_button_pressed)
	_connect_signal(_gameplay_port, &"InventoryToggleRequested", Callable(self, "_handle_inventory_toggle_request"))
	_connect_signal(_gameplay_port, &"InventoryNodeToggleRequested", Callable(self, "_handle_inventory_toggle_request"))
	for section in [_inventory_section, _equipment_section, _deck_section]:
		_connect_signal(section, &"slot_clicked", Callable(self, "_on_slot_clicked"))
	hide()

## 响应 GameplayPort 的背包切换请求。
## @param inventory 请求展示的玩家库存组件。
func _handle_inventory_toggle_request(inventory: Node) -> void:
	if inventory == null:
		push_error("InventoryUIController 收到空 InventoryComponent。")
		return
	if visible:
		Close()
	else:
		Open(inventory)

## 绑定 Model、刷新三个区域并显示背包。
## @param inventory 玩家库存组件。
func Open(inventory: Node) -> void:
	if inventory == null:
		push_error("InventoryUIController.Open 收到空 InventoryComponent。")
		return
	_bind_player_inventory(inventory)
	if _gameplay_port == null:
		push_error("InventoryUIController 未绑定 GameplayPort。")
		return
	var player: Variant = _gameplay_port.get("Player")
	if not (player is Object):
		push_error("InventoryUIController 未找到 Player。")
		return
	var attributes: Variant = (player as Object).get("Attributes")
	if _attribute_summary != null and _attribute_summary.has_method("Bind"):
		_attribute_summary.call("Bind", attributes)
	_bind_equipment((player as Object).get("Equipment") as Node)
	_bind_battle_deck(_gameplay_port.get("PlayerBattleDeck") as Node)
	if _equipment == null or _battle_deck == null:
		return
	_bind_sections()
	show()

## 隐藏背包并关闭物品菜单。
func Close() -> void:
	_clear_item_menu()
	hide()

func _bind_sections() -> void:
	if _inventory_section != null and _inventory_section.has_method("Bind"):
		_inventory_section.call("Bind", _player_inventory, _tooltip_presenter, Callable(self, "_handle_slot_shortcut"), Callable(self, "_handle_slot_use"))
	if _equipment_section != null and _equipment_section.has_method("Bind"):
		_equipment_section.call("Bind", _equipment, _tooltip_presenter)
	if _deck_section != null and _deck_section.has_method("Bind"):
		_deck_section.call("Bind", _battle_deck, _tooltip_presenter, Callable(self, "_handle_slot_shortcut"))
	_rebind_inventory_slots()
	_rebind_equipment_slots()
	_rebind_deck_slots()

func _bind_player_inventory(inventory: Node) -> void:
	if _player_inventory == inventory:
		return
	_disconnect_signal(_player_inventory, &"InventoryChanged", Callable(self, "_on_inventory_changed"))
	_player_inventory = inventory
	_connect_signal(_player_inventory, &"InventoryChanged", Callable(self, "_on_inventory_changed"))

func _bind_equipment(equipment: Node) -> void:
	if equipment == null:
		push_error("InventoryUIController 未找到 EquipmentComponent。")
		return
	if _equipment == equipment:
		return
	_disconnect_signal(_equipment, &"EquipmentChanged", Callable(self, "_on_equipment_changed"))
	_equipment = equipment
	_connect_signal(_equipment, &"EquipmentChanged", Callable(self, "_on_equipment_changed"))

func _bind_battle_deck(battle_deck: Node) -> void:
	if battle_deck == null:
		push_error("InventoryUIController 未找到 BattleDeckComponent。")
		return
	if _battle_deck == battle_deck:
		return
	_disconnect_signal(_battle_deck, &"InventoryChanged", Callable(self, "_on_battle_deck_changed"))
	_battle_deck = battle_deck
	_connect_signal(_battle_deck, &"InventoryChanged", Callable(self, "_on_battle_deck_changed"))

## 兼容旧 Controller 的刷新入口。
func _rebind_inventory_slots() -> void:
	if _inventory_section != null and _inventory_section.has_method("Refresh"):
		_inventory_section.call("Refresh")
		_slot_views = _inventory_section.call("GetSlots") as Array
		_connect_slot_observers(_slot_views)

## 兼容旧 Controller 的刷新入口。
func _rebind_equipment_slots() -> void:
	if _equipment_section != null and _equipment_section.has_method("Refresh"):
		_equipment_section.call("Refresh")
		_equipment_slot_views = _equipment_section.call("GetSlots") as Array
		_connect_slot_observers(_equipment_slot_views)

## 兼容旧 Controller 的刷新入口。
func _rebind_deck_slots() -> void:
	if _deck_section != null and _deck_section.has_method("Refresh"):
		_deck_section.call("Refresh")
		_deck_slot_views = _deck_section.call("GetSlots") as Array
		_connect_slot_observers(_deck_slot_views)

func _on_inventory_changed() -> void:
	_clear_item_menu()
	_rebind_inventory_slots()
	_refresh_tooltip()

func _on_equipment_changed() -> void:
	_rebind_equipment_slots()
	_refresh_tooltip()

func _on_battle_deck_changed() -> void:
	_rebind_deck_slots()
	_refresh_tooltip()

func _connect_slot_observers(slots: Array) -> void:
	for slot_value in slots:
		var slot: ItemSlot = slot_value as ItemSlot
		if slot == null:
			continue
		_connect_signal(slot, &"pointer_entered", Callable(self, "_on_slot_pointer_entered"))
		_connect_signal(slot, &"pointer_left", Callable(self, "_on_slot_pointer_left"))
		_connect_signal(slot, &"content_changed", Callable(self, "_on_slot_content_changed"))

func _on_slot_clicked(slot: ItemSlot) -> void:
	if not _is_slot_selected_in_its_section(slot):
		# 同格取消后仍位于鼠标下时，暂时压住该格的悬停提示，直到鼠标离开。
		if _hovered_slot == slot:
			_suppressed_hover_slot = slot
		if _selected_slot == slot:
			_selected_slot = null
	else:
		_selected_slot = slot
		_suppressed_hover_slot = null
	_refresh_tooltip()

func _on_slot_pointer_entered(slot: ItemSlot) -> void:
	_hovered_slot = slot
	_refresh_tooltip()

func _on_slot_pointer_left(slot: ItemSlot) -> void:
	if _hovered_slot == slot:
		_hovered_slot = null
	if _suppressed_hover_slot == slot:
		_suppressed_hover_slot = null
	_refresh_tooltip()

func _on_slot_content_changed(_slot: ItemSlot) -> void:
	if _slot == _displayed_selected_slot:
		_displayed_selected_item = null
	if _slot == _displayed_hover_slot:
		_displayed_hover_item = null
	_refresh_tooltip()

func _on_setting_changed(section: String, key: String, value: Variant) -> void:
	if section != SETTINGS_SECTION or key != SHOW_SELECTED_INFO_KEY:
		return
	_show_selected_item_info = value if value is bool else true
	_refresh_tooltip()

func _refresh_tooltip() -> void:
	if not is_visible_in_tree() or (_item_action_menu != null and _item_action_menu.visible):
		_hide_selected_tooltip()
		_hide_hover_tooltip()
		return
	var selected_valid: bool = _show_selected_item_info and is_instance_valid(_selected_slot) and _selected_slot.item_data != null
	if selected_valid:
		var selected_item: Resource = _selected_slot.item_data
		if _displayed_selected_slot != _selected_slot or _displayed_selected_item != selected_item:
			_selected_tooltip_presenter.call("Show", _selected_slot.CurrentStack if _selected_slot.CurrentStack != null else selected_item)
			_displayed_selected_slot = _selected_slot
			_displayed_selected_item = selected_item
		if is_instance_valid(_selected_tooltip_panel):
			var slot_rect: Rect2 = _selected_slot.get_global_rect()
			_selected_tooltip_panel.set_fixed_anchor(slot_rect.position + Vector2(slot_rect.size.x, 0.0))
	else:
		_hide_selected_tooltip()
	# 悬停提示独立使用 HUD 的共享实例；固定选中提示不会因悬停切换而消失。
	var show_as_hover: bool = is_instance_valid(_hovered_slot) and _hovered_slot.item_data != null \
		and (_hovered_slot != _selected_slot or not selected_valid) \
		and _hovered_slot != _suppressed_hover_slot
	if show_as_hover:
		var hovered_item: Resource = _hovered_slot.item_data
		if _displayed_hover_slot != _hovered_slot or _displayed_hover_item != hovered_item:
			_tooltip_presenter.call("Show", _hovered_slot.CurrentStack if _hovered_slot.CurrentStack != null else hovered_item)
			_displayed_hover_slot = _hovered_slot
			_displayed_hover_item = hovered_item
	else:
		_hide_hover_tooltip()

func _is_slot_selected_in_its_section(slot: ItemSlot) -> bool:
	for section in [_inventory_section, _equipment_section, _deck_section]:
		if section != null and section.has_method("GetSelectedSlot") and section.call("GetSelectedSlot") == slot:
			return true
	return false

func _hide_selected_tooltip() -> void:
	if _displayed_selected_slot != null:
		_selected_tooltip_presenter.call("Hide")
	_displayed_selected_slot = null
	_displayed_selected_item = null

func _hide_hover_tooltip() -> void:
	if _displayed_hover_slot != null:
		_tooltip_presenter.call("Hide")
	_displayed_hover_slot = null
	_displayed_hover_item = null

func _clear_selection() -> void:
	for section in [_inventory_section, _equipment_section, _deck_section]:
		if section != null and section.has_method("ClearSelection"):
			section.call("ClearSelection")
	_selected_slot = null
	_hovered_slot = null
	_suppressed_hover_slot = null
	_hide_selected_tooltip()
	_hide_hover_tooltip()

func _on_crafting_button_pressed() -> void:
	Close()
	if _gameplay_port != null and _gameplay_port.has_method("RequestOpenCrafting"):
		_gameplay_port.call("RequestOpenCrafting")

## 处理来自 ItemSlot 的 Shift/Alt 快捷请求。
## @param slot_ui 被点击的格子。
## @param shortcut_kind 0 为 Shift，1 为 Alt。
func _handle_slot_shortcut(slot_ui: Variant, shortcut_kind: int) -> void:
	if not (slot_ui is Object) or _player_inventory == null or _battle_deck == null or _equipment == null:
		return
	var source_inventory: Node = (slot_ui as Object).get("Inventory") as Node
	if source_inventory == null:
		return
	if shortcut_kind == SHORTCUT_ALT_CLICK:
		_handle_alt_click_shortcut(slot_ui as Object, source_inventory)
	else:
		_handle_shift_click_shortcut(slot_ui as Object, source_inventory)

func _handle_alt_click_shortcut(slot_ui: Object, source_inventory: Node) -> void:
	if source_inventory == _battle_deck:
		_battle_deck.call("MoveAllMatchingStacksTo", _player_inventory, Callable(self, "_is_skill_card"))
		return
	var current_stack: Variant = slot_ui.get("CurrentStack")
	if source_inventory == _player_inventory and _is_skill_card(_stack_item(current_stack)):
		_player_inventory.call("MoveAllMatchingStacksTo", _battle_deck, Callable(self, "_is_skill_card"))

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

func _is_skill_card(item: Resource) -> bool:
	return item != null and _battle_deck != null and bool(_battle_deck.call("CanAddItem", item, 1))

## 打开建筑物品操作菜单，并把当前身份快照交给二次校验。
## @param slot_ui 当前库存格子。
## @return bool 是否成功打开菜单。
func _handle_slot_use(slot_ui: Object) -> bool:
	if _item_action_menu == null:
		return false
	if not is_visible_in_tree() or not is_instance_valid(_player_inventory) or slot_ui.get("Inventory") != _player_inventory:
		return false
	var stack: Variant = _player_inventory.call("GetStackAt", int(slot_ui.get("SlotIndex")))
	var item: Resource = _stack_item(stack)
	if item == null or _stack_is_empty(stack):
		return false
	# 普通物品没有可执行操作，点击仅选中并显示物品信息；建筑卡仍保留“放置”菜单。
	if not item.has_method("IsBuildingCard") or not bool(item.call("IsBuildingCard")):
		return false
	_clear_item_menu()
	_menu_item = item
	_menu_slot_index = int(slot_ui.get("SlotIndex"))
	_item_action_menu.clear()
	_item_action_menu.add_separator(String(item.get("CardName")))
	_item_action_menu.add_item("放置", ACTION_PLACE_BUILDING)
	_item_action_menu.add_item("取消", 0)
	_hide_selected_tooltip()
	_hide_hover_tooltip()
	# 嵌入窗口使用宿主窗口坐标，避免移动游戏窗口后菜单偏移。
	var popup_position: Vector2 = get_screen_transform() * get_local_mouse_position()
	if get_viewport().gui_embed_subwindows:
		popup_position -= Vector2(get_window().position)
	_item_action_menu.popup(Rect2i(Vector2i(popup_position), Vector2i.ZERO))
	return true

func _on_item_action_selected(action_id: int) -> void:
	var item: Resource = _menu_item
	var slot_index: int = _menu_slot_index
	_clear_item_menu()
	if action_id != ACTION_PLACE_BUILDING or not is_visible_in_tree() or not is_instance_valid(_player_inventory) or item == null or slot_index < 0:
		return
	var stack: Variant = _player_inventory.call("GetStackAt", slot_index)
	if _stack_is_empty(stack) or _stack_item(stack) != item:
		return
	if not item.has_method("IsBuildingCard") or not bool(item.call("IsBuildingCard")):
		return
	Close()
	if _gameplay_port != null and _gameplay_port.has_method("RequestPlaceBuilding"):
		_gameplay_port.call("RequestPlaceBuilding", item)

func _clear_item_menu() -> void:
	_menu_item = null
	_menu_slot_index = -1
	if is_instance_valid(_item_action_menu):
		_item_action_menu.hide()

func _on_panel_visibility_changed() -> void:
	# 菜单是独立弹窗，父级隐藏时也必须清除旧操作快照。
	if not is_visible_in_tree():
		_clear_item_menu()
		_clear_selection()

func _stack_is_empty(stack: Variant) -> bool:
	return stack == null or not (stack is Object) or bool((stack as Object).get("IsEmpty"))

func _stack_item(stack: Variant) -> Resource:
	return null if _stack_is_empty(stack) else (stack as Object).get("Item") as Resource

func _connect_signal(source: Node, signal_name: StringName, callback: Callable) -> void:
	if source != null and source.has_signal(signal_name) and not source.is_connected(signal_name, callback):
		source.connect(signal_name, callback)

func _disconnect_signal(source: Node, signal_name: StringName, callback: Callable) -> void:
	if is_instance_valid(source) and source.has_signal(signal_name) and source.is_connected(signal_name, callback):
		source.disconnect(signal_name, callback)

func _exit_tree() -> void:
	_clear_item_menu()
	_hide_selected_tooltip()
	_hide_hover_tooltip()
	if is_instance_valid(_selected_tooltip_panel):
		_selected_tooltip_panel.queue_free()
	_disconnect_signal(_gameplay_port, &"InventoryToggleRequested", Callable(self, "_handle_inventory_toggle_request"))
	_disconnect_signal(_gameplay_port, &"InventoryNodeToggleRequested", Callable(self, "_handle_inventory_toggle_request"))
	_disconnect_signal(_player_inventory, &"InventoryChanged", Callable(self, "_on_inventory_changed"))
	_disconnect_signal(_equipment, &"EquipmentChanged", Callable(self, "_on_equipment_changed"))
	_disconnect_signal(_battle_deck, &"InventoryChanged", Callable(self, "_on_battle_deck_changed"))
	_disconnect_signal(_settings_manager, &"setting_changed", Callable(self, "_on_setting_changed"))
	for section in [_inventory_section, _equipment_section, _deck_section]:
		_disconnect_signal(section, &"slot_clicked", Callable(self, "_on_slot_clicked"))
	for slots in [_slot_views, _equipment_slot_views, _deck_slot_views]:
		for slot_value in slots:
			if not is_instance_valid(slot_value):
				continue
			var slot: ItemSlot = slot_value as ItemSlot
			_disconnect_signal(slot, &"pointer_entered", Callable(self, "_on_slot_pointer_entered"))
			_disconnect_signal(slot, &"pointer_left", Callable(self, "_on_slot_pointer_left"))
			_disconnect_signal(slot, &"content_changed", Callable(self, "_on_slot_content_changed"))
	if _crafting_button != null and _crafting_button.pressed.is_connected(_on_crafting_button_pressed):
		_crafting_button.pressed.disconnect(_on_crafting_button_pressed)
