extends Label
## 单条飘字的表现组件。
##
## 职责边界：只负责「怎么画、怎么动、何时释放」。字体、描边、颜色与时长全部由调用方传入，
## 组件自身不持有业务规则、不做坐标换算、也不依赖任何 autoload，因此可被任意系统复用。
##
## 生命周期是 fire-and-forget：play() 播放结束后自己 queue_free，调用方不需要回收或登记。
class_name FloatingTextLabel

## 播放结束、节点释放前发出；供上层与测试确认动画真的走完。
signal finished

## 本次动画的 Tween；重复播放或节点离树时必须终止，否则旧动画会继续改写节点属性。
var _tween: Tween = null


## 初始化控件行为：飘字只做展示，必须完全忽略鼠标。
##
## 漏掉 mouse_filter 会让飘字吞掉其下方的所有输入，而且不会有任何报错，属于静默故障。
##
## @return void 无返回值。
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# 暂停时也必须继续推进动画。Tween 默认跟随宿主节点的处理状态，
	# 一旦跟随暂停，暂停期间生成的飘字就会永久停在屏幕上，既不淡出也不释放。
	process_mode = Node.PROCESS_MODE_ALWAYS


## 在指定屏幕锚点配置并启动一次飘字；播放结束后自动释放自身。
##
## @param text 显示文案。
## @param text_color 正文颜色。
## @param font 渲染字体；由调用方传入游戏字体，组件刻意不自带默认值，避免出现第二处字体来源。
## @param font_size 字号（像素）。
## @param outline_size 描边宽度（像素）。
## @param outline_color 描边颜色。
## @param anchor_position 屏幕坐标锚点；文字以该点为中心展开。
## @param rise_distance 向上飘升的像素距离。
## @param duration 动画总时长（秒）。
## @return void 无返回值。
func play(text: String, text_color: Color, font: Font, font_size: int,
		outline_size: int, outline_color: Color,
		anchor_position: Vector2, rise_distance: float, duration: float) -> void:
	_stop_tween()

	self.text = text
	# 必须用 theme override 而不是 LabelSettings：一旦设置了 label_settings，
	# font_color 等 theme_override 会被整体忽略，调用方传入的颜色就会失效，
	# 表现为所有正在飞的飘字一起变色。
	add_theme_font_override("font", font)
	add_theme_font_size_override("font_size", font_size)
	add_theme_color_override("font_color", text_color)
	add_theme_constant_override("outline_size", outline_size)
	add_theme_color_override("font_outline_color", outline_color)

	# 先按当前字体收缩到文字实际尺寸，再把锚点换算成左上角，
	# 使飘字以交互目标为中心展开，而不是从目标处向右下溢出。
	reset_size()
	position = anchor_position - size * 0.5
	modulate = Color.WHITE

	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(self, "position:y", position.y - rise_distance, duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "modulate:a", 0.0, duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_tween.finished.connect(_on_tween_finished, CONNECT_ONE_SHOT)


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
