extends ProgressBar
class_name StatBar

var text_label: Label
var catchup_bar: ProgressBar
var tween: Tween

func _ready() -> void:
	# 自动寻找名字里带有 Text 的 Label
	for child in get_children():
		if child is Label and "Text" in child.name:
			text_label = child
			break

	# 动态创建缓冲血条（底层白色）
	_setup_catchup_bar()

	# 确保初始显示正确
	_update_text(value, max_value)

func _setup_catchup_bar() -> void:
	# 复制当前的背景样式
	var bg_style = get_theme_stylebox("background")
	# 复制当前的填充样式来获取圆角等信息
	var fill_style = get_theme_stylebox("fill")

	catchup_bar = ProgressBar.new()
	catchup_bar.show_percentage = false
	catchup_bar.max_value = max_value
	catchup_bar.value = value
	catchup_bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	catchup_bar.show_behind_parent = true # 放在自己后面
	catchup_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var catchup_fill = StyleBoxFlat.new()
	catchup_fill.bg_color = Color.WHITE
	if fill_style is StyleBoxFlat:
		catchup_fill.corner_radius_top_left = fill_style.corner_radius_top_left
		catchup_fill.corner_radius_top_right = fill_style.corner_radius_top_right
		catchup_fill.corner_radius_bottom_right = fill_style.corner_radius_bottom_right
		catchup_fill.corner_radius_bottom_left = fill_style.corner_radius_bottom_left

	catchup_bar.add_theme_stylebox_override("fill", catchup_fill)
	catchup_bar.add_theme_stylebox_override("background", bg_style)

	# 把自己的背景设为透明，这样就能透出缓冲条的白色和背景
	var empty_bg = StyleBoxEmpty.new()
	add_theme_stylebox_override("background", empty_bg)

	add_child(catchup_bar)

func update_stat(current_val: float, max_val: float, instant: bool = false) -> void:
	self.max_value = max_val
	catchup_bar.max_value = max_val

	_update_text(current_val, max_val)

	if current_val < self.value:
		# 扣血时，前置条立刻掉，缓冲条缓慢掉
		self.value = current_val
		if not instant:
			if tween and tween.is_valid():
				tween.kill()
			tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			# 稍微延迟一下再掉缓冲条
			tween.tween_property(catchup_bar, "value", current_val, 0.4).set_delay(0.2)
		else:
			catchup_bar.value = current_val
	else:
		# 回血时，前置条缓慢涨，或者瞬间涨
		if not instant:
			if tween and tween.is_valid():
				tween.kill()
			tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tween.tween_property(self, "value", current_val, 0.3)
			tween.parallel().tween_property(catchup_bar, "value", current_val, 0.3)
		else:
			self.value = current_val
			catchup_bar.value = current_val

func _update_text(current_val: float, max_val: float) -> void:
	if text_label:
		text_label.text = str(int(current_val)) + "/" + str(int(max_val))
