extends RefCounted

## 只管理一个 ScrollContainer 中的直接格子，内容刷新不会重建节点。
const SLOT_SCENE: PackedScene = preload("res://scenes/ui/item_slot2.tscn")
const SLOT_SCRIPT: GDScript = preload("res://core/ui/warehouse/warehouse_item_slot.gd")

var slots: Array[Button] = []
var _grid: GridContainer
var _controller: Node
var _side: StringName

## 绑定网格与根协调者。参数 grid 为格子容器、controller 为根节点、side 为区域；返回无。
func bind(grid: GridContainer, controller: Node, side: StringName) -> void:
	_grid = grid
	_controller = controller
	_side = side

## 按快照刷新格子。参数 entries 为已解锁位置的内容；返回无。
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
		var entry: Dictionary = entries[index]
		slots[index].call("bind_content", entry.get("item"), int(entry.get("amount", 0)))

## 同步当前区域的单选。参数 index 为位置，-1 为清除；返回无。
func select(index: int) -> void:
	for position: int in slots.size():
		slots[position].call("set_selected", position == index)
