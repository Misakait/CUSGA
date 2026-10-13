extends Node
## 全局飘字服务（autoload 名 FloatingText）。
##
## 职责边界：持有承载层、把「交互目标 / 世界坐标」换算成屏幕坐标、抑制同帧重复提示，
## 并把样式参数交给 FloatingTextLabel 渲染。它不包含任何交互业务规则，也不判断该不该提示。
##
## 调用方只传「目标或坐标」与「文案」，不需要知道字体、描边、层级或 Tween 的任何细节；
## 因此交互目标（棋盘卡视图、建筑视图）不需要为实现提示而新增任何接口，实现零耦合。
##
## 刻意不声明 class_name：autoload 已经提供全局名 FloatingText，再声明同名 class_name 会冲突。

## 游戏字体：工程内唯一的字体资源，含 6769 个 CJK 表意文字，足以渲染中文提示。
const GAME_FONT: FontFile = preload("res://res/font/Uranus_Pixel_11Px.ttf")

## 表现组件脚本。用 preload 而不是 class_name，避免为一个纯表现组件引入新的全局类型。
const LABEL_SCRIPT: GDScript = preload("res://core/ui/feedback/floating_text_label.gd")

## 承载层号。必须高于 UI/HUDLayer(2)，否则飘字会被 HUD 面板遮住。
const CANVAS_LAYER: int = 10

## 默认正文色（红）：距离不足等失败提示的语义色。
const DEFAULT_TEXT_COLOR: Color = Color(1.0, 0.25, 0.2, 1.0)

## 字号。像素字体在小字号下笔画会粘连，28 是保证中文可读的下限。
const FONT_SIZE: int = 28

## 黑色描边宽度，用于在任意地形贴图上保证对比度。
const OUTLINE_SIZE: int = 6

## 描边颜色。
const OUTLINE_COLOR: Color = Color(0.0, 0.0, 0.0, 1.0)

## 向上飘升的像素距离。
const RISE_DISTANCE: float = 48.0

## 飘字总时长（秒）。
const DURATION: float = 0.9

## 去重窗口（秒）。必须覆盖 BoardCardView 在同一次左键里先后发出
## Pressed 与 Clicked 的间隔——两者同帧，间隔为 0。
const DEDUPE_SECONDS: float = 0.2

## 去重坐标容差（像素）。
const DEDUPE_RADIUS: float = 8.0

## 承载飘字的 CanvasLayer。
var _layer: CanvasLayer = null

## 全屏宿主；所有飘字都是它的子节点，子节点的 position 即屏幕坐标。
var _host: Control = null

## 近期已播放的提示，元素为 {text, position, expires_at}；仅用于抑制同帧重复提示。
var _recent: Array[Dictionary] = []


## 建立承载层与全屏宿主。autoload 只初始化一次，因此这里不做幂等分支。
##
## @return void 无返回值。
func _ready() -> void:
	_layer = CanvasLayer.new()
	_layer.name = "FloatingTextLayer"
	_layer.layer = CANVAS_LAYER
	add_child(_layer)

	_host = Control.new()
	_host.name = "FloatingTextHost"
	# Control 的 anchors 以父级 CanvasItem 的 anchorable_rect 为参考；父级是 CanvasLayer 时
	# 该矩形即视口，因此 PRESET_FULL_RECT 等于视口大小，并随视口缩放自动更新。
	_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# 必须忽略鼠标，否则全屏宿主会吞掉其下方的所有输入。
	_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_host)


## 在交互目标处显示飘字。
##
## 目标坐标由本服务自行读取，调用方不需要目标实现任何接口。
##
## @param target 交互目标（棋盘卡视图等）；已失效时回退到鼠标位置。
## @param text 显示文案。
## @param text_color 正文颜色，默认失败红。
## @return 新生成的飘字节点；被去重窗口拦掉时返回 null。
func show_at_target(target: CanvasItem, text: String,
		text_color: Color = DEFAULT_TEXT_COLOR) -> Node:
	return _spawn(text, _resolve_target_screen_position(target), text_color)


## 在世界坐标处显示飘字。
##
## 用于没有存活目标节点的场景，例如建筑已被拆除、建造落点校验失败。
##
## @param world_position 世界坐标。
## @param text 显示文案。
## @param text_color 正文颜色，默认失败红。
## @return 新生成的飘字节点；被去重窗口拦掉时返回 null。
func show_at_world(world_position: Vector2, text: String,
		text_color: Color = DEFAULT_TEXT_COLOR) -> Node:
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return null
	return _spawn(text, viewport.get_canvas_transform() * world_position, text_color)


## 立即清空所有仍在播放的飘字与去重记录；供场景切换与测试收尾使用。
##
## @return void 无返回值。
func clear_all() -> void:
	_recent.clear()
	if _host == null or not is_instance_valid(_host):
		return
	for child: Node in _host.get_children():
		child.queue_free()


## 把交互目标换算成屏幕坐标。
##
## 用 CanvasItem.get_screen_transform()，与 HUD 的 world_hold_progress_indicator 同一口径：
## 它已经包含相机变换与所在画布的偏移，因此调用方不需要关心目标挂在哪个画布上。
##
## @param target 交互目标。
## @return 屏幕坐标；目标已失效时返回鼠标位置。
func _resolve_target_screen_position(target: CanvasItem) -> Vector2:
	var viewport: Viewport = get_viewport()
	if target == null or not is_instance_valid(target):
		# 调用方可能持有刚被 queue_free 的卡牌（跨房卸载），此时不能访问它的变换。
		return viewport.get_mouse_position() if viewport != null else Vector2.ZERO
	if target is Control:
		# Control 的变换原点是左上角，取尺寸中心才是「目标处」。
		var control: Control = target
		return control.get_screen_transform() * (control.size * 0.5)
	# Node2D：BoardCardView 的根、Icon 与碰撞体都位于原点，因此原点即图标中心。
	return target.get_screen_transform().origin


## 生成一条飘字；命中去重窗口时直接返回 null。
##
## @param text 显示文案。
## @param screen_position 屏幕坐标锚点。
## @param text_color 正文颜色。
## @return 飘字节点；被去重或宿主缺失时返回 null。
func _spawn(text: String, screen_position: Vector2, text_color: Color) -> Node:
	if text.is_empty() or _host == null or not is_instance_valid(_host):
		return null
	if _is_duplicate(text, screen_position):
		return null

	# add_child 必须在 play 之前：play 里的 reset_size 需要节点已在场景树中才能拿到最终主题尺寸。
	var label: Control = LABEL_SCRIPT.new()
	_host.add_child(label)
	label.call("play", text, text_color, GAME_FONT, FONT_SIZE, OUTLINE_SIZE,
		OUTLINE_COLOR, screen_position, RISE_DISTANCE, DURATION)
	return label


## 判断同一文案是否刚在同一位置播过；顺带清理过期记录。
##
## @param text 显示文案。
## @param screen_position 屏幕坐标锚点。
## @return 处于去重窗口内且位置足够接近时为 true。
func _is_duplicate(text: String, screen_position: Vector2) -> bool:
	var now: int = Time.get_ticks_msec()
	var window_ms: int = int(DEDUPE_SECONDS * 1000.0)
	# 倒序遍历，便于在清理过期项时安全移除。
	for index: int in range(_recent.size() - 1, -1, -1):
		var entry: Dictionary = _recent[index]
		if int(entry.get("expires_at", 0)) <= now:
			_recent.remove_at(index)
			continue
		if String(entry.get("text", "")) != text:
			continue
		var recorded: Vector2 = entry.get("position", Vector2.ZERO)
		if recorded.distance_to(screen_position) <= DEDUPE_RADIUS:
			return true
	_recent.append({"text": text, "position": screen_position, "expires_at": now + window_ms})
	return false
