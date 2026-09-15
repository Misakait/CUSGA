## 战斗根节点的震屏与 Hit Stop 仲裁器。
## 所有高冲击反馈都必须经过该节点，避免多段和范围事件分别写 Engine.time_scale 后无法恢复。
class_name CombatScreenImpulse
extends Node

## 每条全局冲击开始播放时发出，供聚焦测试验证多段与范围请求没有被覆盖。
signal impulse_started(shake_pixels: float, hit_stop_seconds: float)

## 每条全局冲击完整结束并恢复时间缩放后发出。
signal impulse_finished()

## 需要被短暂移动的战斗根节点。
@export var battle_root_path: NodePath

## 当前战斗根节点的缓存引用。
var _battle_root: Node2D

## 战斗根节点进入场景时的基础位置，恢复时必须精确写回该值。
var _base_position: Vector2

## 当前运行中的震屏 Tween；同一时刻仅播放队首请求，后续请求不会取消它。
var _shake_tween: Tween

## 按接收顺序保存的全局冲击请求，确保多段和范围中的每次命中都不会被合并或丢弃。
var _impulse_queue: Array[Dictionary] = []

## 是否正在异步消费全局冲击队列，防止每次入队都启动重复消费者。
var _is_processing_impulses: bool = false

## Hit Stop 前的全局时间缩放，退出时必须恢复以免污染其它场景。
var _time_scale_before_hit_stop: float = 1.0

## 是否由本控制器持有全局时间缩放。
var _owns_time_scale: bool = false

## 初始化战斗根节点引用。
## @return void 无返回值。
func _ready() -> void:
	_battle_root = get_node_or_null(battle_root_path) as Node2D
	if _battle_root:
		_base_position = _battle_root.position
	else:
		push_warning("CombatScreenImpulse 缺少 Battle 根节点，已禁用震屏。")

## 将一次数值驱动的震屏与可选 Hit Stop 加入 FIFO；所有请求都会被完整消费。
## @param shake_pixels 本次命中已计算的震屏幅度。
## @param shake_duration 本次命中已计算的震屏收束时长。
## @param hit_stop_seconds 本次命中已计算的停顿时长；零代表减弱模式仅震屏。
## @param time_scale 停顿期间的目标时间缩放。
## @return void 无返回值。
func enqueue_impulse(shake_pixels: float, shake_duration: float, hit_stop_seconds: float, time_scale: float) -> void:
	# 每条请求独立保存，避免后续多段或范围命中覆盖正在播放的全局反馈。
	var impulse_request: Dictionary = {
		"shake_pixels": maxf(shake_pixels, 0.0),
		"shake_duration": maxf(shake_duration, 0.0),
		"hit_stop_seconds": maxf(hit_stop_seconds, 0.0),
		"time_scale": clampf(time_scale, 0.01, 1.0)
	}
	_impulse_queue.append(impulse_request)
	if not _is_processing_impulses:
		_is_processing_impulses = true
		_consume_impulse_queue()

## 保留旧调用入口，并将其转发到无节流 FIFO 以兼容现有动态调用方。
## @param shake_pixels 本次命中已计算的震屏幅度。
## @param shake_duration 本次命中已计算的震屏收束时长。
## @param hit_stop_seconds 本次命中已计算的停顿时长。
## @param time_scale 停顿期间的目标时间缩放。
## @return void 无返回值。
func request_impulse(shake_pixels: float, shake_duration: float, hit_stop_seconds: float, time_scale: float) -> void:
	enqueue_impulse(shake_pixels, shake_duration, hit_stop_seconds, time_scale)

## 依照入队顺序完整播放全局冲击，避免一个根节点与全局时间缩放同时被多个 Tween 争夺。
## @return void 无返回值。
func _consume_impulse_queue() -> void:
	while not _impulse_queue.is_empty():
		# 显式声明字典类型，避免 pop_front 的 Variant 返回值在警告即错误配置下失去类型信息。
		var impulse_request: Dictionary = _impulse_queue.pop_front()
		# 当前请求的震屏幅度由导演的数值曲线配方提供。
		var shake_pixels: float = float(impulse_request.get("shake_pixels", 0.0))
		# 当前请求的震屏时长由导演的数值曲线配方提供。
		var shake_duration: float = float(impulse_request.get("shake_duration", 0.0))
		# 当前请求的 Hit Stop 时长在减弱模式中为零，但请求本身仍完整保留。
		var hit_stop_seconds: float = float(impulse_request.get("hit_stop_seconds", 0.0))
		# 当前请求的时间缩放由 Profile 配置提供并已在入队时完成安全钳制。
		var requested_time_scale: float = float(impulse_request.get("time_scale", 1.0))
		impulse_started.emit(shake_pixels, hit_stop_seconds)
		_play_shake(shake_pixels, shake_duration)
		if hit_stop_seconds > 0.0:
			if not _owns_time_scale:
				_time_scale_before_hit_stop = Engine.time_scale
				_owns_time_scale = true
			Engine.time_scale = minf(Engine.time_scale, requested_time_scale)
		# 以较长持续时间作为队首的完整占用窗口，让震屏与 Hit Stop 同步开始且不被下一条覆盖。
		var request_window_seconds: float = maxf(shake_duration, hit_stop_seconds)
		if request_window_seconds > 0.0:
			await get_tree().create_timer(request_window_seconds, true, false, true).timeout
		if not is_inside_tree():
			return
		if _owns_time_scale:
			Engine.time_scale = _time_scale_before_hit_stop
			_owns_time_scale = false
		impulse_finished.emit()
	_is_processing_impulses = false

## 用固定的三段偏移产生冲击后快速归位；请求已串行，因此不会为了新命中取消前一段震屏。
## @param shake_pixels 当前震屏幅度。
## @param shake_duration 完整震屏时长。
## @return void 无返回值。
func _play_shake(shake_pixels: float, shake_duration: float) -> void:
	if not _battle_root or shake_pixels <= 0.0 or shake_duration <= 0.0:
		return
	_battle_root.position = _base_position
	_shake_tween = create_tween()
	_shake_tween.tween_property(_battle_root, "position", _base_position + Vector2(shake_pixels, -shake_pixels * 0.35), shake_duration * 0.30)
	_shake_tween.tween_property(_battle_root, "position", _base_position + Vector2(-shake_pixels * 0.55, shake_pixels * 0.20), shake_duration * 0.32)
	_shake_tween.tween_property(_battle_root, "position", _base_position, shake_duration * 0.38)

## 退出场景时无条件恢复根节点与时间缩放，防止战斗切场景后残留偏移或慢放。
## @return void 无返回值。
func _exit_tree() -> void:
	if _shake_tween and _shake_tween.is_valid() and _shake_tween.is_running():
		_shake_tween.kill()
	# 离开战斗时未播放的请求不应泄露到下一场战斗。
	_impulse_queue.clear()
	_is_processing_impulses = false
	if _battle_root:
		_battle_root.position = _base_position
	if _owns_time_scale:
		Engine.time_scale = _time_scale_before_hit_stop
		_owns_time_scale = false
