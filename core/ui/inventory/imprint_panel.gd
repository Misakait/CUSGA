extends PanelContainer

## 刻印面板：展示属性池、逐张揭晓卡面，并暂存玩家尚未确认的抽取结果。
## 五行展示顺序及其既有元素枚举值。
const ELEMENTS: Array[int] = [1, 4, 3, 5, 2]
## 五行显示名称。
const NAMES: Array[String] = ["木", "土", "水", "火", "金"]
## 各属性卡胚路径，与显示顺序一致。
const EMBRYOS: Array[String] = ["wood", "earth", "water", "fire", "metal"]
## 属性高亮颜色，与分页显示顺序一致。
const ELEMENT_COLORS: Array[Color] = [Color("#91c975"), Color("#ddb678"), Color("#79c8d0"), Color("#e9906e"), Color("#e4d895")]
## 无状态的刻印业务服务。
const SERVICE: GDScript = preload("res://core/imprint/imprint_service.gd")
## 项目合成界面使用的像素字体。
const PIXEL_FONT: Font = preload("res://res/font/Uranus_Pixel_11Px.ttf")
## 现有技能卡场景与空白卡底板。
const CARD_SCENE: PackedScene = preload("res://scenes/skill_card_scenes/SkillCard.tscn")
const BLANK_CARD: Texture2D = preload("res://res/skillcard/技能卡模板2.png")
## 与合成界面一致的小面板按钮材质。
const BUTTON_TEXTURE: Texture2D = preload("res://res/UI/图标ui/面板/小面板.png")
## 刻印桌背景素材。
const TABLE_TEXTURE: Texture2D = preload("res://res/UI/imprint/imprint_table.png")
## 每个卡槽尺寸，五列两行能在 1280×720 的基准画面中展示十张卡。
const SLOT_SIZE: Vector2 = Vector2(202, 146)
## 卡面的显示缩放。
const CARD_SCALE: float = 0.82
## 每张卡收拢与展开各需的秒数。
const FLIP_HALF_SECONDS: float = 0.16
## 连续揭晓之间的停顿秒数。
const REVEAL_GAP_SECONDS: float = 0.08

## 当前玩家库存。
var _inventory: Node
## 返回背包时需要恢复的原面板。
var _backpack: Control
## 当前选中的属性索引。
var _selected: int = 0
## 材料数量显示。
var _balance: Label
## 抽取状态显示。
var _result: Label
## 卡槽容器。
var _card_grid: GridContainer
## 五个属性分页按钮。
var _tab_buttons: Array[Button] = []
## 抽取按钮，结果未处理时禁用以防覆盖。
var _draw_buttons: Array[Button] = []
## 确认获取按钮。
var _confirm_button: Button
## 关闭前的放弃确认框。
var _discard_dialog: ConfirmationDialog
## 本批次结果，按抽出位置保存，允许相同资源出现多次。
var _drawn_cards: Array[Resource] = []
## 已选择的卡槽下标；不以资源身份去重。
var _selected_indices: Array[int] = []
## 当前结果卡槽。
var _slots: Array[Button] = []
## 卡面底部的选择提示。
var _selection_labels: Array[Label] = []
## 揭晓动画运行期间阻止选择和重复结算。
var _revealing: bool = false

## 构造界面并绑定玩家库存。
## 参数 inventory：玩家库存；backpack：返回时显示的背包；返回值：无。
func setup(inventory: Node, backpack: Control) -> void:
	_inventory = inventory
	_backpack = backpack
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	# 统一从根主题继承字体，避免弹窗与运行时创建的控件退回系统字体。
	var pixel_theme := Theme.new()
	pixel_theme.default_font = PIXEL_FONT
	pixel_theme.default_font_size = 22
	theme = pixel_theme
	var canvas := Control.new()
	add_child(canvas)
	var background := TextureRect.new()
	background.texture = TABLE_TEXTURE
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_SCALE
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0.04, 0.025, 0.02, 0.38)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	for edge in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + edge, 56)
	for edge in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 25)
	canvas.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)
	_build_header(box)
	_build_tabs(box)
	_result = Label.new()
	_result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result.add_theme_font_size_override("font_size", 20)
	_result.add_theme_color_override("font_color", Color("#ffe5b0"))
	box.add_child(_result)
	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(center)
	_card_grid = GridContainer.new()
	_card_grid.columns = 5
	_card_grid.add_theme_constant_override("h_separation", 12)
	_card_grid.add_theme_constant_override("v_separation", 8)
	center.add_child(_card_grid)
	_build_actions(box)
	_discard_dialog = ConfirmationDialog.new()
	_discard_dialog.title = "放弃刻印结果？"
	_discard_dialog.dialog_text = "本次刻印还有尚未获取的卡牌。关闭后将放弃这些卡牌，已消耗的卡胚不会返还。"
	_discard_dialog.ok_button_text = "放弃并关闭"
	_discard_dialog.cancel_button_text = "继续选择"
	_discard_dialog.confirmed.connect(_close)
	add_child(_discard_dialog)
	_select(0)

func _build_header(box: VBoxContainer) -> void:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 20)
	box.add_child(header)
	var title := Label.new()
	title.text = "刻 印"
	title.add_theme_font_size_override("font_size", 38)
	title.add_theme_color_override("font_color", Color("#ffe2a1"))
	header.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	_balance = Label.new()
	_balance.add_theme_font_size_override("font_size", 21)
	_balance.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(_balance)
	var close := _make_button("关闭")
	close.pressed.connect(_request_close)
	header.add_child(close)

func _build_tabs(box: VBoxContainer) -> void:
	var tabs := HBoxContainer.new()
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("separation", 16)
	box.add_child(tabs)
	for index in NAMES.size():
		var button := _make_button(NAMES[index] + "  刻印")
		button.custom_minimum_size = Vector2(130, 44)
		button.pressed.connect(_select.bind(index))
		tabs.add_child(button)
		_tab_buttons.append(button)

func _build_actions(box: VBoxContainer) -> void:
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 24)
	box.add_child(actions)
	for count in [1, 10]:
		var button := _make_button("单次刻印 · 1" if count == 1 else "十连刻印 · 10")
		button.custom_minimum_size = Vector2(230, 50)
		button.pressed.connect(_perform_draw.bind(count))
		actions.add_child(button)
		_draw_buttons.append(button)
	_confirm_button = _make_button("确定获取")
	_confirm_button.custom_minimum_size = Vector2(200, 50)
	_confirm_button.pressed.connect(_confirm_selection)
	actions.add_child(_confirm_button)

func _make_button(label: String) -> Button:
	var button := Button.new()
	button.text = label
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_color_override("font_color", Color("#3c241b"))
	button.add_theme_color_override("font_hover_color", Color("#2b1710"))
	button.add_theme_color_override("font_disabled_color", Color("#8b7a68"))
	for state in ["normal", "hover", "pressed", "disabled"]:
		var style := StyleBoxTexture.new()
		style.texture = BUTTON_TEXTURE
		style.region_rect = Rect2(0, 16, 64, 32)
		style.texture_margin_left = 4
		style.texture_margin_top = 5
		style.texture_margin_right = 3
		style.texture_margin_bottom = 4
		style.modulate_color = Color(1.15, 1.15, 1.15) if state == "hover" else Color.WHITE
		button.add_theme_stylebox_override(state, style)
	return button

func _resource(index: int) -> Resource:
	return load("res://items/imprint/%s_embryo.tres" % EMBRYOS[index])

func _universal() -> Resource:
	return load("res://items/imprint/universal_embryo.tres")

func _select(index: int) -> void:
	if not _drawn_cards.is_empty():
		return
	_selected = index
	_result.text = "选择属性，消耗卡胚开始刻印"
	_refresh()

func _refresh() -> void:
	if not is_instance_valid(_inventory):
		return
	_balance.text = "%s卡胚  %d     通用卡胚  %d" % [NAMES[_selected], int(_inventory.call("ItemCnt", _resource(_selected))), int(_inventory.call("ItemCnt", _universal()))]
	var pending: bool = not _drawn_cards.is_empty()
	for index in _tab_buttons.size():
		_tab_buttons[index].disabled = pending
		_tab_buttons[index].modulate = ELEMENT_COLORS[index] if index == _selected else Color.WHITE
	for button in _draw_buttons:
		button.disabled = pending
	_confirm_button.disabled = not pending or _revealing

func _perform_draw(count: int) -> void:
	if not _drawn_cards.is_empty() or not is_instance_valid(_inventory):
		return
	var outcome: Dictionary = SERVICE.new().draw(_inventory, ELEMENTS[_selected], _resource(_selected), _universal(), count)
	if outcome.cards.is_empty():
		_result.text = String(outcome.message)
		_refresh()
		return
	_drawn_cards.assign(outcome.cards)
	_selected_indices.clear()
	_revealing = true
	_result.text = "卡胚化作空白卡牌，刻印正在浮现……"
	_show_cards()
	_refresh()

func _show_cards() -> void:
	for child in _card_grid.get_children():
		child.queue_free()
	_slots.clear()
	_selection_labels.clear()
	var animation := create_tween()
	for index in _drawn_cards.size():
		var slot := Button.new()
		slot.flat = true
		slot.focus_mode = Control.FOCUS_NONE
		slot.custom_minimum_size = SLOT_SIZE
		slot.disabled = true
		_card_grid.add_child(slot)
		_slots.append(slot)
		var blank := Sprite2D.new()
		blank.texture = BLANK_CARD
		blank.position = SLOT_SIZE * 0.5
		blank.scale = Vector2.ONE * (1.5 * CARD_SCALE)
		slot.add_child(blank)
		var front: Node2D = CARD_SCENE.instantiate()
		slot.add_child(front)
		front.position = SLOT_SIZE * 0.5
		front.scale = Vector2(CARD_SCALE, CARD_SCALE)
		front.visible = false
		front.call("init_card_data", _drawn_cards[index])
		front.call("unlock")
		var marker := Label.new()
		marker.position = Vector2(8, 112)
		marker.z_index = 3
		marker.add_theme_font_size_override("font_size", 18)
		marker.add_theme_color_override("font_color", Color("#fff2b1"))
		marker.add_theme_color_override("font_outline_color", Color("#3b2419"))
		marker.add_theme_constant_override("outline_size", 4)
		marker.text = "%d星  ·  点击选择" % int(_drawn_cards[index].get("StarLevel"))
		marker.visible = false
		slot.add_child(marker)
		var flash := ColorRect.new()
		flash.position = Vector2(15, 11)
		flash.z_index = 4
		flash.size = SLOT_SIZE - Vector2(30, 22)
		flash.color = ELEMENT_COLORS[_selected]
		flash.modulate.a = 0.0
		flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(flash)
		_selection_labels.append(marker)
		slot.pressed.connect(_toggle_card.bind(index))
		# 每张卡先收拢空白卡，再展开真实卡面；独立下标可保留重复卡。
		animation.tween_property(blank, "scale:x", 0.0, FLIP_HALF_SECONDS).set_trans(Tween.TRANS_SINE)
		animation.tween_callback(_reveal_front.bind(blank, front, marker, flash))
		animation.tween_property(front, "scale:x", CARD_SCALE, FLIP_HALF_SECONDS).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		animation.parallel().tween_property(flash, "modulate:a", 0.0, FLIP_HALF_SECONDS * 1.5)
		animation.tween_interval(REVEAL_GAP_SECONDS)
	animation.tween_callback(_on_reveal_finished)

func _reveal_front(blank: Sprite2D, front: Node2D, marker: Label, flash: ColorRect) -> void:
	blank.hide()
	front.scale.x = 0.0
	front.show()
	marker.show()
	flash.modulate.a = 0.7

func _on_reveal_finished() -> void:
	_revealing = false
	for slot in _slots:
		slot.disabled = false
	_result.text = "点击卡牌选择要获取的卡，可选择任意张"
	_refresh()

func _toggle_card(index: int) -> void:
	if _revealing or index < 0 or index >= _drawn_cards.size() or _drawn_cards[index] == null:
		return
	if _selected_indices.has(index):
		_selected_indices.erase(index)
	else:
		_selected_indices.append(index)
	_selection_labels[index].text = "%d星  ·  %s" % [int(_drawn_cards[index].get("StarLevel")), "已选择 ✓" if _selected_indices.has(index) else "点击选择"]
	_slots[index].modulate = Color("#ffe5a0") if _selected_indices.has(index) else Color.WHITE
	_result.text = "已选择 %d / %d 张；可不选，点击确定结束" % [_selected_indices.size(), _drawn_cards.size()]

func _confirm_selection() -> void:
	if _revealing or _drawn_cards.is_empty() or not is_instance_valid(_inventory):
		return
	var free_slots: int = 0
	for stack in _inventory.get("Slots"):
		if bool(stack.get("IsEmpty")):
			free_slots += 1
	if free_slots < _selected_indices.size():
		_result.text = "背包空位不足，需要 %d 格，当前 %d 格" % [_selected_indices.size(), free_slots]
		return
	# 逐张记录已交付的下标；即使库存监听器同步改变容量，也不会重复发放。
	for index in _selected_indices.duplicate():
		if int(_inventory.call("AddItem", _drawn_cards[index], 1)) != 0:
			_result.text = "背包空间发生变化，请整理后重试"
			_refresh()
			return
		_selected_indices.erase(index)
		_drawn_cards[index] = null
		_slots[index].disabled = true
		_selection_labels[index].text = "已获取"
	_drawn_cards.clear()
	_selected_indices.clear()
	for child in _card_grid.get_children():
		child.queue_free()
	_slots.clear()
	_selection_labels.clear()
	_result.text = "已完成选择，可继续刻印"
	_refresh()

func _request_close() -> void:
	if not _drawn_cards.is_empty():
		_discard_dialog.popup_centered(Vector2i(560, 180))
		return
	_close()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and is_visible_in_tree():
		get_viewport().set_input_as_handled()
		if not _discard_dialog.visible:
			_request_close()

func _close() -> void:
	if is_instance_valid(_backpack):
		_backpack.show()
	queue_free()
