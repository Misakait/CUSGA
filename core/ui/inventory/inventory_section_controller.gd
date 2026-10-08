extends GridContainer

## 玩家背包区域 Controller。
## 该脚本只管理直接子节点 ItemSlot 的数量、绑定和刷新，库存规则仍由 Model 负责。

const ITEM_SLOT_SCENE: PackedScene = preload("res://scenes/ui/item_slot.tscn")

## 普通格子被点击时通知根 Controller。
signal slot_clicked(slot: ItemSlot)

var _inventory: Node = null
var _tooltip_presenter: Variant = null
var _shortcut_handler: Callable = Callable()
var _use_handler: Callable = Callable()
var _slots: Array[ItemSlot] = []

## 绑定玩家库存并刷新格子。
## @param inventory InventoryComponent 实例。
## @param tooltip_presenter 共享提示框 Presenter。
## @param shortcut_handler Shift/Alt 快捷回调。
## @param use_handler 建筑菜单回调。
func Bind(inventory: Node, tooltip_presenter: Variant, shortcut_handler: Callable, use_handler: Callable) -> void:
	if _inventory != inventory:
		_disconnect_inventory()
	_inventory = inventory
	_connect_inventory()
	_tooltip_presenter = tooltip_presenter
	_shortcut_handler = shortcut_handler
	_use_handler = use_handler
	Refresh()

## 按库存容量创建或复用格子，并更新每个格子的堆叠引用。
func Refresh() -> void:
	var capacity: int = 0
	if _inventory != null:
		capacity = maxi(int(_inventory.get("Capacity")), 0)
	while _slots.size() > capacity:
		var removed: ItemSlot = _slots.pop_back()
		removed.queue_free()
	while _slots.size() < capacity:
		_create_slot()
	for index in _slots.size():
		var stack: Variant = _inventory.call("GetStackAt", index) if _inventory != null else null
		_slots[index].bind_inventory(index, stack, _inventory, _shortcut_handler, _use_handler, _tooltip_presenter)

## 返回当前格子数组，供根 Controller 暴露兼容字段。
## @return Array[ItemSlot] 当前已创建的格子。
func GetSlots() -> Array[ItemSlot]:
	return _slots

func _create_slot() -> void:
	var slot: ItemSlot = ITEM_SLOT_SCENE.instantiate() as ItemSlot
	slot.configure_compact_layout(0.6)
	add_child(slot)
	slot.slot_clicked.connect(_on_slot_clicked)
	_slots.append(slot)

func _on_slot_clicked(slot: ItemSlot) -> void:
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
