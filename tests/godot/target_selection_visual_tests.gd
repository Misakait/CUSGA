extends SceneTree

const MONSTER_SCENE := preload("res://scenes/monster_scenes/monster.tscn")

# 累积断言失败信息，使一次运行能报告所有目标选择视觉回归。
var _failures: Array[String] = []


func _init() -> void:
	call_deferred(&"_run")


func _run() -> void:
	await _test_static_selected_and_unavailable_visuals()
	await _test_pulse_can_be_stopped_and_reset()
	_finish()


func _create_monster() -> Node2D:
	# 测试怪物实例复用正式场景，确保 C# 缓存路径与描边节点名称不会和实际战斗脱节。
	var monster: Node2D = MONSTER_SCENE.instantiate()
	root.add_child(monster)
	await process_frame
	return monster


func _test_static_selected_and_unavailable_visuals() -> void:
	# 本用例中的怪物实例用于验证选中边框与不可选变暗共享同一套正式接口。
	var monster: Node2D = await _create_monster()
	# 正式场景中的卡面 Sprite2D 是缩放和颜色断言的可见主体。
	var sprite: Sprite2D = monster.get_node("Sprite2D")
	# 正式场景中的绿色描边节点必须由 Monster.cs 动态显示与隐藏。
	var outline: Line2D = monster.get_node("TargetSelectionOutline")
	# 主选中缩放与 CardManager 默认值保持一致，验证跨语言参数可直接应用。
	var primary_scale := Vector2(1.66, 1.66)
	# 绿色描边颜色与 CardManager 默认值保持一致，验证颜色参数不会被场景默认值覆盖。
	var outline_color := Color(0.25, 1.0, 0.35, 1.0)

	monster.call("ApplyTargetSelectionVisual", primary_scale, false, Color.WHITE, true, outline_color, 3.0, 0.0)
	await process_frame
	_assert(outline.visible, "主选中目标应显示绿色描边。")
	_assert(outline.default_color == outline_color, "主选中目标应使用传入的绿色描边颜色。")
	_assert(sprite.scale == primary_scale, "主选中目标应应用主目标缩放倍率。")

	# 不可选的灰暗倍率与 CardManager 默认值保持一致，验证卡面而非血条被变暗。
	var unavailable_color := Color(0.45, 0.45, 0.45, 1.0)
	monster.call("ApplyTargetSelectionVisual", Vector2(1.5, 1.5), true, unavailable_color, false, outline_color, 3.0, 0.0)
	await process_frame
	_assert(not outline.visible, "不可选目标不应保留绿色描边。")
	_assert(sprite.modulate == unavailable_color, "不可选目标应按配置的颜色倍率变暗。")

	monster.queue_free()
	await process_frame


func _test_pulse_can_be_stopped_and_reset() -> void:
	# 本用例中的怪物实例用于验证循环 Tween 在选中或取消后不会残留。
	var monster: Node2D = await _create_monster()
	# 读取正式卡面以确认复位接口会恢复标准缩放。
	var sprite: Sprite2D = monster.get_node("Sprite2D")
	# 读取正式描边以确认呼吸状态不会错误显示已选中边框。
	var outline: Line2D = monster.get_node("TargetSelectionOutline")

	monster.call("StartTargetSelectionPulse", Vector2(1.53, 1.53), Vector2(1.56, 1.56), 0.01)
	await create_timer(0.015).timeout
	_assert(not outline.visible, "可选目标的呼吸状态不应显示绿色描边。")

	monster.call("ResetTargetSelectionVisual", Vector2(1.5, 1.5), 0.0)
	await process_frame
	_assert(sprite.scale == Vector2(1.5, 1.5), "取消目标选择后卡面应恢复正常缩放。")
	_assert(sprite.modulate == Color.WHITE, "取消目标选择后卡面应恢复原始颜色。")
	_assert(not outline.visible, "取消目标选择后描边应隐藏。")

	monster.queue_free()
	await process_frame


func _assert(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("All target selection visual Godot tests passed.")
		quit(0)
		return

	for failure in _failures:
		push_error(failure)
	quit(1)
