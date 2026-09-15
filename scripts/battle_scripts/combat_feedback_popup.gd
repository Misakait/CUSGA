## 可复用的战斗浮字节点。
## 节点播放完成后不自行销毁，而是通知导演回收到对象池，避免多段伤害频繁分配 UI 节点。
class_name CombatFeedbackPopup
extends Control

## 普通浮字的默认字号。
const BASE_FONT_SIZE: float = 28.0

## 普通浮字的描边宽度，用于保证数字在战场背景上的可读性。
const NORMAL_OUTLINE_SIZE: int = 4

## 暴击等强调浮字的描边宽度，通过更粗笔画模拟加粗效果。
const EMPHASIZED_OUTLINE_SIZE: int = 6

## 下划线与文字基线之间的额外间距。
const UNDERLINE_VERTICAL_OFFSET: float = 3.0

## 浮字播放完成时发出，参数是可立即复用的浮字节点。
signal playback_finished(popup: CombatFeedbackPopup)

## 承载数字和结果标签的文本控件。
var _label: Label

## 当前浮字正在运行的 Tween；回收时必须终止，防止旧动画改写新内容。
var _playback_tween: Tween

## 当前浮字是否需要绘制下划线；击杀数字通过此状态表达终结感而不增加文字标签。
var _is_underlined: bool = false

## 初始化稳定的 Label 结构，后续播放只更新内容而不重复创建子节点。
## @return void 无返回值。
func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(96.0, 42.0)
	pivot_offset = custom_minimum_size * 0.5
	_label = Label.new()
	_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_color_override("font_outline_color", Color(0.08, 0.06, 0.10, 1.0))
	_label.add_theme_constant_override("outline_size", NORMAL_OUTLINE_SIZE)
	add_child(_label)
	hide()

## 用一份已结算结果启动浮字动画。
## @param text 要显示的伤害数值或结果标签。
## @param text_color 与结果语义对应的颜色。
## @param screen_position 屏幕坐标系中的起始位置。
## @param scale_multiplier 用于暴击、击杀和连击中段的大小差异。
## @param rise_distance 向上漂浮的像素距离。
## @param duration 动画总时长。
## @param is_underlined 是否在数字下方绘制下划线。
## @param is_emphasized 是否使用更粗的描边强调文字。
## @param start_delay 浮字开始显示前的延迟，用于将同帧多段结算错开为连续出现。
## @return void 无返回值。
func play_feedback(text: String, text_color: Color, screen_position: Vector2, scale_multiplier: float, rise_distance: float, duration: float, is_underlined: bool = false, is_emphasized: bool = false, start_delay: float = 0.0) -> void:
	stop_feedback()
	_label.text = text
	_label.add_theme_color_override("font_color", text_color)
	_label.add_theme_font_size_override("font_size", roundi(BASE_FONT_SIZE * scale_multiplier))
	_label.add_theme_constant_override("outline_size", EMPHASIZED_OUTLINE_SIZE if is_emphasized else NORMAL_OUTLINE_SIZE)
	_is_underlined = is_underlined
	position = screen_position - custom_minimum_size * 0.5
	scale = Vector2.ONE * scale_multiplier
	modulate = Color.WHITE
	if start_delay > 0.0:
		hide()
	else:
		show()
	queue_redraw()

	# 先轻微放大再回落，让文字的出现与目标受力处于同一拍，而不是平铺直叙地上移。
	_playback_tween = create_tween()
	if start_delay > 0.0:
		# 多段伤害在权威结算中可能同帧发出，先延迟显示可使每段数字按顺序进入画面。
		_playback_tween.tween_interval(start_delay)
		_playback_tween.tween_callback(func() -> void: show())
	_playback_tween.set_parallel(true)
	_playback_tween.tween_property(self, "position", position + Vector2(0.0, -rise_distance), duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_playback_tween.tween_property(self, "modulate:a", 0.0, duration * 0.55).set_delay(duration * 0.45)
	_playback_tween.tween_property(self, "scale", Vector2.ONE * scale_multiplier * 1.10, duration * 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_playback_tween.chain().tween_property(self, "scale", Vector2.ONE * scale_multiplier, duration * 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_playback_tween.finished.connect(_finish_playback, CONNECT_ONE_SHOT)

## 中止旧动画并隐藏节点，供导演在高优先级事件抢占时安全回收。
## @return void 无返回值。
func stop_feedback() -> void:
	if _playback_tween and _playback_tween.is_valid() and _playback_tween.is_running():
		_playback_tween.kill()
	_playback_tween = null
	_is_underlined = false
	hide()
	queue_redraw()

## 在击杀数字下方绘制短线，使终结结果只依赖数字本身而不需要额外文字标签。
## @return void 无返回值。
func _draw() -> void:
	if not _is_underlined:
		return
	var font: Font = _label.get_theme_font("font")
	if font == null:
		return
	var font_size: int = _label.get_theme_font_size("font_size")
	var text_size: Vector2 = font.get_string_size(_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size)
	var line_width: float = minf(text_size.x, custom_minimum_size.x - NORMAL_OUTLINE_SIZE * 2.0)
	var line_start_x: float = (custom_minimum_size.x - line_width) * 0.5
	var line_y: float = (custom_minimum_size.y + text_size.y) * 0.5 + UNDERLINE_VERTICAL_OFFSET
	draw_line(Vector2(line_start_x, line_y), Vector2(line_start_x + line_width, line_y), _label.get_theme_color("font_color"), 2.0)

## 将完成的节点交回导演对象池。
## @return void 无返回值。
func _finish_playback() -> void:
	_playback_tween = null
	hide()
	playback_finished.emit(self)
