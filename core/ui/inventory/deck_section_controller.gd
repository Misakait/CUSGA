extends GridContainer

## 出战卡组区域 Controller。
## 卡组继承库存组件协议，只在这里管理 ItemSlot 视图，不复制卡组容量或移动规则。

const ITEM_SLOT_SCENE: PackedScene = preload("res://scenes/ui/item_slot1.tscn")
const BACKPACK_ITEM_SLOT_SCRIPT: GDScript = preload("res://scripts/ui_scripts/backpack_item_slot.gd")
signal slot_clicked(slot: ItemSlot)

var _inventory: Node = null
var _tooltip_presenter: Variant = null
var _shortcut_handler: Callable = Callable()
var _slots: Array[ItemSlot] = []
var _selected_slot: ItemSlot = null

## 绑定出战卡组并刷新格子。
## @param inventory BattleDeckComponent 实例。
## @param tooltip_presenter 共享提示框 Presenter。
## @param shortcut_handler Shift/Alt 快捷回调。
func Bind(inventory: Node, tooltip_presenter: Variant, shortcut_handler: Callable) -> void:
	if _inventory != inventory:
		_disconnect_inventory()
	_inventory = inventory
	_connect_inventory()
	_tooltip_presenter = tooltip_presenter
	_shortcut_handler = shortcut_handler
	Refresh()

## 按卡组容量创建或复用格子并重新绑定 ItemStack。
func Refresh() -> void:
	var capacity: int = 0
	if _inventory != null:
		capacity = maxi(int(_inventory.get("Capacity")), 0)
	while _slots.size() > capacity:
		var removed: ItemSlot = _slots.pop_back()
		if removed == _selected_slot:
			_selected_slot = null
		if removed.slot_clicked.is_connected(_on_slot_clicked):
			removed.slot_clicked.disconnect(_on_slot_clicked)
		removed.queue_free()
	while _slots.size() < capacity:
		_create_slot()
	for index in _slots.size():
		var stack: Variant = _inventory.call("GetStackAt", index) if _inventory != null else null
		_slots[index].configure_display(false, false)
		_slots[index].bind_inventory(index, stack, _inventory, _shortcut_handler, Callable(), _tooltip_presenter)
		_slots[index].set_selected(_slots[index] == _selected_slot)

## 返回当前卡组格子。
## @return Array[ItemSlot] 当前格子列表。
func GetSlots() -> Array[ItemSlot]:
	return _slots

## 返回本区域当前选中的格子。
## @return 当前选中的格子；没有选中时返回 null。
func GetSelectedSlot() -> ItemSlot:
	return _selected_slot

## 清除本区域的选中格子。
## @return 无返回值。
func ClearSelection() -> void:
	if is_instance_valid(_selected_slot):
		_selected_slot.set_selected(false)
	_selected_slot = null

func _create_slot() -> void:
	var slot_node: Button = ITEM_SLOT_SCENE.instantiate() as Button
	slot_node.set_script(BACKPACK_ITEM_SLOT_SCRIPT)
	var slot: ItemSlot = slot_node as ItemSlot
	if slot == null:
		push_error("DeckSectionController: 无法将 item_slot1 适配为 ItemSlot。")
		return
	add_child(slot)
	slot.configure_compact_layout(0.6)
	slot.slot_clicked.connect(_on_slot_clicked)
	_slots.append(slot)

func _on_slot_clicked(slot: ItemSlot) -> void:
	if is_instance_valid(_selected_slot) and _selected_slot == slot:
		_selected_slot.set_selected(false)
		_selected_slot = null
	else:
		if is_instance_valid(_selected_slot):
			_selected_slot.set_selected(false)
		_selected_slot = slot
		slot.set_selected(true)
	slot_clicked.emit(slot)

func _connect_inventory() -> void:
	if _inventory != null and _inventory.has_signal("InventoryChanged"):
		var callback := Callable(self, "_on_inventory_changed")
		if not _inventory.is_connected("InventoryChanged", callback):
			_inventory.connect("InventoryChanged", callback)

func _disconnect_inventory() -> void:
	if _inventory != null and _inventory.has_signal("InventoryChanged"):
		var callback := Callable(self, "_on_inventory_changed")
		if _inventory.is_connected("InventoryChanged", callback):
			_inventory.disconnect("InventoryChanged", callback)

func _on_inventory_changed() -> void:
	Refresh()

func _exit_tree() -> void:
	_disconnect_inventory()
	for slot in _slots:
		if is_instance_valid(slot) and slot.slot_clicked.is_connected(_on_slot_clicked):
			slot.slot_clicked.disconnect(_on_slot_clicked)
