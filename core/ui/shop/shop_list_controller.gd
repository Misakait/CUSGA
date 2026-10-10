extends RefCounted

## 只管理一个商店网格的直接格子，容量和目录不变时复用节点。
const SLOT_SCENE: PackedScene = preload("res://scenes/ui/item_slot2.tscn")
const SLOT_SCRIPT: GDScript = preload("res://core/ui/shop/shop_item_slot.gd")

var slots: Array[Button] = []
var _grid: GridContainer
var _controller: Node
var _side: StringName

## 绑定本区。参数 grid 为容器、controller 为根、side 为区域；返回无。
func bind(grid: GridContainer, controller: Node, side: StringName) -> void:
	_grid = grid
	_controller = controller
	_side = side

## 刷新直接格子。参数 entries 为权威快照数组；返回无，仅条目数变动时增删节点。
func refresh(entries: Array) -> void:
	while slots.size() < entries.size():
		var slot: Button = SLOT_SCENE.instantiate() as Button
		slot.set_script(SLOT_SCRIPT)
		slot.call("configure", _controller, _side, slots.size())
		slot.connect("slot_clicked", Callable(_controller, "_on_slot_clicked"))
		slot.connect("drag_started", Callable(_controller, "clear_selection"))
		_grid.add_child(slot)
		slots.append(slot)
	while slots.size() > entries.size():
		var removed: Button = slots.pop_back()
		_grid.remove_child(removed)
		removed.queue_free()
	for index: int in entries.size():
		slots[index].call("bind_content", entries[index])

## 同步本区单选。参数 index 为位置、-1 为取消；返回无。
func select(index: int) -> void:
	for position: int in slots.size():
		slots[position].call("set_selected", position == index)
