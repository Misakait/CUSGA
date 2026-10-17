extends Node2D
## 「所需交互范围」提示圈的表现组件。
##
## 职责边界：只负责「在给定世界坐标处画一个空心圈、按时长淡出、然后释放自己」。
## 组件不含任何交互业务、不读交互距离、也不依赖任何 autoload，
## 因此可被任意需要「显示一个范围」的系统复用。
##
## 圈心与半径都只在生成时写一次。宿主画布带着相机变换（follow_viewport_enabled），
## 相机移动由引擎负责，组件因此不需要 _process，也不需要做「世界 → 屏幕」换算。
##
## 生命周期与 FloatingTextLabel 对称：fire-and-forget，play() 播完自己 queue_free，
## 调用方不需要回收或登记。
##
## 为什么继承 Node2D 而不是 Control：
## 1. 圈不参与任何布局，Node2D 的 position 可以直接写入世界坐标，不需要像 Label 那样
##    先按内容收缩尺寸、再把中心点换算成左上角；
## 2. Node2D 天然不参与 GUI 命中测试，不存在「全屏宿主漏设 mouse_filter 会静默吞掉
##    其下方所有输入」那一类故障面；
## 3. CanvasItem.modulate 在 Node2D 上同样可用，淡出写法与飘字组件完全一致。
class_name InteractionRangeRing

## 淡出结束、节点释放前发出；与 FloatingTextLabel 的 finished 对称，供上层与测试确认动画真的走完。
signal finished

## 空心圆的折线段数。圈半径量级约 160 像素，64 段的折线误差已在半个像素以内；
## 再提高只会增加每帧三角面数，观感没有区别。
const SEGMENTS: int = 64

## 本次动画的 Tween；重复播放或节点离树时必须终止，否则旧动画会继续改写节点属性。
var _tween: Tween = null

## 圈的半径（世界单位，即所需交互距离）；由 play() 写入，_draw() 读取。
var _radius: float = 0.0

## 圈线颜色；由 play() 写入，_draw() 读取。
var _line_color: Color = Color.WHITE

## 圈线宽度（像素）；由 play() 写入，_draw() 读取。
var _line_width: float = 0.0


## 初始化节点行为：圈只做展示，必须与所依附的飘字一起在暂停时继续推进动画。
##
## @return void 无返回值。
func _ready() -> void:
	# 暂停时也必须继续推进动画。Tween 默认跟随宿主节点的处理状态，
	# 一旦跟随暂停，暂停期间生成的圈就会永久停在屏幕上，既不淡出也不释放。
	# 这一点与 FloatingTextLabel 完全相同，不能只给飘字设而漏掉圈。
	process_mode = Node.PROCESS_MODE_ALWAYS


## 在指定世界坐标处配置并启动一次提示圈；淡出结束后自动释放自身。
##
## @param center 圈心的世界坐标；与同批飘字取自同一个世界坐标，圈因此与文字同心。
## @param radius 圈的半径（世界单位，即所需交互距离）；宿主画布带相机变换，不需要换算成像素。
## @param line_color 圈线颜色。
## @param line_width 圈线宽度（像素）。
## @param duration 淡出总时长（秒）；必须与同批飘字相同，两者才会同步消失。
## @return void 无返回值。
func play(center: Vector2, radius: float, line_color: Color, line_width: float,
		duration: float) -> void:
	_stop_tween()

	position = center
	_radius = maxf(0.0, radius)
	_line_color = line_color
	_line_width = maxf(0.0, line_width)
	# 必须显式重绘：_draw() 只在节点进树时与 queue_redraw() 之后执行，
	# 而节点进树时 _radius 还是 0。漏掉这一行会得到一个永远画不出任何东西、
	# 却也不产生任何报错的空节点——本组件最容易踩的静默故障。
	queue_redraw()

	modulate = Color.WHITE
	_tween = create_tween()
	# 淡出曲线必须与飘字逐位一致（同一 DURATION + 同一 TRANS_SINE/EASE_IN）：
	# 只有两条 alpha 曲线相同，才谈得上「与字体同步出现和消失」。
	_tween.tween_property(self, "modulate:a", 0.0, duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_tween.finished.connect(_on_tween_finished, CONNECT_ONE_SHOT)


## 绘制空心圈。
##
## 用 draw_arc 而不是 draw_circle：draw_arc 只描边、不填充，因此天然就是空心圈；
## draw_circle 需要额外依赖 filled 参数才能得到同样效果，语义更绕。
##
## @return void 无返回值。
func _draw() -> void:
	if _radius <= 0.0:
		return
	draw_arc(Vector2.ZERO, _radius, 0.0, TAU, SEGMENTS, _line_color, _line_width, true)


## 中止当前动画；重复播放或节点退出场景树时调用。
##
## @return void 无返回值。
func _stop_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null


## 动画播完：广播结束并释放自身。
##
## @return void 无返回值。
func _on_tween_finished() -> void:
	# 先置空引用，避免 _exit_tree 再去 kill 一个已经结束的 Tween。
	_tween = null
	finished.emit()
	queue_free()


## 退出场景树时终止 Tween，避免动画继续驱动一个已经离树的节点。
##
## @return void 无返回值。
func _exit_tree() -> void:
	_stop_tween()
