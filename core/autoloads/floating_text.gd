extends Node
## 全局飘字服务（autoload 名 FloatingText）。
##
## 职责边界：持有承载层、读取「交互目标 / 世界坐标」的世界坐标、抑制同帧重复提示，
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

## 「所需交互范围」提示圈的表现组件脚本。
##
## 圈是飘字的**附加**组件：调用方给出世界半径后，圈与飘字在同一次调用里一起产生、
## 一起淡出、一起释放，因此画面上不可能只出现其中一个。
const RING_SCRIPT: GDScript = preload("res://core/ui/feedback/interaction_range_ring.gd")

## 承载层号。必须高于 UI/HUDLayer(2) 与昼夜滤镜层(0)，否则飘字会被 HUD 面板遮住、或被滤镜染色。
##
## 保留 CanvasLayer（而不是把飘字挂进世界画布的某个节点下）正是为了这个层级：
## 配合 _ready() 里的 follow_viewport_enabled，本层同时具备「世界坐标定位」与「独立层级」，
## 不必在「贴住目标」和「不被 HUD 盖住」之间二选一。
const CANVAS_LAYER: int = 10

## 默认正文色（红）：距离不足等失败提示的语义色。
const DEFAULT_TEXT_COLOR: Color = Color(1.0, 0.25, 0.2, 1.0)

## 字号。像素字体在小字号下笔画会粘连，28 是保证中文可读的下限。
const FONT_SIZE: int = 28

## 黑色描边宽度，用于在任意地形贴图上保证对比度。
const OUTLINE_SIZE: int = 6

## 描边颜色。
const OUTLINE_COLOR: Color = Color(0.0, 0.0, 0.0, 1.0)

## 「所需交互范围」提示圈的颜色：灰色半透明。
##
## 取半透明而不是不透明，是因为圈要一直盖在各类地形贴图上：太实会抢走飘字的注意力，
## 太淡又会在亮色地面上看不见，0.5 是这个取舍下的取值。
const RANGE_RING_COLOR: Color = Color(0.62, 0.62, 0.66, 0.5)

## 「所需交互范围」提示圈的线宽（像素）。
const RANGE_RING_WIDTH: float = 3.0

## 向上飘升的像素距离。
const RISE_DISTANCE: float = 48.0

## 飘字总时长（秒）。
const DURATION: float = 0.9

## 去重窗口（秒）。必须覆盖 BoardCardView 在同一次左键里先后发出
## Pressed 与 Clicked 的间隔——两者同帧，间隔为 0。
const DEDUPE_SECONDS: float = 0.2

## 去重坐标容差（世界单位）。与飘字坐标同一坐标系，因此不需要任何换算。
const DEDUPE_RADIUS: float = 8.0

## 承载飘字的 CanvasLayer。
var _layer: CanvasLayer = null

## 飘字宿主；所有飘字都是它的子节点，子节点的 position 即**世界坐标**。
var _host: Control = null

## 近期已播放的提示，元素为 {text, position, expires_at}；仅用于抑制同帧重复提示。
var _recent: Array[Dictionary] = []


## 建立承载层与宿主。autoload 只初始化一次，因此这里不做幂等分支。
##
## @return void 无返回值。
func _ready() -> void:
	_layer = CanvasLayer.new()
	_layer.name = "FloatingTextLayer"
	_layer.layer = CANVAS_LAYER
	# 关键：让这一层跟随视口的相机变换，子节点的 position 于是直接就是世界坐标。
	# 不开这一项时本层是屏幕空间，飘字就必须每帧自己把世界坐标换算成屏幕坐标，
	# 否则相机一移动（跟随玩家的 Camera2D）圈与字就会从目标身上滑走；
	# 开着它既能「只写一次坐标」，又保住了本层的绘制顺序（在 HUD 与昼夜滤镜之上）。
	_layer.follow_viewport_enabled = true
	add_child(_layer)

	_host = Control.new()
	_host.name = "FloatingTextHost"
	# 宿主只作为定位父级，不参与布局：子节点的 position 相对它即为世界坐标。
	# 刻意不用 PRESET_FULL_RECT——anchors 以父级 CanvasItem 的 anchorable_rect 为参考，
	# 而跟随相机变换后该矩形不再固定在屏幕上，反而会把子节点整体平移。
	_host.position = Vector2.ZERO
	# 必须忽略鼠标，否则宿主会吞掉其下方的所有输入。
	_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_host)


## 在交互目标处显示飘字。
##
## 目标坐标由本服务自行读取，调用方不需要目标实现任何接口。坐标是世界坐标，
## 只在生成时取一次，之后相机怎么移动都不用再管。
##
## @param target 交互目标（棋盘卡视图等）；已失效时回退到鼠标位置。
## @param text 显示文案。
## @param text_color 正文颜色，默认失败红。
## @param world_radius 所需交互范围的世界半径；大于 0 时在目标处叠加同心的提示圈，0 表示只飘字。
## @return 新生成的飘字节点；被去重窗口拦掉时返回 null。
func show_at_target(target: CanvasItem, text: String,
		text_color: Color = DEFAULT_TEXT_COLOR, world_radius: float = 0.0) -> Node:
	return _spawn(text, _resolve_target_world_position(target), text_color, world_radius)


## 在世界坐标处显示飘字。
##
## 用于没有存活目标节点的场景，例如建筑已被拆除、建造落点校验失败。
## 坐标原样使用，不做任何换算。
##
## @param world_position 世界坐标。
## @param text 显示文案。
## @param text_color 正文颜色，默认失败红。
## @param world_radius 所需交互范围的世界半径；大于 0 时在该世界坐标处叠加同心的提示圈。
## @return 新生成的飘字节点；被去重窗口拦掉时返回 null。
func show_at_world(world_position: Vector2, text: String,
		text_color: Color = DEFAULT_TEXT_COLOR, world_radius: float = 0.0) -> Node:
	if get_viewport() == null:
		return null
	return _spawn(text, world_position, text_color, world_radius)


## 取交互目标的世界坐标。
##
## 只在生成时调用一次。宿主画布带着相机变换，坐标写一次就够，
## 因此这里刻意不提供「可反复求值」的形态，也不需要每帧重算。
##
## @param target 交互目标。
## @return 世界坐标；目标已失效时返回鼠标位置换算出的世界坐标。
func _resolve_target_world_position(target: CanvasItem) -> Vector2:
	var viewport: Viewport = get_viewport()
	if target == null or not is_instance_valid(target):
		# 调用方可能持有刚被 queue_free 的卡牌（跨房卸载），此时不能访问它的变换，
		# 回退到鼠标位置。鼠标是屏幕坐标，必须换算成世界坐标才写得进这一层。
		if viewport == null:
			return Vector2.ZERO
		return viewport.get_canvas_transform().affine_inverse() * viewport.get_mouse_position()
	if target is Control:
		# Control 的变换原点是左上角，取尺寸中心才是「目标处」。
		var control: Control = target
		return control.get_global_transform() * (control.size * 0.5)
	# Node2D：BoardCardView 的根、Icon 与碰撞体都位于原点，因此原点即图标中心。
	return target.get_global_transform().origin


## 立即清空所有仍在播放的飘字（含随字出现的提示圈）与去重记录；供场景切换与测试收尾使用。
##
## @return void 无返回值。
func clear_all() -> void:
	_recent.clear()
	if _host == null or not is_instance_valid(_host):
		return
	for child: Node in _host.get_children():
		child.queue_free()


## 生成一条飘字，以及可选的「所需交互范围」提示圈；命中去重窗口时直接返回 null。
##
## 圈与字必须在同一个函数体内生成：_is_duplicate 是本服务唯一的去重门禁，
## 把画圈拆成第二次调用会让同帧双发（BoardCardView 的 Pressed + Clicked）叠出两个圈，
## 也会失去「要么都有、要么都没有」的结构性保证。
## 两者还共用同一个世界坐标，因此不可能落到不同的位置上。
##
## @param text 显示文案。
## @param world_position 目标的世界坐标；圈与字共用，写一次即可，不需要每帧重算。
## @param text_color 正文颜色。
## @param world_radius 提示圈的世界半径；小于等于 0 时不生成圈。
## @return 飘字节点；被去重或宿主缺失时返回 null。
func _spawn(text: String, world_position: Vector2, text_color: Color,
		world_radius: float = 0.0) -> Node:
	if text.is_empty() or _host == null or not is_instance_valid(_host):
		return null
	if _is_duplicate(text, world_position):
		return null

	# 先建圈再建字：同一宿主下按子节点顺序绘制，圈因此画在文字之下，不会压住「距离不够！」。
	# 圈刻意不做上飘 Tween —— 它必须始终以目标为中心，否则「所需范围」的语义会随动画漂移。
	if world_radius > 0.0:
		var ring: Node2D = RING_SCRIPT.new()
		_host.add_child(ring)
		# 半径直接就是世界半径，不需要换算成像素：这一层已经带相机变换。
		# 圈与字用同一个 DURATION 且内部用同一条缓动曲线，两条 alpha 曲线逐帧相同，因此同步消失。
		ring.call("play", world_position, world_radius, RANGE_RING_COLOR,
			RANGE_RING_WIDTH, DURATION)

	# add_child 必须在 play 之前：play 里的 reset_size 需要节点已在场景树中才能拿到最终主题尺寸。
	var label: Control = LABEL_SCRIPT.new()
	_host.add_child(label)
	label.call("play", text, text_color, GAME_FONT, FONT_SIZE, OUTLINE_SIZE,
		OUTLINE_COLOR, world_position, RISE_DISTANCE, DURATION)
	return label


## 判断同一文案是否刚在同一位置播过；顺带清理过期记录。
##
## @param text 显示文案。
## @param world_position 目标的世界坐标。
## @return 处于去重窗口内且位置足够接近时为 true。
func _is_duplicate(text: String, world_position: Vector2) -> bool:
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
		if recorded.distance_to(world_position) <= DEDUPE_RADIUS:
			return true
	_recent.append({"text": text, "position": world_position, "expires_at": now + window_ms})
	return false
