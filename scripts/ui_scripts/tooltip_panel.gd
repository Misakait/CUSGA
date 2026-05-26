extends PanelContainer
class_name TooltipPanel

# ==========================================
# 悬停提示框组件 (Tooltip Panel)
# ==========================================
# 负责在鼠标悬停在特定物体上时显示详细文本。
# 加入了延迟显示逻辑，并强制设置了鼠标穿透以防止闪烁。
# 修复了 RichTextLabel 首次加载长文本时布局被拉伸的 Bug（使用 request_id 追踪与帧延迟）。
# ==========================================

@export_category("UI节点绑定")
## 提示框标题节点（如卡牌名称或怪物名称）
@export var title_label: Label
## 提示框描述节点（如卡牌效果描述或怪物属性）
@export var description_label: RichTextLabel

@export_category("位置与动画参数")
## 提示框相对于鼠标的偏移量
@export var mouse_offset: Vector2 = Vector2(15, 15)
## 显示/隐藏的渐变动画过渡时间（秒）
@export var fade_duration: float = 0.15
## 鼠标悬停多长时间后才显示提示框（秒）
@export var hover_delay: float = 0.8

# ==========================================
# 内部状态变量
# ==========================================
var _is_visible: bool = false
var _screen_size: Vector2

var _pending_show: bool = false
var _hover_time: float = 0.0
var _target_title: String = ""
var _target_desc: String = ""

var _current_tween: Tween
var _request_id: int = 0

func _ready() -> void:
	# 强制设置鼠标穿透，防止提示框挡住鼠标导致目标触发 mouse_exited 引起闪烁
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# 初始化时隐藏，并设置透明度为0
	modulate.a = 0.0
	hide()

	# 确保提示框置于最顶层，不受父级变换影响
	top_level = true
	z_index = 100

	# 获取屏幕尺寸用于边界检测
	_screen_size = get_viewport_rect().size
	get_viewport().size_changed.connect(_on_viewport_size_changed)

func _process(delta: float) -> void:
	# 处理延迟显示逻辑
	if _pending_show:
		_hover_time += delta
		if _hover_time >= hover_delay:
			_pending_show = false
			_actually_show_tooltip()

	# 仅在显示状态下实时跟随鼠标
	if _is_visible:
		_update_position()

## 对外接口：请求显示提示框（进入延迟等待）
## @param title_text: 标题内容
## @param desc_text: 描述内容
func show_tooltip(title_text: String, desc_text: String) -> void:
	# 每次请求都自增 ID，确保异步延迟期间能认出是否还是这次请求
	_request_id += 1

	# 记录目标文本，开始计时
	_target_title = title_text
	_target_desc = desc_text
	_hover_time = 0.0
	_pending_show = true

	# 如果当前已经显示了，且内容不同，则直接刷新内容而不等待，保持连续浏览的顺畅感
	if _is_visible:
		_pending_show = false
		_actually_show_tooltip()

func show_tooltip_now(title_text: String, desc_text: String) -> void:
	# 每次请求都自增 ID，确保异步延迟期间能认出是否还是这次请求
	_request_id += 1

	_target_title = title_text
	_target_desc = desc_text
	_pending_show = false
	_actually_show_tooltip()

## 内部逻辑：时间到达后真正执行显示
func _actually_show_tooltip() -> void:
	var current_request: int = _request_id

	if title_label:
		title_label.text = _target_title
	if description_label:
		if _target_desc.length() > 18:
			description_label.text = "[fill]" + _target_desc + "[/fill]"
		else:
			description_label.text = _target_desc

	# 必须先调用 show() 并且保持透明，让 Godot 的 UI 排版引擎开始工作
	modulate.a = 0.0
	show()

	# 为了解决 RichTextLabel 首次填入长文本时高度计算不准确导致布局异常拉伸的 Bug
	# 我们必须让引擎先在后台走两帧的排版计算 (layout process)
	await get_tree().process_frame
	await get_tree().process_frame

	# 在等待的这几帧中，如果玩家移开了鼠标，或者悬停到了另一张牌上，request_id 就会改变
	if _request_id != current_request:
		return

	_is_visible = true

	# 强制更新一次布局，以便即时获取正确的尺寸用于接下来的边界限制
	reset_size()
	_update_position()

	# 如果有正在播放的动画，先终止它
	if _current_tween and _current_tween.is_valid():
		_current_tween.kill()

	# 渐现动画
	_current_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_current_tween.tween_property(self, "modulate:a", 1.0, fade_duration)

## 对外接口：隐藏提示框（并取消任何正在等待的显示）
func hide_tooltip() -> void:
	# 取消挂起的显示，同时自增 ID 以废弃之前可能正在 await 的显示请求
	_request_id += 1
	_pending_show = false
	_hover_time = 0.0

	if not _is_visible:
		return

	_is_visible = false

	if _current_tween and _current_tween.is_valid():
		_current_tween.kill()

	_current_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_current_tween.tween_property(self, "modulate:a", 0.0, fade_duration)
	_current_tween.tween_callback(hide)

## 内部逻辑：根据鼠标位置更新提示框坐标，并防止超出屏幕边界
func _update_position() -> void:
	# 获取鼠标在屏幕上的坐标
	var mouse_pos = get_viewport().get_mouse_position()
	var target_pos = mouse_pos + mouse_offset

	# 获取当前提示框的实际渲染宽高
	var panel_size = size

	# 屏幕右侧边界检测：如果超出了右侧，则将提示框翻转到鼠标左侧
	if target_pos.x + panel_size.x > _screen_size.x:
		target_pos.x = mouse_pos.x - panel_size.x - mouse_offset.x

	# 屏幕下侧边界检测：如果超出了下侧，则将提示框翻转到鼠标上方
	if target_pos.y + panel_size.y > _screen_size.y:
		target_pos.y = mouse_pos.y - panel_size.y - mouse_offset.y

	# 屏幕左侧与上侧的极限保护（兜底）
	target_pos.x = max(0, target_pos.x)
	target_pos.y = max(0, target_pos.y)

	# 赋值坐标
	global_position = target_pos

## 当窗口大小改变时刷新缓存的屏幕尺寸
func _on_viewport_size_changed() -> void:
	_screen_size = get_viewport_rect().size
