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
## 禁用与选中分页共用的灰色像素底图，不依赖颜色叠乘。
const INACTIVE_BUTTON_TEXTURE: Texture2D = preload("res://res/UI/背包格子-未选中-选中的样子.png")
## 与开局选卡共用选中上移动画的距离和时长。
const CARD_VISUALS: GDScript = preload("res://core/card_visual_config.gd")
## 确认后卡牌飞行或淡出的时长，单位为秒。
const CLAIM_ANIMATION_SECONDS: float = 0.55
## 刻印桌背景素材。
const TABLE_TEXTURE: Texture2D = preload("res://res/UI/imprint/imprint_table.png")
## 每个卡槽尺寸，五列两行能在 1280×720 的基准画面中展示十张卡。
const SLOT_SIZE: Vector2 = Vector2(202, 146)
## 卡面的显示缩放。
const CARD_SCALE: float = 0.82
## 卡牌选择提示占满卡槽宽度，选中时与卡面同步上移。
const SELECTION_MARKER_SIZE: Vector2 = Vector2(SLOT_SIZE.x, 24)
## 卡面未缩放高度为 150 像素；提示位于卡面下缘外 3 像素处。
const SELECTION_MARKER_POSITION: Vector2 = Vector2(0, SLOT_SIZE.y * 0.5 + 75.0 * CARD_SCALE + 3.0)
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
## 当前揭晓序列；跳过时停止，避免后续回调再次改写已展示的卡面。
var _reveal_tween: Tween
## 与卡槽下标对应的空白卡面，用于跳过时一次隐藏。
var _blank_cards: Array[Sprite2D] = []
## 与卡槽下标对应的揭晓闪光，用于跳过时消除残留。
var _reveal_flashes: Array[ColorRect] = []
## 第一张卡右上方的跳过入口，仅在揭晓期间存在。
var _skip_button: Button
## 已交付卡牌的离场动画期间禁止关闭、重新选择和重复结算。
var _settling: bool = false
## 与卡槽下标对应的技能卡视图，用于独立处理重复卡。
var _card_views: Array[Node2D] = []
## 每个卡槽的上移动画；切换选择时先停止旧动画。
var _lift_tweens: Dictionary = {}

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
		button.toggle_mode = true
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
	# 灰色底图包括禁用和选中两种状态，统一使用白字保证对比度。
	button.add_theme_color_override("font_disabled_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.add_theme_color_override("font_hover_pressed_color", Color.WHITE)
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var style := StyleBoxTexture.new()
		# 选中与不可操作状态使用同一张真实灰色像素贴图，而不是给原贴图染色。
		var inactive: bool = state in ["pressed", "hover_pressed", "disabled"]
		style.texture = INACTIVE_BUTTON_TEXTURE if inactive else BUTTON_TEXTURE
		style.region_rect = Rect2(0, 0, 32, 32) if inactive else Rect2(0, 16, 64, 32)
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
		_tab_buttons[index].set_pressed_no_signal(index == _selected)
		_tab_buttons[index].disabled = pending or _settling
	for button in _draw_buttons:
		button.disabled = pending or _settling
	_confirm_button.disabled = not pending or _revealing or _settling

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
	_result.text = "刻印中..."
	_show_cards()
	_refresh()

func _show_cards() -> void:
	for child in _card_grid.get_children():
		child.queue_free()
	_slots.clear()
	_selection_labels.clear()
	_card_views.clear()
	_blank_cards.clear()
	_reveal_flashes.clear()
	_lift_tweens.clear()
	var animation := create_tween()
	_reveal_tween = animation
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
		_blank_cards.append(blank)
		var front: Node2D = CARD_SCENE.instantiate()
		_card_views.append(front)
		slot.add_child(front)
		front.position = SLOT_SIZE * 0.5
		front.scale = Vector2(CARD_SCALE, CARD_SCALE)
		front.visible = false
		front.call("init_card_data", _drawn_cards[index])
		front.call("unlock")
		var marker := Label.new()
		marker.position = SELECTION_MARKER_POSITION
		marker.size = SELECTION_MARKER_SIZE
		marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		marker.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		marker.z_index = 3
		marker.add_theme_font_size_override("font_size", 18)
		marker.add_theme_color_override("font_color", Color("#fff2b1"))
		marker.add_theme_color_override("font_outline_color", Color("#3b2419"))
		marker.add_theme_constant_override("outline_size", 4)
		marker.text = "点击选择"
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
		_reveal_flashes.append(flash)
		_selection_labels.append(marker)
		slot.pressed.connect(_toggle_card.bind(index))
		if index == 0:
			# 将入口挂在第一个卡槽上方，使单抽和十连都与各自的左上角卡牌对齐。
			_skip_button = Button.new()
			_skip_button.text = "跳过"
			_skip_button.flat = true
			_skip_button.focus_mode = Control.FOCUS_NONE
			_skip_button.position = Vector2(SLOT_SIZE.x - 72, -36)
			_skip_button.size = Vector2(72, 32)
			_skip_button.z_index = 10
			_skip_button.add_theme_color_override("font_color", Color.WHITE)
			_skip_button.add_theme_color_override("font_hover_color", Color("#ffe2a1"))
			_skip_button.pressed.connect(_skip_reveal)
			slot.add_child(_skip_button)
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

## 立即完成当前揭晓，并保留每个卡槽对应的抽取结果。
## 返回值：无。
func _skip_reveal() -> void:
	if not _revealing:
		return
	# 先停止原序列，再恢复所有卡面终态，避免旧 Tween 在跳过后继续翻转。
	if _reveal_tween != null and _reveal_tween.is_valid():
		_reveal_tween.kill()
	for index in _card_views.size():
		_blank_cards[index].hide()
		_card_views[index].scale = Vector2.ONE * CARD_SCALE
		_card_views[index].show()
		_selection_labels[index].show()
		_reveal_flashes[index].modulate.a = 0.0
	_on_reveal_finished()

func _on_reveal_finished() -> void:
	_revealing = false
	_reveal_tween = null
	if is_instance_valid(_skip_button):
		_skip_button.queue_free()
		_skip_button = null
	for slot in _slots:
		slot.disabled = false
	_result.text = "点击卡牌选择要获取的卡，可选择任意张"
	_refresh()

func _toggle_card(index: int) -> void:
	if _revealing or _settling or index < 0 or index >= _drawn_cards.size() or _drawn_cards[index] == null:
		return
	if _selected_indices.has(index):
		_selected_indices.erase(index)
	else:
		_selected_indices.append(index)
	_animate_card_lift(index, _selected_indices.has(index))
	_result.text = "已选择 %d / %d 张；可不选，点击确定结束" % [_selected_indices.size(), _drawn_cards.size()]

## 按开局选卡的统一距离和时间移动卡面与选择提示。
## 参数 index：卡槽下标；lifted：是否上移；返回值：无。
func _animate_card_lift(index: int, lifted: bool) -> void:
	if index >= _card_views.size() or index >= _selection_labels.size():
		return
	var previous: Tween = _lift_tweens.get(index)
	if previous != null and previous.is_valid():
		previous.kill()
	var offset: float = -CARD_VISUALS.CLICK_SELECTED_LIFT_DISTANCE if lifted else 0.0
	var card: Node2D = _card_views[index]
	var marker: Label = _selection_labels[index]
	var target: Vector2 = SLOT_SIZE * 0.5 + Vector2(0, offset)
	var marker_target: Vector2 = SELECTION_MARKER_POSITION + Vector2(0, offset)
	if not is_inside_tree():
		card.position = target
		marker.position = marker_target
		return
	var tween := create_tween().set_parallel(true)
	_lift_tweens[index] = tween
	tween.tween_property(card, "position", target, CARD_VISUALS.CLICK_SELECTED_LIFT_DURATION)
	tween.tween_property(marker, "position", marker_target, CARD_VISUALS.CLICK_SELECTED_LIFT_DURATION)

func _confirm_selection() -> void:
	if _revealing or _settling or _drawn_cards.is_empty() or not is_instance_valid(_inventory):
		return
	var free_slots: int = 0
	for stack in _inventory.get("Slots"):
		if bool(stack.get("IsEmpty")):
			free_slots += 1
	if free_slots < _selected_indices.size():
		_result.text = "背包空位不足，需要 %d 格，当前 %d 格" % [_selected_indices.size(), free_slots]
		return
	# 先锁定本批次，避免同步库存信号或重复点击造成重复领取。
	_settling = true
	_refresh()
	var claimed_indices: Array[int] = []
	# 逐张记录已交付的下标；即使库存监听器同步改变容量，也不会重复发放。
	for index in _selected_indices.duplicate():
		if int(_inventory.call("AddItem", _drawn_cards[index], 1)) != 0:
			_settling = false
			_result.text = "背包空间发生变化，请整理后重试"
			_refresh()
			return
		claimed_indices.append(index)
		_selected_indices.erase(index)
		_drawn_cards[index] = null
		_slots[index].disabled = true
	_animate_claimed_cards(claimed_indices)

## 已获取的卡飞向背包锚点，未获取的卡同时淡出。
## 参数 claimed_indices：本次成功写入库存的卡槽下标；返回值：无。
func _animate_claimed_cards(claimed_indices: Array[int]) -> void:
	if not is_inside_tree() or _card_views.size() != _slots.size() or _card_views.is_empty():
		_finish_claim_animation()
		return
	var destination: Vector2 = global_position + size - Vector2(20, 20)
	var hud: Node = get_parent()
	var target: Control = hud.get_node_or_null("BackpackButton/BackpackFlyTarget") as Control if hud != null else null
	if is_instance_valid(target):
		destination = target.get_global_rect().get_center()
	var animation := create_tween().set_parallel(true)
	for index in _card_views.size():
		var previous: Tween = _lift_tweens.get(index)
		if previous != null and previous.is_valid():
			previous.kill()
		_slots[index].disabled = true
		var card: Node2D = _card_views[index]
		var marker: Label = _selection_labels[index]
		animation.tween_property(marker, "modulate:a", 0.0, CLAIM_ANIMATION_SECONDS * 0.45)
		if claimed_indices.has(index):
			card.z_index = 20
			animation.tween_property(card, "global_position", destination, CLAIM_ANIMATION_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
			animation.tween_property(card, "scale", Vector2.ZERO, CLAIM_ANIMATION_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		else:
			animation.tween_property(card, "modulate:a", 0.0, CLAIM_ANIMATION_SECONDS)
	animation.chain().tween_callback(_finish_claim_animation)

## 离场结束后清理本批结果并允许继续刻印。
## 返回值：无。
func _finish_claim_animation() -> void:
	_drawn_cards.clear()
	_selected_indices.clear()
	for child in _card_grid.get_children():
		child.queue_free()
	_slots.clear()
	_selection_labels.clear()
	_card_views.clear()
	_blank_cards.clear()
	_reveal_flashes.clear()
	_lift_tweens.clear()
	_settling = false
	_result.text = "已完成选择，可继续刻印"
	_refresh()

func _request_close() -> void:
	if _settling:
		return
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
