extends RefCounted

## 材料区控制器。每行左侧为 item_slot1 格子，右侧为需求与库存数量。

signal item_selected(item: Resource, slot: BaseButton)
signal item_hovered(item: Resource, slot: BaseButton)
signal item_left(slot: BaseButton)
## 右键取消材料浏览时发出；参数 slot 为刚取消的格子，不改变配方或材料数量。
signal selection_cancelled(slot: BaseButton)

const ITEM_SLOT_SCENE: PackedScene = preload("res://scenes/ui/item_slot1.tscn")
const ITEM_COMPAT: GDScript = preload("res://resources/item/item_data_compat.gd")

var _container: VBoxContainer = null
var _inventory: Node = null
var _rows_by_item: Dictionary = {}
var _selected_slot: BaseButton = null

## 绑定材料行容器和当前库存。
## @param container 材料 ScrollContainer 内的 VBoxContainer。
## @param inventory 提供 ItemCnt 的库存组件。
## @return 无。
func bind(container: VBoxContainer, inventory: Node) -> void:
	_container = container
	_inventory = inventory

## 根据配方和合成数量刷新材料行；库存变化时复用未变化的材料节点。
## @param recipe 当前配方资源。
## @param quantity 合成次数。
## @return 无。
func refresh(recipe: Variant, quantity: int = 1) -> void:
	if _container == null:
		return
	var totals: Dictionary = _totals(recipe, quantity)
	for old_item: Variant in _rows_by_item.keys():
		if not totals.has(old_item):
			var old_row: HBoxContainer = _rows_by_item[old_item]
			if is_instance_valid(_selected_slot) and _selected_slot.get_parent() == old_row:
				_selected_slot = null
			(_rows_by_item[old_item] as HBoxContainer).queue_free()
			_rows_by_item.erase(old_item)
	var row_index: int = 0
	for item: Resource in totals:
		var row: HBoxContainer = _rows_by_item.get(item)
		if row == null:
			row = _create_row(item)
			_container.add_child(row)
			_rows_by_item[item] = row
		var slot: BaseButton = row.get_child(0) as BaseButton
		# 区域退出时解除订阅；重新打开时恢复复用行的输入，不额外创建格子。
		for binding: Array in _input_bindings(item, slot):
			if not slot.is_connected(binding[0], binding[1]):
				slot.connect(binding[0], binding[1])
		_container.move_child(row, row_index)
		row_index += 1
		var required: int = int(totals[item])
		var owned: int = int(_inventory.call("ItemCnt", item)) if _inventory != null and _inventory.has_method("ItemCnt") else 0
		var label := row.get_node("QuantityLabel") as Label
		label.text = "需要 %d / 拥有 %d" % [required, owned]
		label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.25) if owned < required else Color.WHITE)

func _totals(recipe: Variant, quantity: int) -> Dictionary:
	var totals: Dictionary = {}
	if not (recipe is Object):
		return totals
	var inputs: Variant = (recipe as Object).get("Inputs")
	if not (inputs is Array):
		return totals
	for ingredient: Variant in inputs:
		var item: Resource = _resource(ingredient, "RequiredItem")
		var amount: int = int(_property(ingredient, "Amount", 0)) * maxi(1, quantity)
		if item != null and amount > 0:
			totals[item] = int(totals.get(item, 0)) + amount
	return totals

func _create_row(item: Resource) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 78)
	var slot: BaseButton = _instantiate_slot()
	if slot == null:
		return row
	row.add_child(slot)
	slot.toggle_mode = false
	slot.custom_minimum_size = Vector2(72, 72)
	slot.tooltip_text = String(ITEM_COMPAT.call("get_display_name", item, ""))
	var icon := slot.get_node_or_null("Icon") as TextureRect
	if icon != null:
		icon.texture = ITEM_COMPAT.call("get_display_icon", item, null) as Texture2D
	var name_label := slot.get_node_or_null("NameLabel") as Label
	if name_label != null:
		name_label.text = String(ITEM_COMPAT.call("get_display_name", item, ""))
	var count_label := slot.get_node_or_null("CountLabel") as Label
	if count_label != null:
		count_label.hide()
	var label := Label.new()
	label.name = "QuantityLabel"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	return row

func _on_slot_pressed(item: Resource, slot: BaseButton) -> void:
	# 材料仍使用原来的瞬时按钮外观，只记录浏览选择，不改变制作配方。
	_selected_slot = slot
	item_selected.emit(item, slot)

func _on_slot_entered(item: Resource, slot: BaseButton) -> void:
	item_hovered.emit(item, slot)

func _on_slot_exited(slot: BaseButton) -> void:
	item_left.emit(slot)

func _on_slot_gui_input(event: InputEvent, slot: BaseButton) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT \
		and event.pressed and _selected_slot == slot and not slot.get_viewport().gui_is_dragging():
		_selected_slot = null
		selection_cancelled.emit(slot)
		slot.accept_event()

func _input_bindings(item: Resource, slot: BaseButton) -> Array:
	return [[&"pressed", _on_slot_pressed.bind(item, slot)], \
		[&"mouse_entered", _on_slot_entered.bind(item, slot)], \
		[&"mouse_exited", _on_slot_exited.bind(slot)], \
		[&"gui_input", _on_slot_gui_input.bind(slot)]]

## 解除本控制器建立的格子订阅。无参数；返回无，根界面退出树时调用。
func disconnect_input() -> void:
	for item: Resource in _rows_by_item:
		var row: HBoxContainer = _rows_by_item[item]
		if not is_instance_valid(row) or row.get_child_count() == 0:
			continue
		var slot: BaseButton = row.get_child(0) as BaseButton
		if slot == null:
			continue
		for binding: Array in _input_bindings(item, slot):
			if slot.is_connected(binding[0], binding[1]):
				slot.disconnect(binding[0], binding[1])
	_selected_slot = null

func _instantiate_slot() -> BaseButton:
	# item_slot1 的根节点可以是 Button 或 TextureButton；统一使用 BaseButton 保持两种场景资源兼容。
	var instance: Node = ITEM_SLOT_SCENE.instantiate()
	if not is_instance_valid(instance) or not (instance is BaseButton):
		if is_instance_valid(instance):
			instance.queue_free()
		push_error("材料格子场景的根节点必须继承 BaseButton。")
		return null
	return instance as BaseButton

func _resource(value: Variant, property_name: StringName) -> Resource:
	var result: Variant = _property(value, property_name, null)
	return result as Resource if result is Resource else null

func _property(value: Variant, property_name: StringName, fallback: Variant) -> Variant:
	if not (value is Object):
		return fallback
	var result: Variant = (value as Object).get(String(property_name))
	return fallback if result == null else result
