## 战斗根节点的震屏与 Hit Stop 仲裁器。
## 所有高冲击反馈都必须经过该节点，避免多段和范围事件分别写 Engine.time_scale 后无法恢复。
class_name CombatScreenImpulse
extends Node

## 需要被短暂移动的战斗根节点。
@export var battle_root_path: NodePath

## 当前战斗根节点的缓存引用。
var _battle_root: Node2D

## 战斗根节点进入场景时的基础位置，恢复时必须精确写回该值。
var _base_position: Vector2

## 当前运行中的震屏 Tween。
var _shake_tween: Tween

## 命中停顿恢复令牌，后创建的高优先级请求会覆盖旧请求。
var _hit_stop_token: int = 0

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

## 为高优先级结果请求一次震屏和可选 Hit Stop。
## @param shake_pixels 当前表现强度下允许的震屏幅度。
## @param shake_duration 震屏收束所需时长。
## @param hit_stop_seconds 命中停顿时长；小于等于零时只播放震屏。
## @param time_scale 停顿期间的时间缩放。
## @return void 无返回值。
func request_impulse(shake_pixels: float, shake_duration: float, hit_stop_seconds: float, time_scale: float) -> void:
	_play_shake(shake_pixels, shake_duration)
	if hit_stop_seconds > 0.0:
		_request_hit_stop(hit_stop_seconds, time_scale)

## 用固定的三段偏移产生冲击后快速归位，避免随机抖动造成不可控的视觉噪声。
## @param shake_pixels 当前震屏幅度。
## @param shake_duration 完整震屏时长。
## @return void 无返回值。
func _play_shake(shake_pixels: float, shake_duration: float) -> void:
	if not _battle_root or shake_pixels <= 0.0:
		return
	if _shake_tween and _shake_tween.is_valid() and _shake_tween.is_running():
		_shake_tween.kill()
	_battle_root.position = _base_position
	_shake_tween = create_tween()
	_shake_tween.tween_property(_battle_root, "position", _base_position + Vector2(shake_pixels, -shake_pixels * 0.35), shake_duration * 0.30)
	_shake_tween.tween_property(_battle_root, "position", _base_position + Vector2(-shake_pixels * 0.55, shake_pixels * 0.20), shake_duration * 0.32)
	_shake_tween.tween_property(_battle_root, "position", _base_position, shake_duration * 0.38)

## 以忽略时间缩放的计时器恢复世界速度，保证慢放本身不会阻止自身结束。
## @param duration 停顿持续时长。
## @param requested_time_scale 停顿期间的目标时间缩放。
## @return void 无返回值。
func _request_hit_stop(duration: float, requested_time_scale: float) -> void:
	_hit_stop_token += 1
	var request_token: int = _hit_stop_token
	if not _owns_time_scale:
		_time_scale_before_hit_stop = Engine.time_scale
		_owns_time_scale = true
	Engine.time_scale = minf(Engine.time_scale, clampf(requested_time_scale, 0.01, 1.0))
	_restore_time_scale_after(duration, request_token)

## 等待最新请求结束后恢复进入停顿前的时间缩放。
## @param duration 停顿持续时长。
## @param request_token 本次请求对应的恢复令牌。
## @return void 无返回值。
func _restore_time_scale_after(duration: float, request_token: int) -> void:
	await get_tree().create_timer(duration, true, false, true).timeout
	if request_token != _hit_stop_token or not _owns_time_scale:
		return
	Engine.time_scale = _time_scale_before_hit_stop
	_owns_time_scale = false

## 退出场景时无条件恢复根节点与时间缩放，防止战斗切场景后残留偏移或慢放。
## @return void 无返回值。
func _exit_tree() -> void:
	if _shake_tween and _shake_tween.is_valid() and _shake_tween.is_running():
		_shake_tween.kill()
	if _battle_root:
		_battle_root.position = _base_position
	if _owns_time_scale:
		Engine.time_scale = _time_scale_before_hit_stop
		_owns_time_scale = false
