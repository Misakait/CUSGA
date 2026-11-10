extends PanelContainer

## 刻印面板：展示属性池、逐张揭晓卡面，并暂存玩家尚未确认的抽取结果。
## 五行展示顺序及其既有元素枚举值。
const ELEMENTS: Array[int] = [1, 4, 3, 5, 2]
## 五行显示名称。
const NAMES: Array[String] = ["木", "土", "水", "火", "金"]
## 各属性卡胚路径，与显示顺序一致。
const EMBRYOS: Array[String] = ["wood", "earth", "water", "fire", "metal"]
## 属性高亮颜色，与分页显示顺序一致。
const ELEMENT_COLORS: Array[Color] = [Color("#8ee05c"), Color("#ffb850"), Color("#62d1ff"), Color("#ff8371"), Color("#ffe16a")]
## 无状态的刻印业务服务。
const SERVICE: GDScript = preload("res://core/imprint/imprint_service.gd")
## 刻印专用展示组件；业务服务保持独立，不依赖视觉实现。
const STYLE: GDScript = preload("res://core/ui/inventory/imprint_style.gd")
## 直接复用游戏内技能卡场景；不改卡面主题、文字、纹理或资源。
const CARD_SCENE: PackedScene = preload("res://scenes/skill_card_scenes/SkillCard.tscn")
## 原有空白卡胚素材，仅用于揭晓前的背面。
const BLANK_CARD: Texture2D = preload("res://res/skillcard/技能卡模板2.png")
## 像素工坊背景负责卡胚弹跳与彩色纸屑。
const PRESENTATION: GDScript = preload("res://core/ui/inventory/imprint_presentation.gd")
## 音效组件通过展示事件触发。
const AUDIO: GDScript = preload("res://core/ui/inventory/imprint_audio.gd")
## 与开局选卡共用选中上移动画的距离和时长。
const CARD_VISUALS: GDScript = preload("res://core/card_visual_config.gd")
## 确认后卡牌飞行或淡出的时长，单位为秒。
const CLAIM_ANIMATION_SECONDS: float = 0.55
## 每个卡槽沿用原版尺寸，五列两行保留选中抬升空间。
const SLOT_SIZE: Vector2 = Vector2(202, 146)
## 卡面的显示缩放。
const CARD_SCALE: float = 0.82
## 每张卡收拢与展开各需的秒数。
const FLIP_HALF_SECONDS: float = 0.09
## 连续揭晓之间的停顿秒数。
const REVEAL_GAP_SECONDS: float = 0.035
## 汇聚时长；轻动效会缩短为 0.15 秒。
@export_range(0.1, 3.0, 0.05) var charge_seconds: float = 0.55
## 卡背入场时长；由同一揭晓时间线管理，跳过时可完整取消。
const ARRIVAL_SECONDS: float = 0.26
## 稀有卡额外停顿，三星不增加停顿，四星 0.10 秒、五星 0.18 秒。
const RARE_PAUSES: Dictionary = {4: 0.10, 5: 0.18}
## 卡面弹开与弹性收敛时间，避免长尾抖动影响选择。
const POP_SECONDS: float = 0.11
## 回弹收敛时长。
const SETTLE_SECONDS: float = 0.18
## 元素诗句仅作美术说明，不代表额外玩法加成。
const ELEMENT_VERSES: Array[String] = ["来点生机！", "稳稳出招！", "灵感冒泡！", "热力全开！", "闪亮登场！"]

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
## 本批次结果，按抽出位置保存，允许相同资源出现多次。
var _drawn_cards: Array[Resource] = []
## 已选择的卡槽下标；不以资源身份去重。
var _selected_indices: Array[int] = []
## 当前结果卡槽。
var _slots: Array[Button] = []
## 揭晓动画运行期间阻止选择和重复结算。
var _revealing: bool = false
## 当前揭晓序列；跳过时停止，避免后续回调再次改写已展示的卡面。
var _reveal_tween: Tween
## 与卡槽下标对应的空白卡面，用于跳过时一次隐藏。
var _blank_cards: Array[Sprite2D] = []
## 舞台右上方的固定跳过入口，蓄能到揭晓结束期间均可操作。
var _skip_button: Button
## 已交付卡牌的离场动画期间禁止重新选择和重复结算，允许关闭。
var _settling: bool = false
## HUD 共享提示面板；缺失时只关闭悬停提示，不影响刻印。
var _tooltip_panel: Node
## 当前鼠标悬停的卡槽下标，用于避免跨卡移动时旧的退出事件关闭新提示。
var _hovered_index: int = -1
## 是否由本面板发出了提示请求，避免清理时隐藏其他界面的提示。
var _owns_tooltip: bool = false
## 与卡槽下标对应的技能卡视图，用于独立处理重复卡。
var _card_views: Array[Node2D] = []
## 每个卡槽的上移动画；切换选择时先停止旧动画。
var _lift_tweens: Dictionary = {}

## 固定设计坐标根节点；仅缩放这一层，避免容器重排破坏动画坐标。
var _design: Control
## 背景卡胚与纸屑展示组件。
var _presentation: Control
## 合成音效组件。
var _audio: Node
## 空闲时的主题文案组。
var _idle_copy: Control
## 当前五行主题标题。
var _element_title: Label
## 当前五行意象文案。
var _element_verse: Label
## 揭晓进度或收取反馈。
var _stage_label: Label
## 轻动效选项，仅影响展示，不改变抽取结果。
var _reduced_motion: bool = false
## 领取动画引用，卸载或恢复时可确保只有一个活动序列。
var _claim_tween: Tween
## 入场动画引用，避免连续打开产生多个相互竞争的淡入。
var _open_tween: Tween
## 每个按钮只有一个弹性动画，快速进出时替换旧动画避免越缩越大。
var _button_tweens: Dictionary = {}

## 构造界面并绑定玩家库存。
## 参数 inventory：玩家库存；backpack：返回时显示的背包；返回值：无。
func setup(inventory: Node, backpack: Control) -> void:
	_inventory = inventory
	_backpack = backpack
	process_mode = Node.PROCESS_MODE_ALWAYS
	# 刻印面板与开局选卡同处 HUD 根节点，复用同一个鼠标跟随提示框。
	_tooltip_panel = get_node_or_null("../TooltipPanel") if is_inside_tree() else null
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	# 字体与主题只作用于本面板，不改变背包和战斗界面的继承关系。
	## 面板独立主题，系统字体缺失时回退到项目像素字体。
	var pixel_theme := Theme.new()
	pixel_theme.default_font = STYLE.make_font()
	pixel_theme.default_font_size = 22
	theme = pixel_theme
	## 外层画布由 PanelContainer 铺满，内层设计画布独立等比缩放。
	var canvas := Control.new()
	canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(canvas)
	## 超宽或窄窗口的余白使用相同底色，避免边缘露出战斗画面。
	var background := ColorRect.new()
	background.color = Color("#f5b449")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_design = Control.new()
	_design.name = "DesignRoot"
	_design.size = STYLE.DESIGN_SIZE
	_design.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_design.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(_design)
	_presentation = PRESENTATION.new()
	_presentation.size = STYLE.DESIGN_SIZE
	_design.add_child(_presentation)
	_audio = AUDIO.new()
	add_child(_audio)
	_build_header()
	_build_tabs()
	_stage_label = _label("准备好了吗？", Vector2(84, 188), Vector2(800, 24), 18, STYLE.INK)
	_result = _label("选个属性，开始刻印！", Vector2(244, 581), Vector2(792, 32), 22, STYLE.INK)
	_result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	## 中心容器只管理卡槽排版，动效始终施加在卡槽子节点上。
	var center := CenterContainer.new()
	center.position = Vector2(88, 232)
	center.size = Vector2(1104, 330)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_design.add_child(center)
	_card_grid = GridContainer.new()
	_card_grid.columns = 5
	_card_grid.add_theme_constant_override("h_separation", 16)
	_card_grid.add_theme_constant_override("v_separation", 22)
	center.add_child(_card_grid)
	_build_idle_copy()
	_build_actions()
	_skip_button = _make_button("跳过  >>")
	_skip_button.position = Vector2(1060, 181)
	_skip_button.size = Vector2(144, 38)
	_skip_button.hide()
	_skip_button.pressed.connect(_skip_reveal)
	_design.add_child(_skip_button)
	resized.connect(_layout_presentation)
	_select(0)
	_layout_presentation()
	if is_inside_tree():
		_layout_presentation.call_deferred()

## 显示已有刻印面板并刷新材料数量，保留待领取结果。
## 返回值：无。
func Open() -> void:
	show()
	_layout_presentation()
	_refresh()
	if is_inside_tree():
		if _open_tween != null and _open_tween.is_valid():
			_open_tween.kill()
		_design.modulate.a = 0.0
		_open_tween = create_tween()
		_open_tween.tween_property(_design, "modulate:a", 1.0, 0.2)

func _layout_presentation() -> void:
	if not is_instance_valid(_design) or size.x <= 0.0 or size.y <= 0.0:
		return
	## 单一缩放系数保证字体、卡面、鼠标命中框和粒子坐标一起缩放。
	var factor: float = minf(size.x / STYLE.DESIGN_SIZE.x, size.y / STYLE.DESIGN_SIZE.y)
	_design.scale = Vector2.ONE * factor
	_design.position = (size - STYLE.DESIGN_SIZE * factor) * 0.5

func _build_header() -> void:
	## 标题沿用背包的大像素字，以白色描边增强明亮底色上的辨识度。
	var title: Label = _label("五行刻印", Vector2(64, 32), Vector2(320, 58), 44, Color("#fff5bd"))
	title.add_theme_color_override("font_outline_color", Color("#974620"))
	title.add_theme_constant_override("outline_size", 8)
	_label("卡胚一弹，好牌登场！", Vector2(67, 91), Vector2(410, 26), 20, STYLE.INK)
	_balance = _label("", Vector2(615, 61), Vector2(450, 36), 22, STYLE.INK)
	_balance.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	## 返回按钮在蓄力和收取期间始终可用。
	var close := _make_button("返回")
	close.position = Vector2(1102, 54)
	close.size = Vector2(108, 48)
	close.pressed.connect(_request_close)
	_design.add_child(close)

func _build_tabs() -> void:
	for index in NAMES.size():
		## 五行按钮使用独立鲜亮颜色，选中时白描边和弹跳共同反馈。
		var button := _make_button("%s  刻印" % NAMES[index])
		button.position = Vector2(146 + index * 200, 132)
		button.size = Vector2(184, 48)
		button.toggle_mode = true
		button.pressed.connect(_select.bind(index))
		for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
			button.add_theme_stylebox_override(state, STYLE.button_style(ELEMENT_COLORS[index], state))
		_design.add_child(button)
		_tab_buttons.append(button)

func _build_idle_copy() -> void:
	_idle_copy = Control.new()
	_idle_copy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_design.add_child(_idle_copy)
	_element_title = _label("", Vector2(390, 508), Vector2(500, 32), 28, STYLE.INK)
	_element_verse = _label("", Vector2(390, 534), Vector2(500, 23), 18, STYLE.MUTED)
	for label in [_element_title, _element_verse]:
		_design.remove_child(label)
		_idle_copy.add_child(label)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func _build_actions() -> void:
	for index in 2:
		## 卡胚消耗与原规则一致，按钮把单次与十连清晰分开。
		var count: int = 1 if index == 0 else 10
		## 十连按钮更宽，留出足够的点击与回弹空间。
		var button := _make_button("单次刻印 · 1" if count == 1 else "十连刻印 · 10", count == 10)
		button.position = Vector2(228 if index == 0 else 508, 631)
		button.size = Vector2(248 if index == 0 else 304, 56)
		button.pressed.connect(_perform_draw.bind(count))
		_design.add_child(button)
		_draw_buttons.append(button)
	_confirm_button = _make_button("确定获取")
	_confirm_button.position = Vector2(844, 631)
	_confirm_button.size = Vector2(248, 56)
	_confirm_button.pressed.connect(_confirm_selection)
	_design.add_child(_confirm_button)
	## 轻动效只影响展示，保留同一份抽取结果和扣料规则。
	var motion := CheckButton.new()
	motion.text = "轻动效"
	motion.position = Vector2(50, 643)
	motion.size = Vector2(154, 38)
	motion.add_theme_font_size_override("font_size", 16)
	motion.add_theme_color_override("font_color", STYLE.INK)
	motion.toggled.connect(_set_reduced_motion)
	_design.add_child(motion)
	_label("属性卡胚优先，不足使用通用卡胚", Vector2(430, 695), Vector2(700, 20), 14, STYLE.INK)

func _label(value: String, at: Vector2, bounds: Vector2, font_size: int, color: Color) -> Label:
	## 静态文案不接收鼠标事件，保证舞台和按钮的输入路径单一。
	var label := Label.new()
	label.text = value
	label.position = at
	label.size = bounds
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_design.add_child(label)
	return label

func _make_button(label: String, primary: bool = false) -> Button:
	## 按钮主题只作用于外部操作，不向真实 SkillCard 注入任何样式。
	var button := Button.new()
	button.text = label
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 22)
	button.add_theme_color_override("font_color", STYLE.INK)
	button.add_theme_color_override("font_hover_color", Color("#51260f"))
	button.add_theme_color_override("font_pressed_color", STYLE.INK)
	button.add_theme_color_override("font_hover_pressed_color", STYLE.INK)
	button.add_theme_color_override("font_disabled_color", Color("#886c55"))
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		button.add_theme_stylebox_override(state, STYLE.button_style(STYLE.GOLD, state, primary))
	button.mouse_entered.connect(_bounce_button.bind(button, Vector2(1.045, 1.045)))
	button.mouse_exited.connect(_bounce_button.bind(button, Vector2.ONE))
	button.button_down.connect(_bounce_button.bind(button, Vector2(1.06, 0.88)))
	button.button_up.connect(_bounce_button.bind(button, Vector2.ONE))
	return button

func _bounce_button(button: Button, target: Vector2) -> void:
	if not is_inside_tree() or not is_instance_valid(button):
		return
	## 按下的宽扁与释放的弹性收敛模拟果冻形变，焦点和点击区域跟随实际按钮。
	var previous: Tween = _button_tweens.get(button)
	if previous != null and previous.is_valid():
		previous.kill()
	button.pivot_offset = button.size * 0.5
	if _reduced_motion or button.disabled:
		button.scale = Vector2.ONE
		return
	## 每次输入都从当前缩放起步，不叠加相对比例。
	var tween := create_tween()
	_button_tweens[button] = tween
	tween.tween_property(button, "scale", target, 0.10 if target.y < 1.0 else 0.32).set_trans(Tween.TRANS_QUAD if target.y < 1.0 else Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

func _set_reduced_motion(enabled: bool) -> void:
	_reduced_motion = enabled
	_presentation.set("reduced_motion", enabled)
	if enabled and _revealing:
		_skip_reveal()

func _resource(index: int) -> Resource:
	return load("res://items/imprint/%s_embryo.tres" % EMBRYOS[index])

func _universal() -> Resource:
	return load("res://items/imprint/universal_embryo.tres")

func _select(index: int) -> void:
	if not _drawn_cards.is_empty():
		return
	_selected = index
	_result.text = "选个属性，开始刻印！"
	_element_title.text = "%s · %s" % [NAMES[index], ELEMENT_VERSES[index]]
	_element_verse.text = "单抽试试手气，十连快乐加倍"
	_presentation.call("set_element", ELEMENT_COLORS[index], NAMES[index])
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
	_idle_copy.visible = not pending and not _settling
	_presentation.set("result_mode", pending and not _revealing)
	_skip_button.visible = _revealing
	_confirm_button.text = "确定获取" if _selected_indices.is_empty() else "确定获取  /  %d" % _selected_indices.size()
	_confirm_button.tooltip_text = "未选中的卡牌将被放弃" if pending else "完成刻印并选择想要保留的卡牌"

func _perform_draw(count: int) -> void:
	if _settling or _revealing or not _drawn_cards.is_empty() or not is_instance_valid(_inventory):
		return
	var outcome: Dictionary = SERVICE.new().draw(_inventory, ELEMENTS[_selected], _resource(_selected), _universal(), count)
	if outcome.cards.is_empty():
		_result.text = String(outcome.message)
		_refresh()
		return
	_drawn_cards.assign(outcome.cards)
	_selected_indices.clear()
	_revealing = true
	_result.text = "蓄力中... 好牌马上弹出来！"
	_stage_label.text = "卡胚就位，准备弹射！"
	_audio.call("play_cue", "charge")
	_show_cards()
	_refresh()

func _show_cards() -> void:
	for child in _card_grid.get_children():
		_card_grid.remove_child(child)
		child.queue_free()
	_slots.clear()
	_card_views.clear()
	_blank_cards.clear()
	_lift_tweens.clear()
	## 蓄力、入场与揭晓共享时间线，跳过时不会残留延迟回调。
	var animation := create_tween()
	_reveal_tween = animation
	_presentation.set("result_mode", false)
	animation.tween_property(_presentation, "energy", 1.0, 0.12 if _reduced_motion else charge_seconds).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	animation.tween_callback(_release_seal)
	for index in _drawn_cards.size():
		## 卡槽保持原版尺寸，最终卡面缩放同样沿用原参数。
		var slot := Button.new()
		slot.flat = true
		slot.focus_mode = Control.FOCUS_ALL
		slot.custom_minimum_size = SLOT_SIZE
		slot.disabled = true
		slot.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			slot.add_theme_stylebox_override(state, StyleBoxEmpty.new())
		_card_grid.add_child(slot)
		_slots.append(slot)
		## 空白卡胚只做入场形变，背面仍使用既有游戏素材。
		var blank := Sprite2D.new()
		blank.texture = BLANK_CARD
		blank.position = SLOT_SIZE * 0.5 + Vector2(0, 75)
		blank.scale = Vector2.ONE * (1.5 * CARD_SCALE * 0.18)
		blank.modulate.a = 0.0
		slot.add_child(blank)
		_blank_cards.append(blank)
		## 真实技能卡直接实例化生产场景，绑定同一个 Resource，不重画卡面。
		var front: Node2D = CARD_SCENE.instantiate()
		slot.add_child(front)
		_card_views.append(front)
		front.position = SLOT_SIZE * 0.5
		front.scale = Vector2.ONE * CARD_SCALE
		front.visible = false
		front.call("init_card_data", _drawn_cards[index])
		front.call("unlock")
		slot.pressed.connect(_toggle_card.bind(index))
		slot.mouse_entered.connect(_on_card_slot_mouse_entered.bind(index))
		slot.mouse_exited.connect(_on_card_slot_mouse_exited.bind(index))
		slot.focus_entered.connect(_on_card_slot_mouse_entered.bind(index))
		slot.focus_exited.connect(_on_card_slot_mouse_exited.bind(index))
		## 十连错拍弹入，同一并行段不会把十次入场时间累加。
		if index == 0:
			animation.tween_property(blank, "modulate:a", 1.0, 0.10)
		else:
			animation.parallel().tween_property(blank, "modulate:a", 1.0, 0.10).set_delay(index * 0.028)
		animation.parallel().tween_property(blank, "position", SLOT_SIZE * 0.5, ARRIVAL_SECONDS).set_delay(index * 0.028).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		animation.parallel().tween_property(blank, "scale", Vector2.ONE * (1.5 * CARD_SCALE), ARRIVAL_SECONDS).set_delay(index * 0.028).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	animation.tween_interval(0.05)
	for index in _drawn_cards.size():
		## 读取真实星级决定停顿与纸屑，抽取结果只由业务服务产生一次。
		var stars: int = int(_drawn_cards[index].get("StarLevel"))
		animation.tween_callback(_focus_reveal.bind(index))
		if stars >= 4 and not _reduced_motion:
			animation.tween_interval(float(RARE_PAUSES.get(stars, 0.18)))
		animation.tween_property(_blank_cards[index], "scale:x", 0.0, FLIP_HALF_SECONDS).set_trans(Tween.TRANS_QUAD)
		animation.tween_callback(_reveal_front.bind(index))
		animation.tween_property(_card_views[index], "scale", Vector2(1.12, 0.87) * CARD_SCALE, POP_SECONDS).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		animation.parallel().tween_property(_card_views[index], "rotation", 0.0, POP_SECONDS)
		animation.tween_property(_card_views[index], "scale", Vector2.ONE * CARD_SCALE, SETTLE_SECONDS).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		animation.tween_interval(REVEAL_GAP_SECONDS)
	animation.tween_callback(_on_reveal_finished)

func _release_seal() -> void:
	_presentation.set("result_mode", true)
	_presentation.set("energy", 0.0)
	_presentation.call("burst", PRESENTATION.CENTER, ELEMENT_COLORS[_selected], 5)
	_stage_label.text = "啪！惊喜弹出来啦"

func _focus_reveal(index: int) -> void:
	_stage_label.text = "惊喜揭晓  %d / %d" % [index + 1, _drawn_cards.size()]

func _reveal_front(index: int) -> void:
	_blank_cards[index].hide()
	## 拉长再压扁后回到原比例，只改变实例的临时变换，不改变卡牌资源。
	var front: Node2D = _card_views[index]
	front.scale = Vector2(0.04, 1.24) * CARD_SCALE
	front.rotation = -0.06 if index % 2 == 0 else 0.06
	front.show()
	## 纸屑在卡面背后爆开，卡上的名称、描述和颜色保持清晰。
	var stars: int = int(_drawn_cards[index].get("StarLevel"))
	_presentation.call("burst", _design.get_global_transform().affine_inverse() * front.global_position, STYLE.rarity_color(stars), stars)
	_audio.call("play_cue", "rare" if stars >= 4 else "reveal", 1.0 + float(index % 5) * 0.07)

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
		_card_views[index].position = SLOT_SIZE * 0.5
		_card_views[index].rotation = 0.0
		_card_views[index].show()
	_audio.call("stop_all")
	_presentation.call("settle")
	_on_reveal_finished()

func _on_reveal_finished() -> void:
	_revealing = false
	_reveal_tween = null
	_skip_button.hide()
	_presentation.set("result_mode", true)
	_presentation.set("energy", 0.0)
	for slot in _slots:
		slot.disabled = false
	_stage_label.text = "好牌到手！挑选想带走的技能卡"
	_result.text = "已选择%d/%d张" % [_selected_indices.size(), _drawn_cards.size()]
	_refresh()
	# 鼠标可能在揭晓结束前已经进入卡槽；此时不会再触发新的进入事件。
	if _hovered_index >= 0 and _hovered_index < _slots.size():
		if _slots[_hovered_index].get_global_rect().has_point(get_global_mouse_position()):
			_show_card_tooltip(_hovered_index)

## 鼠标进入卡槽时显示已揭晓技能卡的名称与描述。
## 参数 index：卡槽下标；返回值：无。
func _on_card_slot_mouse_entered(index: int) -> void:
	_hovered_index = index
	if not _revealing and not _settling:
		_animate_card_lift(index, _selected_indices.has(index))
	_show_card_tooltip(index)

## 鼠标离开当前卡槽时取消对应提示。
## 参数 index：卡槽下标；返回值：无。
func _on_card_slot_mouse_exited(index: int) -> void:
	if _hovered_index != index:
		return
	_hovered_index = -1
	if not _revealing and not _settling:
		_animate_card_lift(index, _selected_indices.has(index))
	_hide_card_tooltip()

## 按开局选卡使用的显示字段请求延迟悬停提示。
## 参数 index：卡槽下标；返回值：无。
func _show_card_tooltip(index: int) -> void:
	if _revealing or _settling or not is_instance_valid(_tooltip_panel):
		return
	if index < 0 or index >= _drawn_cards.size() or _drawn_cards[index] == null:
		return
	if not _tooltip_panel.has_method("show_tooltip"):
		return
	var card: Resource = _drawn_cards[index]
	var title: Variant = card.get("DisplayName")
	var description: Variant = card.get("DisplayDescription")
	if title == null or str(title).strip_edges().is_empty():
		title = card.get("CardName")
	if description == null or str(description).strip_edges().is_empty():
		description = card.get("Description")
	_tooltip_panel.call("show_tooltip", str(title) if title != null else "", str(description) if description != null else "")
	_owns_tooltip = true

## 清除本界面发出的提示，避免延迟显示残留在其他界面。
## 返回值：无。
func _hide_card_tooltip() -> void:
	if _owns_tooltip and is_instance_valid(_tooltip_panel) and _tooltip_panel.has_method("hide_tooltip"):
		_tooltip_panel.call("hide_tooltip")
	_owns_tooltip = false

func _toggle_card(index: int) -> void:
	if _revealing or _settling or index < 0 or index >= _drawn_cards.size() or _drawn_cards[index] == null:
		return
	if _selected_indices.has(index):
		_selected_indices.erase(index)
	else:
		_selected_indices.append(index)
	_animate_card_lift(index, _selected_indices.has(index))
	_audio.call("play_cue", "select", 1.0 if _selected_indices.has(index) else 0.8)
	_result.text = "已选择%d/%d张" % [_selected_indices.size(), _drawn_cards.size()]
	_refresh()

## 按开局选卡的统一距离和时间移动卡面。
## 参数 index：卡槽下标；lifted：是否上移；返回值：无。
func _animate_card_lift(index: int, lifted: bool) -> void:
	if index < 0 or index >= _card_views.size():
		return
	## 停止旧动画，快速点击时仍以当前位置平滑收敛到同一个终点。
	var previous: Tween = _lift_tweens.get(index)
	if previous != null and previous.is_valid():
		previous.kill()
	## 选中抬升保持原距离，悬停只附加很小的弹起。
	var offset: float = -CARD_VISUALS.CLICK_SELECTED_LIFT_DISTANCE if lifted else 0.0
	if _hovered_index == index and not lifted:
		offset -= 8.0
	## 真实卡面只做节点变换，不修改其字体、材质和资源。
	var card: Node2D = _card_views[index]
	## 最终位置与原始槽中心一致。
	var target: Vector2 = SLOT_SIZE * 0.5 + Vector2(0, offset)
	if not is_inside_tree():
		card.position = target
		return
	## 选中位置使用共用的 0.12 秒，缩放回弹稍长以营造跟手的 QQ 感。
	var tween := create_tween().set_parallel(true)
	_lift_tweens[index] = tween
	tween.tween_property(card, "position", target, CARD_VISUALS.CLICK_SELECTED_LIFT_DURATION).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "scale", Vector2.ONE * CARD_SCALE * (1.035 if _hovered_index == index and not _reduced_motion else 1.0), 0.24).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

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
	_hide_card_tooltip()
	_hovered_index = -1
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
	_claim_tween = animation
	_stage_label.text = "装进口袋，下次再来！"
	_result.text = "正在收取 %d 张刻印" % claimed_indices.size()
	if not claimed_indices.is_empty():
		_audio.call("play_cue", "claim")
	for index in _card_views.size():
		var previous: Tween = _lift_tweens.get(index)
		if previous != null and previous.is_valid():
			previous.kill()
		_slots[index].disabled = true
		var card: Node2D = _card_views[index]
		if claimed_indices.has(index):
			card.z_index = 20
			_presentation.call("burst", _design.get_global_transform().affine_inverse() * card.global_position, STYLE.GOLD, 3)
			# 先小幅向上回弹，再加速收入背包；位置与缩放共用终点，避免抖动残留。
			animation.tween_property(card, "global_position", destination, CLAIM_ANIMATION_SECONDS).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
			animation.tween_property(card, "scale", Vector2.ZERO, CLAIM_ANIMATION_SECONDS).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
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
	_card_views.clear()
	_blank_cards.clear()
	_lift_tweens.clear()
	_settling = false
	_claim_tween = null
	_presentation.call("settle")
	_presentation.set("result_mode", false)
	_stage_label.text = "准备好了吗？"
	_result.text = "已完成选择，可继续刻印"
	_refresh()

func _request_close() -> void:
	# 关闭时直接归一化揭晓终态，重新打开无需等待不可见动画，也不会重新扣材料。
	if _revealing:
		_skip_reveal()
	_audio.call("stop_all")
	_presentation.call("settle")
	_hide_card_tooltip()
	_hovered_index = -1
	_close()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and is_visible_in_tree():
		get_viewport().set_input_as_handled()
		_request_close()

func _close() -> void:
	_hide_card_tooltip()
	hide()
	if is_instance_valid(_backpack):
		_backpack.show()

## 场景卸载时也取消悬停延迟，避免共享提示在其他界面中继续出现。
## 返回值：无。
func _exit_tree() -> void:
	_hide_card_tooltip()
	for animation in [_reveal_tween, _claim_tween, _open_tween] + _button_tweens.values():
		if animation != null and animation.is_valid():
			animation.kill()
