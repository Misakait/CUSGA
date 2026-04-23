## CardAnimator.gd
## 卡牌动画器组件 —— 挂载为子节点，父节点即可调用动画方法。
## 本组件完全可选，父节点不挂也不影响游戏运行。
##
## 用法：
##   1. 添加为卡牌的子节点
##   2. Inspector 中指定 card_sprite（必须）和 card_root（可选，默认父节点）
##   3. 父节点中：
##      @onready var animator = $CardAnimator if has_node("CardAnimator") else null
##      if animator: await animator.play_death()
class_name CardAnimator
extends Node


# ──────────────────────────────────────────────
# @export 关联节点
# ──────────────────────────────────────────────

## 卡牌主 Sprite2D，闪白/闪红效果目标。
@export var card_sprite: Sprite2D

## 卡牌根节点，缩放/位移/淡出目标。不填则自动取父节点。
@export var card_root: Node2D


# ──────────────────────────────────────────────
# 内部状态
# ──────────────────────────────────────────────

var _origin_y: float = 0.0          ## 悬停前的 Y 坐标
var _dying: bool = false            ## 死亡锁
var _idle_tween: Tween = null       ## 待机动画引用，用于停止


func _ready() -> void:
	if card_root == null and get_parent() is Node2D:
		card_root = get_parent() as Node2D
	if card_root != null:
		_origin_y = card_root.position.y


# ══════════════════════════════════════════════
#  原子动画（直接透传 CardAnimations 静态方法）
# ══════════════════════════════════════════════

## 淡入。
func fade_in(duration: float = CardAnimations.NORMAL) -> Tween:
	if card_root == null: return null
	return CardAnimations.fade_in(card_root, duration)

## 淡出。
func fade_out(duration: float = CardAnimations.NORMAL) -> Tween:
	if card_root == null: return null
	return CardAnimations.fade_out(card_root, duration)

## 缩放到指定值。
func scale_to(target: Vector2, duration: float = CardAnimations.NORMAL) -> Tween:
	if card_root == null: return null
	return CardAnimations.scale_to(card_root, target, duration)

## 弹入缩放。
func scale_bounce(from: Vector2, to: Vector2, duration: float = CardAnimations.NORMAL) -> Tween:
	if card_root == null: return null
	return CardAnimations.scale_bounce(card_root, from, to, duration)

## 缩放至零。
func scale_to_zero(duration: float = CardAnimations.SLOW) -> Tween:
	if card_root == null: return null
	return CardAnimations.scale_to_zero(card_root, duration)

## 飞向全局坐标。
func fly_to(target: Vector2, duration: float = CardAnimations.NORMAL) -> Tween:
	if card_root == null: return null
	return CardAnimations.fly_to(card_root, target, duration)

## 水平抖动。
func shake_x(amplitude: float = 10.0, duration: float = 0.28) -> Tween:
	if card_root == null: return null
	return CardAnimations.shake_x(card_root, amplitude, duration)

## 竖直抖动。
func shake_y(amplitude: float = 10.0, duration: float = 0.28) -> Tween:
	if card_root == null: return null
	return CardAnimations.shake_y(card_root, amplitude, duration)

## 闪白（需要 card_sprite）。
func flash_white(duration: float = 0.10) -> Tween:
	if card_sprite == null: return null
	return CardAnimations.flash_white(card_sprite, duration)

## 闪红（需要 card_sprite）。
func flash_red(duration: float = 0.10) -> Tween:
	if card_sprite == null: return null
	return CardAnimations.flash_red(card_sprite, duration)

## 闪指定颜色（需要 card_sprite）。
func flash_color(color: Color, duration: float = 0.10) -> Tween:
	if card_sprite == null: return null
	return CardAnimations.flash_color(card_sprite, color, duration)

## 旋转到指定角度。
func rotate_to(angle: float, duration: float = CardAnimations.NORMAL) -> Tween:
	if card_root == null: return null
	return CardAnimations.rotate_to(card_root, angle, duration)

## 旋转回零。
func rotate_reset(duration: float = CardAnimations.NORMAL) -> Tween:
	if card_root == null: return null
	return CardAnimations.rotate_reset(card_root, duration)

## 左右摇摆（循环，需手动 stop_wobble 停止）。
func wobble(angle: float = 0.05, duration: float = 0.4) -> Tween:
	if card_root == null: return null
	return CardAnimations.wobble(card_root, angle, duration)

## 停止摇摆。
func stop_wobble() -> void:
	if card_root != null:
		card_root.rotation = 0.0

## 重置节点状态。
func reset() -> void:
	if card_root != null:
		CardAnimations.reset(card_root)


# ══════════════════════════════════════════════
#  待机动画
# ══════════════════════════════════════════════

## 开始待机微动（不规律地围绕中心微微浮动），循环播放直到手动停止。
func start_idle(max_offset: float = 2.0, base_duration: float = 0.2) -> void:
	if card_root == null: return
	stop_idle()
	_idle_tween = CardAnimations.idle_float(card_root, max_offset, base_duration)

## 停止待机微动并回到原位。
func stop_idle() -> void:
	if _idle_tween != null and _idle_tween.is_valid():
		_idle_tween.kill()
	_idle_tween = null


# ══════════════════════════════════════════════
#  复合动画（由原子方法组合）
# ══════════════════════════════════════════════

## 抽牌：从牌堆飞入手牌区，弹入缩放 + 淡入。
func draw_card(from: Vector2, to: Vector2) -> void:
	if card_root == null: return
	await CardAnimations.draw_card(card_root, from, to).finished

## 手牌悬停：上浮 + 放大。
func hover_enter() -> void:
	if card_root == null: return
	await CardAnimations.hover_enter(card_root, _origin_y).finished

## 手牌悬停还原。
func hover_exit() -> void:
	if card_root == null: return
	await CardAnimations.hover_exit(card_root, _origin_y).finished

## 更新悬停锚点 Y（手牌重新排列后调用）。
func update_origin_y() -> void:
	if card_root != null:
		_origin_y = card_root.position.y

## 出牌：飞向目标，飞行中缩小增强速度感。
func play_card(target: Vector2) -> void:
	if card_root == null: return
	await CardAnimations.play_card(card_root, target).finished

## 弃牌：飞向弃牌堆 + 缩小 + 淡出，结束后自动删除节点。
func discard_card(discard_pos: Vector2) -> void:
	if card_root == null: return
	await CardAnimations.discard_card(card_root, discard_pos).finished

## 受击：水平抖动 + 闪白并行。
func play_hit() -> void:
	if card_root == null: return
	if card_sprite != null:
		await CardAnimations.hit(card_root, card_sprite)
	else:
		await shake_x().finished

## 怪物死亡：闪红 → 弹跳缩小 → 淡出 → 删除节点。有死亡锁防重入。
func play_death() -> void:
	if _dying or card_root == null: return
	_dying = true
	if card_sprite != null:
		CardAnimations.death(card_sprite, card_root)
	else:
		await scale_to_zero().finished
		await fade_out(0.15).finished
		if is_instance_valid(card_root):
			card_root.queue_free()
