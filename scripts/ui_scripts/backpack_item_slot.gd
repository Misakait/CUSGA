extends ItemSlot

## 背包专用的 item_slot1 兼容适配。
## item_slot1 是轻量场景，旧 ItemSlot 协议仍需要价格标签和选中接口；这里补齐缺失节点并保留原有绑定、拖拽与提示逻辑。

var _layout_rects: Dictionary = {}
var _layout_font_sizes: Dictionary = {}

func _ready() -> void:
	_normal_style = get_theme_stylebox("normal")
	_hover_style = _normal_style
	_selected_style = get_theme_stylebox("pressed")
	# 选中只由区域 Controller 决定，不能让原场景的自动切换或悬停贴图制造第二个点击外观。
	toggle_mode = false
	focus_mode = Control.FOCUS_NONE
	if not mouse_entered.is_connected(_on_mouse_entered):
		mouse_entered.connect(_on_mouse_entered)
	if not mouse_exited.is_connected(_on_mouse_exited):
		mouse_exited.connect(_on_mouse_exited)
	clear_slot()
	set_selected(false)

## 使用 item_slot1 原贴图显示区域决定的持续选中状态。
## @param selected 是否选中；各个区域独立拥有单选状态。
## @return 无返回值。
func set_selected(selected: bool) -> void:
	_is_selected = selected
	if _normal_style == null:
		return
	var style: StyleBox = _selected_style if selected else _normal_style
	# 所有 Button 绘制状态均服从同一选择结果，鼠标按住另一个格子时也不能出现两个点击外观。
	for state: StringName in [&"normal", &"hover", &"pressed", &"hover_pressed", &"disabled"]:
		add_theme_stylebox_override(state, style)

## 沿用三栏原有尺寸，并按 item_slot1 场景里的相对位置缩放图标与文字。
## @param scale_factor 相对于旧格子 96×104 像素尺寸的比例。
## @return 无返回值。
func configure_compact_layout(scale_factor: float) -> void:
	_resolve_nodes()
	var controls: Array[Control] = [_icon, _count_label, _name_label]
	if _layout_rects.is_empty():
		for control: Control in controls:
			_layout_rects[control.name] = Rect2(control.position, control.size)
			if control is Label:
				_layout_font_sizes[control.name] = (control as Label).get_theme_font_size("font_size")
	var factor: float = clampf(scale_factor, 0.25, 1.0)
	custom_minimum_size = Vector2(96.0, 104.0) * factor
	scale = Vector2.ONE
	var layout_scale: Vector2 = custom_minimum_size / Vector2(72.0, 72.0)
	for control: Control in controls:
		var original_rect: Rect2 = _layout_rects[control.name]
		control.position = original_rect.position * layout_scale
		control.size = original_rect.size * layout_scale
		if control is Label:
			var original_font_size: int = int(_layout_font_sizes[control.name])
			(control as Label).add_theme_font_size_override("font_size", maxi(roundi(original_font_size * minf(layout_scale.x, layout_scale.y)), 1))

func _resolve_nodes() -> void:
	# Controller 可在入树前配置尺寸和绑定数据，必须在首次解析节点时补齐旧协议需要的价格标签。
	_ensure_price_label()
	super._resolve_nodes()
	_count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _ensure_price_label() -> void:
	if get_node_or_null("PriceLabel") != null:
		return
	var price_label := Label.new()
	price_label.name = "PriceLabel"
	price_label.visible = false
	price_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(price_label)

