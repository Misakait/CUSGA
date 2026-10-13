extends GridContainer

## 收获区域控制器；只管理直接格子和自身创建的提示层，不修改局外资产。
## 参数通过 bind_result 传入，容量与格子查询返回隔离的显示状态。

const ITEM_SLOT_SCENE: PackedScene = preload("res://scenes/ui/item_slot1.tscn")
const SETTLEMENT_SLOT_SCRIPT: GDScript = preload("res://core/ui/settlement/settlement_item_slot.gd")
const TOOLTIP_SCENE: PackedScene = preload("res://scenes/ui_scenes/TooltipPanel.tscn")
const PRESENTER_SCRIPT: GDScript = preload("res://core/ui/item_tooltip_presenter.gd")

## 显示容量变化通知；参数 capacity 是格子数量，不代表升级已经发生。
signal harvest_capacity_changed(capacity: int)

var _capacity: int = 5
var _harvest: Array = []
var _slots: Array[ItemSlot] = []
var _selected_slot: ItemSlot = null
var _hovered_slot: ItemSlot = null
var _suppressed_hover_slot: ItemSlot = null
var _hover_panel: TooltipPanel = null
var _selected_panel: TooltipPanel = null
var _hover_presenter: RefCounted = null
var _selected_presenter: RefCounted = null

func _ready() -> void:
	_create_tooltips()
	_refresh_slots()

## 展示指定的结算收获；结果不足容量时仍保留空格。
## 参数 harvest：真实 ItemStack 数组；capacity：本局固定容量。
## 返回值：无；本接口只更新显示，不发奖、不保存。
func bind_result(harvest: Array, capacity: int = 5) -> void:
	clear_selection()
	_harvest.clear()
	for value: Variant in harvest:
		var snapshot: Variant = null
		if value is Object and (value as Object).has_method("Duplicate"):
			snapshot = (value as Object).call("Duplicate")
		_harvest.append(snapshot)
	_capacity = maxi(capacity, 0)
	if is_node_ready():
		_refresh_slots()

## 读取当前显示容量。
## 返回值：格子数量，默认 5。
func get_harvest_capacity() -> int:
	return _capacity

## 刷新格子显示容量，供未来升级展示接入；不改 Profile 或固定结果。
## 参数 capacity：期望格子数量。
## 返回值：容量有效且没有遮蔽已有收获时为 true。
func refresh_capacity(capacity: int) -> bool:
	if capacity < 0 or capacity < _harvest.size():
		return false
	if _capacity == capacity:
		return true
	_capacity = capacity
	clear_selection()
	if is_node_ready():
		_refresh_slots()
	harvest_capacity_changed.emit(_capacity)
	return true

## 查询当前格子，以便测试和未来界面协调。
## 返回值：格子列表副本；格子仍归本区域所有。
func get_slots() -> Array[ItemSlot]:
	return _slots.duplicate()

## 查询单选结果。
## 返回值：选中的格子，没有选择时为 null。
func get_selected_slot() -> ItemSlot:
	return _selected_slot

## 清除选中状态和所有提示。
## 返回值：无。
func clear_selection() -> void:
	if is_instance_valid(_selected_slot):
		_selected_slot.set_selected(false)
	_selected_slot = null
	_hovered_slot = null
	_suppressed_hover_slot = null
	_hide_presenter(_selected_presenter)
	_hide_presenter(_hover_presenter)

func _refresh_slots() -> void:
	while _slots.size() > _capacity:
		var removed: ItemSlot = _slots.pop_back()
		remove_child(removed)
		removed.queue_free()
	while _slots.size() < _capacity:
		var slot: Button = ITEM_SLOT_SCENE.instantiate() as Button
		slot.set_script(SETTLEMENT_SLOT_SCRIPT)
		add_child(slot)
		var item_slot: ItemSlot = slot as ItemSlot
		item_slot.configure_compact_layout(0.95)
		item_slot.slot_clicked.connect(_on_slot_clicked)
		item_slot.pointer_entered.connect(_on_pointer_entered)
		item_slot.pointer_left.connect(_on_pointer_left)
		_slots.append(item_slot)
	for index: int in _slots.size():
		var stack: Variant = _harvest[index] if index < _harvest.size() else null
		_slots[index].call("bind_snapshot", index, stack)
		_slots[index].set_selected(_slots[index] == _selected_slot)

func _create_tooltips() -> void:
	var layer := CanvasLayer.new()
	layer.name = "HarvestTooltipLayer"
	layer.layer = 125
	add_child(layer)
	_hover_panel = TOOLTIP_SCENE.instantiate() as TooltipPanel
	_selected_panel = TOOLTIP_SCENE.instantiate() as TooltipPanel
	_hover_panel.name = "HarvestHoverTooltip"
	_selected_panel.name = "HarvestSelectedTooltip"
	for panel: TooltipPanel in [_hover_panel, _selected_panel]:
		layer.add_child(panel)
		# 私有提示不可留在全局组，避免其它界面的悬停组件借走本面板。
		panel.remove_from_group("tooltip_panel")
	_hover_presenter = PRESENTER_SCRIPT.new(_hover_panel) as RefCounted
	_selected_presenter = PRESENTER_SCRIPT.new(_selected_panel) as RefCounted

func _on_slot_clicked(slot: ItemSlot) -> void:
	if _selected_slot == slot:
		_selected_slot.set_selected(false)
		_selected_slot = null
		_suppressed_hover_slot = slot
		_hide_presenter(_selected_presenter)
		_hide_presenter(_hover_presenter)
		return
	if is_instance_valid(_selected_slot):
		_selected_slot.set_selected(false)
	_selected_slot = slot
	_suppressed_hover_slot = null
	slot.set_selected(true)
	_selected_presenter.call("Show", slot.CurrentStack)
	var anchor: Vector2 = slot.get_global_transform_with_canvas() * Vector2(slot.size.x, 0.0)
	_selected_panel.set_fixed_anchor(anchor)
	_hide_presenter(_hover_presenter)

func _on_pointer_entered(slot: ItemSlot) -> void:
	_hovered_slot = slot
	if slot == _suppressed_hover_slot or slot == _selected_slot or slot.item_data == null:
		_hide_presenter(_hover_presenter)
		return
	_hover_presenter.call("Show", slot.CurrentStack)

func _on_pointer_left(slot: ItemSlot) -> void:
	if _hovered_slot == slot:
		_hovered_slot = null
		_hide_presenter(_hover_presenter)
	if _suppressed_hover_slot == slot:
		_suppressed_hover_slot = null

func _hide_presenter(presenter: RefCounted) -> void:
	if presenter != null:
		presenter.call("Hide")

func _exit_tree() -> void:
	clear_selection()
