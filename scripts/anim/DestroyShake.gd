## 长按破坏期间的贴图抖动表现，并负责同步「不参与抖动」的进度锚点。
##
## 为什么抖 position 而不是 offset：`Sprite2D.get_rect()` 会把 `offset` 计入矩形，
## 而进度圆环锚点正是用 `get_rect().end` 取点的，抖 offset 会连带把圆环一起拖走。
## 抖 position 时圆环改用独立锚点（见 SyncAnchor），两条路径都保证圆环静止。
class_name DestroyShake
extends RefCounted

## 动作参数缺失时的兜底抖动幅度，单位为贴图节点本地像素。
const DEFAULT_AMPLITUDE: float = 3.0
## 动作参数缺失时的兜底步进间隔，单位为真实秒。
const DEFAULT_STEP_SECONDS: float = 0.045
## 步进间隔下限：更小的值只会让同一帧内反复重设偏移，观感与性能都没有收益。
const MIN_STEP_SECONDS: float = 0.01

## 被抖动的贴图节点。
var _sprite: Sprite2D
## 随机偏移半径，单位为 _sprite 的父节点空间像素。
var _amplitude: float
## 两次随机偏移之间的等待时间，单位为真实秒。
var _step_seconds: float
## _sprite 的静止位置；只在首次 Start 时采样一次，之后始终作为复位目标。
var _rest_position: Vector2
## 是否已经采样过静止位置；未采样时 Stop 不得写 position，否则会覆盖场景里作者设置的坐标。
var _rest_captured: bool = false
## 当前驱动抖动的循环 Tween。
var _tween: Tween


## 构造抖动表现。
##
## 参数 sprite：被抖动的贴图节点，为空时全部方法安全空转。
## 参数 amplitude：随机偏移半径，单位为 sprite 父节点空间像素。
## 参数 step_seconds：两次随机偏移之间的等待时间，单位为真实秒。
func _init(
	sprite: Sprite2D,
	amplitude: float = DEFAULT_AMPLITUDE,
	step_seconds: float = DEFAULT_STEP_SECONDS
) -> void:
	_sprite = sprite
	_amplitude = maxf(amplitude, 0.0)
	_step_seconds = maxf(step_seconds, MIN_STEP_SECONDS)


## 开始抖动；已在抖动时直接返回，重复调用幂等。
##
## 静止位置只在首次调用时采样，因此中途被打断后再 Start 也不会把偏移位置误当静止位置。
##
## 返回值：无。
func Start() -> void:
	if _sprite == null or not is_instance_valid(_sprite) or not _sprite.is_inside_tree():
		return
	if IsRunning():
		return

	if not _rest_captured:
		_rest_position = _sprite.position
		_rest_captured = true

	# 用 Tween 而不是 _process：停止时一次 kill 就能丢掉全部待执行步骤，
	# 不会留下「本帧还要再抖一下」的尾帧。
	_tween = _sprite.create_tween()
	_tween.set_loops()
	# 先立刻换一次偏移再等待，避免第一次抖动被延迟一个步进间隔才出现。
	_tween.tween_callback(_apply_random_offset)
	_tween.tween_interval(_step_seconds)


## 停止抖动并把贴图节点复位到静止位置；未在抖动时同样保证复位，重复调用幂等。
##
## 返回值：无。
func Stop() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null

	# 复位必须无条件执行：即使 Tween 被场景树变化提前作废，也不能把贴图留在偏移位置。
	if _rest_captured and _sprite != null and is_instance_valid(_sprite):
		_sprite.position = _rest_position


## 当前是否正在抖动。
##
## 返回值：Tween 有效时为 true；节点离开场景树或被 kill 后为 false。
func IsRunning() -> bool:
	return _tween != null and _tween.is_valid()


## 把进度锚点写到图标静止状态下的右下角，使圆环位置与图标抖动解耦。
##
## 复刻的是指示器对 Sprite2D 目标的取点公式 `get_screen_transform() * get_rect().end`，
## 因此锚点的屏幕位置与「直接锚定图标」完全一致，但不会随 `Icon.position` 变化。
##
## 前置条件：anchor 与 icon 必须是同一个父节点的子节点，且 icon 不带旋转
## （本项目的两张破坏目标视图都满足）。
##
## 参数 icon：被抖动的图标节点。
## 参数 anchor：不参与抖动的进度锚点节点。
## 返回值：无。
static func SyncAnchor(icon: Sprite2D, anchor: Node2D) -> void:
	if icon == null or not is_instance_valid(icon) or anchor == null or not is_instance_valid(anchor):
		return
	anchor.position = icon.position + icon.scale * icon.get_rect().end


## 换一个随机偏移；半径按 sqrt 采样，避免方形分布让对角线方向抖得更远。
##
## 返回值：无。
func _apply_random_offset() -> void:
	if _sprite == null or not is_instance_valid(_sprite):
		return
	var angle: float = randf() * TAU
	var radius: float = _amplitude * sqrt(randf())
	_sprite.position = _rest_position + Vector2(cos(angle), sin(angle)) * radius
