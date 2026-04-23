## CardAnimations.gd
## 卡牌原子动画库 —— 每个方法只做一件事，可自由组合。
## 所有方法为静态方法，返回 Tween，可 await tween.finished 等待完成。
class_name CardAnimations
extends RefCounted


# ──────────────────────────────────────────────
# 常量
# ──────────────────────────────────────────────

const FAST:   float = 0.10  ## 快速（闪白等）
const NORMAL: float = 0.25  ## 标准（悬停、出牌等）
const SLOW:   float = 0.40  ## 较慢（死亡、弃牌等）
const HOVER_LIFT: float = -20.0  ## 悬停上浮像素


# ══════════════════════════════════════════════
#  原子动画（每个只做一件事）
# ══════════════════════════════════════════════


# ────────── 透明度 ──────────

## 淡入：将节点 modulate.a 从当前值渐变到 1.0。
static func fade_in(node: CanvasItem, duration: float = NORMAL) -> Tween:
	var tween: Tween = node.get_tree().create_tween()
	tween.tween_property(node, "modulate:a", 1.0, duration)
	return tween


## 淡出：将节点 modulate.a 从当前值渐变到 0.0。
static func fade_out(node: CanvasItem, duration: float = NORMAL) -> Tween:
	var tween: Tween = node.get_tree().create_tween()
	tween.tween_property(node, "modulate:a", 0.0, duration)
	return tween


# ────────── 缩放 ──────────

## 缩放到指定值。
static func scale_to(node: Node2D, target: Vector2, duration: float = NORMAL,
		ease: Tween.EaseType = Tween.EASE_OUT,
		trans: Tween.TransitionType = Tween.TRANS_CUBIC) -> Tween:
	var tween: Tween = node.get_tree().create_tween()
	tween.tween_property(node, "scale", target, duration).set_ease(ease).set_trans(trans)
	return tween


## 弹入缩放：从 scale_from 弹性过渡到 scale_to（适合入场）。
static func scale_bounce(node: Node2D, scale_from: Vector2, scale_to: Vector2,
		duration: float = NORMAL) -> Tween:
	node.scale = scale_from
	var tween: Tween = node.get_tree().create_tween()
	tween.tween_property(node, "scale", scale_to, duration) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	return tween


## 缩放到零：节点缩至消失（适合死亡收尾）。
static func scale_to_zero(node: Node2D, duration: float = SLOW) -> Tween:
	var tween: Tween = node.get_tree().create_tween()
	tween.tween_property(node, "scale", Vector2.ZERO, duration) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)
	return tween


# ────────── 位移 ──────────

## 飞向全局坐标。
static func fly_to(node: Node2D, target: Vector2, duration: float = NORMAL,
		ease: Tween.EaseType = Tween.EASE_OUT,
		trans: Tween.TransitionType = Tween.TRANS_CUBIC) -> Tween:
	var tween: Tween = node.get_tree().create_tween()
	tween.tween_property(node, "global_position", target, duration).set_ease(ease).set_trans(trans)
	return tween


## 飞向本地坐标（相对父节点）。
static func move_to(node: Node2D, target: Vector2, duration: float = NORMAL,
		ease: Tween.EaseType = Tween.EASE_OUT,
		trans: Tween.TransitionType = Tween.TRANS_CUBIC) -> Tween:
	var tween: Tween = node.get_tree().create_tween()
	tween.tween_property(node, "position", target, duration).set_ease(ease).set_trans(trans)
	return tween


# ────────── 抖动 ──────────

## 水平抖动：节点沿 X 轴快速震荡后回正（衰减式，幅度逐次递减）。
## [param node]      目标节点
## [param amplitude] 最大抖动幅度（像素）
## [param duration]  总时长
static func shake_x(node: Node2D, amplitude: float = 10.0,
		duration: float = 0.28) -> Tween:
	var ox: float = node.position.x
	var tween: Tween = node.get_tree().create_tween()
	var offsets: Array[float] = [amplitude, -amplitude, amplitude * 0.6, -amplitude * 0.35, 0.0]
	for off: float in offsets:
		tween.tween_property(node, "position:x", ox + off, duration / 5.0) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	return tween


## 竖直抖动：节点沿 Y 轴快速震荡后回正。
static func shake_y(node: Node2D, amplitude: float = 10.0,
		duration: float = 0.28) -> Tween:
	var oy: float = node.position.y
	var tween: Tween = node.get_tree().create_tween()
	var offsets: Array[float] = [amplitude, -amplitude, amplitude * 0.6, -amplitude * 0.35, 0.0]
	for off: float in offsets:
		tween.tween_property(node, "position:y", oy + off, duration / 5.0) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	return tween


# ────────── 颜色叠加（Sprite2D 专用） ──────────

## 闪白：Sprite2D 短暂叠加高亮白色后恢复原色。
static func flash_white(sprite: Sprite2D, duration: float = 0.10) -> Tween:
	var tween: Tween = sprite.get_tree().create_tween()
	tween.tween_property(sprite, "self_modulate", Color(2.2, 2.2, 2.2, 1.0), 0.04)
	tween.tween_property(sprite, "self_modulate", Color.WHITE, duration)
	return tween


## 闪红：Sprite2D 短暂叠加红色后恢复原色。
static func flash_red(sprite: Sprite2D, duration: float = 0.10) -> Tween:
	var tween: Tween = sprite.get_tree().create_tween()
	tween.tween_property(sprite, "self_modulate", Color(2.0, 0.2, 0.2, 1.0), 0.04)
	tween.tween_property(sprite, "self_modulate", Color.WHITE, duration)
	return tween


## 闪指定颜色后恢复白色。
static func flash_color(sprite: Sprite2D, color: Color, duration: float = 0.10) -> Tween:
	var tween: Tween = sprite.get_tree().create_tween()
	tween.tween_property(sprite, "self_modulate", color, 0.04)
	tween.tween_property(sprite, "self_modulate", Color.WHITE, duration)
	return tween


# ────────── 旋转 ──────────

## 旋转到指定角度（弧度）。
static func rotate_to(node: Node2D, angle: float, duration: float = NORMAL) -> Tween:
	var tween: Tween = node.get_tree().create_tween()
	tween.tween_property(node, "rotation", angle, duration) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	return tween


## 旋转回零。
static func rotate_reset(node: Node2D, duration: float = NORMAL) -> Tween:
	return rotate_to(node, 0.0, duration)


## 摇摆：围绕当前角度左右旋转（适合待机微动或攻击摇晃）。
## [param angle]   最大摇摆角度（弧度），如 0.05
## [param duration] 单次摇摆时长
static func wobble(node: Node2D, angle: float = 0.05,
		duration: float = 0.4) -> Tween:
	var base: float = node.rotation
	var tween: Tween = node.get_tree().create_tween() \
		.set_loops().set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	tween.tween_property(node, "rotation", base + angle, duration * 0.5)
	tween.tween_property(node, "rotation", base - angle, duration * 0.5)
	return tween


# ────────── 节点管理 ──────────

## 延迟调用 queue_free（通常串联在淡出/缩放之后）。
static func queue_free_delayed(node: Node, delay: float = 0.0) -> Tween:
	var tween: Tween = node.get_tree().create_tween()
	tween.tween_callback(node.queue_free).set_delay(delay)
	return tween


## 立即重置节点到正常可见状态。
static func reset(node: Node2D) -> void:
	node.scale    = Vector2.ONE
	node.modulate = Color.WHITE
	node.rotation = 0.0


# ══════════════════════════════════════════════
#  待机动画
# ══════════════════════════════════════════════

## 待机微动：节点不规律地围绕中心点微微浮动。
## 使用 randf 生成随机偏移，每段 Tween 时长也随机变化，营造呼吸感。
## 返回循环 Tween，需手动 .kill() 停止。
## [param node]           目标节点
## [param max_offset]     最大偏移像素（默认 2.0，非常细微）
## [param base_duration]  每段微动的基准时长（实际会随机浮动）
static func idle_float(node: Node2D, max_offset: float = 2.0,
		base_duration: float = 0.2) -> Tween:
	var origin: Vector2 = node.position
	var tween: Tween = node.get_tree().create_tween().set_loops()

	# 每次循环：随机偏移 → 再回原位
	tween.tween_callback(func() -> void:
		var offset := Vector2(
			randf_range(-max_offset, max_offset),
			randf_range(-max_offset, max_offset)
		)
		var dur := base_duration + randf_range(-0.3, 0.3)
		node.get_tree().create_tween() \
			.tween_property(node, "position", origin + offset, dur) \
			.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	)
	tween.tween_interval(base_duration + randf_range(-0.2, 0.2))

	tween.tween_callback(func() -> void:
		var dur := base_duration + randf_range(-0.3, 0.3)
		node.get_tree().create_tween() \
			.tween_property(node, "position", origin, dur) \
			.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	)
	tween.tween_interval(base_duration + randf_range(-0.2, 0.2))

	return tween


# ══════════════════════════════════════════════
#  复合动画（由原子方法组合而成）
# ══════════════════════════════════════════════

## 抽牌：从牌堆飞入手牌区，同时弹入缩放 + 淡入。
static func draw_card(node: Node2D, from: Vector2, to: Vector2) -> Tween:
	node.global_position = from
	node.scale = Vector2(0.3, 0.3)
	node.modulate.a = 0.0

	var tween: Tween = node.get_tree().create_tween().set_parallel(true)
	tween.tween_property(node, "global_position", to, NORMAL) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(node, "scale", Vector2.ONE, NORMAL) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(node, "modulate:a", 1.0, NORMAL * 0.6)
	return tween


## 手牌悬停：上浮 + 放大。
static func hover_enter(node: Node2D, origin_y: float) -> Tween:
	var tween: Tween = node.get_tree().create_tween().set_parallel(true)
	tween.tween_property(node, "position:y", origin_y + HOVER_LIFT, FAST * 1.2) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(node, "scale", Vector2(1.08, 1.08), FAST * 1.2) \
		.set_ease(Tween.EASE_OUT)
	return tween


## 手牌悬停还原。
static func hover_exit(node: Node2D, origin_y: float) -> Tween:
	var tween: Tween = node.get_tree().create_tween().set_parallel(true)
	tween.tween_property(node, "position:y", origin_y, FAST * 1.2) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(node, "scale", Vector2.ONE, FAST * 1.2) \
		.set_ease(Tween.EASE_OUT)
	return tween


## 出牌：飞向目标，飞行中缩小增强速度感。
static func play_card(node: Node2D, target: Vector2) -> Tween:
	var tween: Tween = node.get_tree().create_tween().set_parallel(true)
	tween.tween_property(node, "global_position", target, NORMAL) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(node, "scale", Vector2(0.85, 0.85), NORMAL) \
		.set_ease(Tween.EASE_IN)
	return tween


## 弃牌：飞向弃牌堆 + 缩小 + 淡出，结束后自动删除。
static func discard_card(node: Node2D, discard_pos: Vector2) -> Tween:
	var tween: Tween = node.get_tree().create_tween().set_parallel(true)
	tween.tween_property(node, "global_position", discard_pos, SLOW) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(node, "modulate:a", 0.0, SLOW).set_ease(Tween.EASE_IN)
	tween.tween_property(node, "scale", Vector2(0.6, 0.6), SLOW).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(node.queue_free)
	return tween


## 受击：水平抖动 + 闪白并行。
static func hit(node: Node2D, sprite: Sprite2D) -> void:
	var t1: Tween = shake_x(node)
	var t2: Tween = flash_white(sprite)
	await t1.finished
	await t2.finished


## 怪物死亡：闪红 → 弹跳缩小 → 淡出 → 删除。
static func death(sprite: Sprite2D, node: Node2D) -> void:
	# 闪红
	await flash_red(sprite, 0.08).finished
	# 先弹起再缩到零
	await scale_bounce(node, Vector2(1.15, 1.15), Vector2.ZERO, SLOW * 1.4).finished
	# 淡出并删除
	await fade_out(node, 0.15).finished
	node.queue_free()
