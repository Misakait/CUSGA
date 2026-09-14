extends SceneTree

const MONSTER_SCENE := preload("res://scenes/monster_scenes/monster.tscn")
const CARD_MANAGER_SCRIPT := preload("res://scripts/card_scripts/card_manager.gd")

# 累积断言失败信息，使一次运行能报告所有目标选择视觉回归。
var _failures: Array[String] = []


func _init() -> void:
	call_deferred(&"_run")


func _run() -> void:
	await _test_static_selected_and_unavailable_visuals()
	await _test_pulse_can_be_stopped_and_reset()
	await _test_monster_presentation_controls_allow_target_selection()
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

	monster.call("ApplyTargetSelectionVisual", primary_scale, false, Color.WHITE, true, outline_color, 2.0, 0.0)
	await process_frame
	_assert(outline.visible, "主选中目标应显示绿色描边。")
	_assert(outline.default_color == outline_color, "主选中目标应使用传入的绿色描边颜色。")
	_assert(is_equal_approx(outline.width, 2.0), "主选中目标应使用更薄的 2px 描边。")
	_assert(sprite.scale == primary_scale, "主选中目标应应用主目标缩放倍率。")

	# 次级描边颜色比主描边更浅且略透明，避免扩散范围压过主目标。
	var secondary_outline_color := Color(0.55, 1.0, 0.65, 0.80)
	monster.call("ApplyTargetSelectionVisual", Vector2(1.60, 1.60), false, Color.WHITE, true, secondary_outline_color, 2.0, 0.0)
	await process_frame
	_assert(outline.default_color == secondary_outline_color, "次级目标应使用更淡的绿色描边。")

	# 不可选的灰暗倍率与 CardManager 默认值保持一致，验证卡面而非血条被变暗。
	var unavailable_color := Color(0.45, 0.45, 0.45, 1.0)
	monster.call("ApplyTargetSelectionVisual", Vector2(1.5, 1.5), true, unavailable_color, false, outline_color, 2.0, 0.0)
	await process_frame
	_assert(not outline.visible, "不可选目标不应保留绿色描边。")
	_assert(sprite.modulate == unavailable_color, "不可选目标应按配置的颜色倍率变暗。")

	monster.queue_free()
	await process_frame


func _test_monster_presentation_controls_allow_target_selection() -> void:
	# 正式怪物实例用于验证名称、元素和属性等 GUI 展示节点都能沿父链识别为怪物卡面。
	var monster: Node2D = await _create_monster()
	# CardManager 的纯函数不依赖场景树即可验证 GUI 白名单规则。
	var card_manager = CARD_MANAGER_SCRIPT.new()
	# 名称标签是怪物卡面上默认会被 GUI 命中的展示控件。
	var card_name: Control = monster.get_node("CardName")
	# 元素标签同样需要放行，才能在其覆盖区域点击敌人。
	var element: Control = monster.get_node("Element")
	# 属性标签验证 MonsterAttribute 的深层子控件不会重新阻挡目标选择。
	var attribute_label: Control = monster.get_node("MonsterAttribute/power/PhyLabel")
	# 与怪物无关的独立控件必须继续阻挡世界输入。
	var unrelated_control := Control.new()

	_assert(bool(card_manager.call("_is_monster_card_presentation_control", card_name)), "怪物名称标签应允许继续选择敌人目标。")
	_assert(bool(card_manager.call("_is_monster_card_presentation_control", element)), "怪物元素标签应允许继续选择敌人目标。")
	_assert(bool(card_manager.call("_is_monster_card_presentation_control", attribute_label)), "MonsterAttribute 子控件应允许继续选择敌人目标。")
	_assert(not bool(card_manager.call("_is_monster_card_presentation_control", unrelated_control)), "非怪物 GUI 仍应阻挡世界目标选择。")

	card_manager.queue_free()
	unrelated_control.queue_free()
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
