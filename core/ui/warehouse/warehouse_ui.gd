extends Control

## 玩家背包与全局仓库之间的 GDScript 生产面板。
##
## 面板只响应 GameplayPort 请求、绑定两个 InventoryComponent 并维护槽位视图；物品移动
## 仍由 SlotUI 与库存组件处理，并通过稳定方法与信号兼容当前 C# 组件。

const ITEM_TOOLTIP_PRESENTER_SCRIPT: GDScript = preload("res://core/ui/item_tooltip_presenter.gd")

## 普通库存槽位场景；字段名保持现有 .tscn 序列化键。
@export var SlotPrefab: PackedScene
## GameplayPort 相对路径；由 Main.tscn 实例覆盖。
@export var GameplayPortPath: NodePath
## 全局 TooltipPanel 相对路径；保持旧默认值。
@export var TooltipPanelPath: NodePath = NodePath("../../TooltipPanel")

var _gameplay_port: Node = null
var _player_slot_grid: GridContainer = null
var _warehouse_slot_grid: GridContainer = null
var _tooltip_presenter: RefCounted = ITEM_TOOLTIP_PRESENTER_SCRIPT.call("Empty") as RefCounted
var _player_inventory: Node = null
var _warehouse_inventory: Node = null
var _player_slot_views: Array[Control] = []
var _warehouse_slot_views: Array[Control] = []


## 解析场景依赖、连接 GameplayPort 请求并初始化关闭按钮样式。
## 返回值：无。
func _ready() -> void:
	_player_slot_grid = get_node("MainPanel/VBoxContainer/ContentSplit/BackpackSection/BackpackScroll/BackpackMargin/PlayerSlotGrid") as GridContainer
	_warehouse_slot_grid = get_node("MainPanel/VBoxContainer/ContentSplit/WarehouseSection/WarehouseScroll/WarehouseMargin/WarehouseSlotGrid") as GridContainer
	var close_button := get_node("MainPanel/VBoxContainer/TitleBar/CloseButton") as Button
	if not close_button.pressed.is_connected(Close):
		close_button.pressed.connect(Close)
	_apply_close_button_styles(close_button)

	_gameplay_port = get_node(GameplayPortPath) as Node
	_tooltip_presenter = ITEM_TOOLTIP_PRESENTER_SCRIPT.new(get_node_or_null(TooltipPanelPath))
	_connect_signal(_gameplay_port, &"WarehouseRequested", Callable(self, "_handle_warehouse_requested"))
	_connect_signal(_gameplay_port, &"WarehouseNodeRequested", Callable(self, "_handle_warehouse_requested"))
	hide()


## 绑定玩家与仓库库存、重绑两组槽位并显示面板。
## 参数 player_inventory：玩家背包组件。
## 参数 warehouse_inventory：全局仓库组件。
## 返回值：无。
func Open(player_inventory: Node, warehouse_inventory: Node) -> void:
	_bind_inventories(player_inventory, warehouse_inventory)
	_rebind_player_slots()
	_rebind_warehouse_slots()
	show()


## 隐藏提示框与仓库面板。
## 返回值：无。
func Close() -> void:
	_tooltip_presenter.call("Hide")
	hide()


## 处理 GameplayPort 的仓库打开请求。
func _handle_warehouse_requested(player_inventory: Node, warehouse_inventory: Node) -> void:
	if player_inventory == null or warehouse_inventory == null:
		push_error("WarehouseUI 收到空 InventoryComponent。")
		return
	Open(player_inventory, warehouse_inventory)


## 切换库存绑定并维护各自 InventoryChanged 连接。
func _bind_inventories(player_inventory: Node, warehouse_inventory: Node) -> void:
	if _player_inventory != player_inventory:
		_disconnect_player_inventory_signal()
		_player_inventory = player_inventory
		_connect_signal(_player_inventory, &"InventoryChanged", Callable(self, "_on_player_inventory_changed"))
		_player_slot_views.clear()

	if _warehouse_inventory != warehouse_inventory:
		_disconnect_warehouse_inventory_signal()
		_warehouse_inventory = warehouse_inventory
		_connect_signal(_warehouse_inventory, &"InventoryChanged", Callable(self, "_on_warehouse_inventory_changed"))
		_warehouse_slot_views.clear()


## 重新绑定玩家背包槽位。
func _rebind_player_slots() -> void:
	_rebind_slots(_player_slot_grid, _player_slot_views, _player_inventory)


## 重新绑定全局仓库槽位。
func _rebind_warehouse_slots() -> void:
	_rebind_slots(_warehouse_slot_grid, _warehouse_slot_views, _warehouse_inventory)


## 让一组槽位数量匹配库存容量，并绑定当前堆叠引用。
func _rebind_slots(slot_grid: GridContainer, slot_views: Array[Control], inventory: Node) -> void:
	if inventory == null:
		return
	var capacity: int = int(inventory.get("Capacity"))
	if slot_views.size() != capacity:
		_generate_slots(slot_grid, slot_views, capacity)
	for index in slot_views.size():
		slot_views[index].call("Bind", index, inventory.call("GetStackAt", index), inventory)


## 按容量重新生成槽位，并为每格设置共享 Presenter。
func _generate_slots(slot_grid: GridContainer, slot_views: Array[Control], capacity: int) -> void:
	for child in slot_grid.get_children():
		child.queue_free()
	slot_views.clear()
	for _index in maxi(capacity, 0):
		var slot_ui := SlotPrefab.instantiate() as Control
		slot_grid.add_child(slot_ui)
		slot_ui.call("SetTooltipPresenter", _tooltip_presenter)
		slot_views.append(slot_ui)


## 玩家库存变化时保持槽位节点并重绑当前堆叠。
func _on_player_inventory_changed() -> void:
	_rebind_player_slots()


## 仓库库存变化时保持槽位节点并重绑当前堆叠。
func _on_warehouse_inventory_changed() -> void:
	_rebind_warehouse_slots()


## 解除玩家库存变化信号。
func _disconnect_player_inventory_signal() -> void:
	_disconnect_signal(_player_inventory, &"InventoryChanged", Callable(self, "_on_player_inventory_changed"))


## 解除仓库库存变化信号。
func _disconnect_warehouse_inventory_signal() -> void:
	_disconnect_signal(_warehouse_inventory, &"InventoryChanged", Callable(self, "_on_warehouse_inventory_changed"))


## 退出场景时解除所有外部信号并隐藏提示框。
## 返回值：无。
func _exit_tree() -> void:
	_disconnect_signal(_gameplay_port, &"WarehouseRequested", Callable(self, "_handle_warehouse_requested"))
	_disconnect_signal(_gameplay_port, &"WarehouseNodeRequested", Callable(self, "_handle_warehouse_requested"))
	_disconnect_player_inventory_signal()
	_disconnect_warehouse_inventory_signal()
	_tooltip_presenter.call("Hide")


## 复刻旧 C# 运行时覆盖的关闭按钮常态和悬停样式。
func _apply_close_button_styles(close_button: Button) -> void:
	var normal_style := StyleBoxFlat.new()
	normal_style.bg_color = Color(0.25, 0.25, 0.25, 1.0)
	normal_style.set_corner_radius_all(4)
	var hover_style := StyleBoxFlat.new()
	hover_style.bg_color = Color(0.35, 0.35, 0.35, 1.0)
	hover_style.set_corner_radius_all(4)
	close_button.add_theme_stylebox_override("normal", normal_style)
	close_button.add_theme_stylebox_override("hover", hover_style)


## 在新旧 Godot Node 上安全连接指定信号。
func _connect_signal(source: Node, signal_name: StringName, callback: Callable) -> void:
	if source != null and source.has_signal(signal_name) and not source.is_connected(signal_name, callback):
		source.connect(signal_name, callback)


## 在新旧 Godot Node 上安全解除指定信号。
func _disconnect_signal(source: Node, signal_name: StringName, callback: Callable) -> void:
	if source != null and source.has_signal(signal_name) and source.is_connected(signal_name, callback):
		source.disconnect(signal_name, callback)
