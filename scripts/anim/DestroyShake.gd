## 长按破坏期间的贴图抖动表现，并负责同步「不参与抖动」的进度锚点。
##
## 抖动作用在调用方指定的**整个可见节点**上：地形卡传卡牌视觉根节点，于是卡框、
## 卡名与卡内物品图标一起抖；建筑传建筑图标，而建筑的可见部分本来就只有那个图标。
##
## 为什么抖 position 而不是 offset：`Sprite2D.get_rect()` 会把 `offset` 计入矩形，
## 而进度圆环锚点正是用 `get_rect().end` 取点的，抖 offset 会连带把圆环一起拖走。
## 抖 position 时圆环改用独立锚点（见 SyncAnchor），两条路径都保证圆环静止。
class_name DestroyShake
extends RefCounted

## 动作参数缺失时的兜底抖动幅度，单位为被抖节点父节点空间的像素。
const DEFAULT_AMPLITUDE: float = 3.0
## 动作参数缺失时的兜底步进间隔，单位为真实秒。
const DEFAULT_STEP_SECONDS: float = 0.045
## 步进间隔下限：更小的值只会让同一帧内反复重设偏移，观感与性能都没有收益。
const MIN_STEP_SECONDS: float = 0.01

## 被抖动的可见节点；抖动只改它的本地 position，不碰旋转、缩放与碰撞。
var _target: Node2D
## 随机偏移半径，单位为 _target 父节点空间的像素。
var _amplitude: float
## 两次随机偏移之间的等待时间，单位为真实秒。
var _step_seconds: float
## _target 的静止位置；只在首次 Start 时采样一次，之后始终作为复位目标。
var _rest_position: Vector2
## 是否已经采样过静止位置；未采样时 Stop 不得写 position，否则会覆盖场景里作者设置的坐标。
var _rest_captured: bool = false
## 当前驱动抖动的循环 Tween。
var _tween: Tween


## 构造抖动表现。
##
## 参数 target：被抖动的可见节点，为空时全部方法安全空转。
## 参数 amplitude：随机偏移半径，单位为 target 父节点空间的像素。
## 参数 step_seconds：两次随机偏移之间的等待时间，单位为真实秒。
func _init(
	target: Node2D,
	amplitude: float = DEFAULT_AMPLITUDE,
	step_seconds: float = DEFAULT_STEP_SECONDS
) -> void:
	_target = target
	_amplitude = maxf(amplitude, 0.0)
	_step_seconds = maxf(step_seconds, MIN_STEP_SECONDS)


## 开始抖动；已在抖动时直接返回，重复调用幂等。
##
## 静止位置只在首次调用时采样，因此中途被打断后再 Start 也不会把偏移位置误当静止位置。
##
## 返回值：无。
func Start() -> void:
	if _target == null or not is_instance_valid(_target) or not _target.is_inside_tree():
		return
	if IsRunning():
		return

	if not _rest_captured:
		_rest_position = _target.position
		_rest_captured = true

	# 用 Tween 而不是 _process：停止时一次 kill 就能丢掉全部待执行步骤，
	# 不会留下「本帧还要再抖一下」的尾帧。
	_tween = _target.create_tween()
	_tween.set_loops()
	# 先立刻换一次偏移再等待，避免第一次抖动被延迟一个步进间隔才出现。
	_tween.tween_callback(_apply_random_offset)
	_tween.tween_interval(_step_seconds)


## 停止抖动并把目标复位到静止位置；未在抖动时同样保证复位，重复调用幂等。
##
## 返回值：无。
func Stop() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null

	# 复位必须无条件执行：即使 Tween 被场景树变化提前作废，也不能把目标留在偏移位置。
	if _rest_captured and _target != null and is_instance_valid(_target):
		_target.position = _rest_position


## 当前是否正在抖动。
##
## 返回值：Tween 有效时为 true；节点离开场景树或被 kill 后为 false。
func IsRunning() -> bool:
	return _tween != null and _tween.is_valid()


## 把进度锚点写到图标静止状态下的右下角，使圆环位置与卡牌抖动解耦。
##
## 复刻的是指示器对 Sprite2D 目标的取点公式 `get_screen_transform() * get_rect().end`，
## 因此锚点的屏幕位置与「直接锚定图标」完全一致。锚点必须在被抖节点的子树之外，
## 且允许与被抖节点、与图标处于不同的父节点下。
##
## 取点一律按**静止状态**换算：抖动期间调用（例如长按中刷新视图）会先扣掉当前抖动
## 偏移，否则会把这一帧的偏移烘进锚点，圆环跟着抖一下。
##
## 参数 icon：取点用的图标节点。
## 参数 anchor：不参与抖动的进度锚点节点。
## 返回值：无。
func SyncAnchor(icon: Sprite2D, anchor: Node2D) -> void:
	if _target == null or not is_instance_valid(_target):
		return
	if icon == null or not is_instance_valid(icon) or not icon.is_inside_tree():
		return
	if anchor == null or not is_instance_valid(anchor) or not anchor.is_inside_tree():
		return
	var anchor_parent: Node2D = anchor.get_parent() as Node2D
	if anchor_parent == null:
		return

	var point: Vector2 = icon.get_global_transform() * icon.get_rect().end
	# 抖动只平移 _target，它的整棵子树（含 icon）随之整体平移；
	# 把这段平移扣掉，等价于「假设 _target 还在静止位置」时取点。
	var rest: Vector2 = _rest_position if _rest_captured else _target.position
	var shift: Vector2 = _target.position - rest
	if shift != Vector2.ZERO:
		var shaken_parent: Node2D = _target.get_parent() as Node2D
		if shaken_parent != null:
			point -= shaken_parent.get_global_transform().basis_xform(shift)

	anchor.position = anchor_parent.to_local(point)


## 换一个随机偏移；半径按 sqrt 采样，避免方形分布让对角线方向抖得更远。
##
## 返回值：无。
func _apply_random_offset() -> void:
	if _target == null or not is_instance_valid(_target):
		return
	var angle: float = randf() * TAU
	var radius: float = _amplitude * sqrt(randf())
	_target.position = _rest_position + Vector2(cos(angle), sin(angle)) * radius
