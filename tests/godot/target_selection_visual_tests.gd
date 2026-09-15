extends SceneTree

const MONSTER_SCENE := preload("res://scenes/monster_scenes/monster.tscn")
const CARD_MANAGER_SCRIPT := preload("res://scripts/card_scripts/card_manager.gd")
const SKILL_CARD_SCENE := preload("res://scenes/skill_card_scenes/SkillCard.tscn")
const SKILL_TARGETING_TYPE := preload("res://scripts/generated/SkillTargetingType.gd")

# 累积断言失败信息，使一次运行能报告所有目标选择视觉回归。
var _failures: Array[String] = []


func _init() -> void:
	call_deferred(&"_run")


func _run() -> void:
	await _test_static_selected_and_unavailable_visuals()
	await _test_pulse_can_be_stopped_and_reset()
	await _test_monster_presentation_controls_allow_target_selection()
	_test_drag_ghost_keeps_real_card_and_ignores_input()
	_test_auto_target_types_reject_manual_enemy_selection()
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


func _test_drag_ghost_keeps_real_card_and_ignores_input() -> void:
	# 独立 CardManager 足以覆盖虚影创建契约，不需要启动完整战斗状态机。
	var card_manager: Node2D = CARD_MANAGER_SCRIPT.new()
	# 正式卡牌场景保证虚影验证覆盖真实 Area2D、标签与锁定遮罩节点。
	var source_card: Node2D = SKILL_CARD_SCENE.instantiate()
	# 真实卡的初始位置用于验证创建虚影不会移动手牌本身。
	var source_position := Vector2(180.0, 620.0)
	source_card.position = source_position
	card_manager.add_child(source_card)

	# 通过正式创建入口获得完整展示副本，而不是在测试中手工重建卡面。
	var drag_ghost: Node2D = card_manager.call("_create_card_drag_ghost", source_card) as Node2D
	_assert(drag_ghost != null, "拖拽开始时应创建独立的卡牌虚影。")
	if drag_ghost == null:
		return
	_assert(drag_ghost != source_card, "拖拽虚影不能复用真实手牌节点。")
	_assert(source_card.position == source_position, "创建虚影不能移动真实手牌。")
	_assert(drag_ghost.position == source_position, "虚影初始位置应与真实手牌重合。")
	_assert(is_equal_approx(drag_ghost.modulate.a, 0.5), "拖拽虚影应固定为 50% 不透明度。")
	_assert(drag_ghost.scale == card_manager.get("card_drag_scale"), "拖拽虚影应复用既有拖拽缩放参数。")

	# 虚影复制了真实 Area2D，但必须退出物理点查询与鼠标输入，不能遮挡卡牌或目标卡槽。
	var ghost_area: Area2D = drag_ghost.get_node("Area2D") as Area2D
	# 真实卡名称用于确认虚影复制的是完整卡面内容，而不只是背景贴图。
	var source_name_label: Label = source_card.get_node("CardName") as Label
	# 虚影标签是 GUI 透传策略的代表节点，验证递归配置不会遗漏卡面文字。
	var ghost_name_label: Label = drag_ghost.get_node("CardName") as Label
	_assert(ghost_name_label.text == source_name_label.text, "拖拽虚影应保留真实卡的卡面内容。")
	_assert(ghost_area.collision_layer == 0, "拖拽虚影不应保留手牌物理碰撞层。")
	_assert(ghost_area.collision_mask == 0, "拖拽虚影不应参与任何物理碰撞查询。")
	_assert(not ghost_area.input_pickable, "拖拽虚影的 Area2D 不应接收鼠标输入。")
	_assert(ghost_name_label.mouse_filter == Control.MOUSE_FILTER_IGNORE, "拖拽虚影的卡面标签应允许鼠标穿透。")

	# 清理入口需先隐藏虚影，保证松开鼠标的当前帧不会同时显示虚影与真实飞行牌。
	card_manager.call("_clear_card_drag_ghost")
	_assert(not drag_ghost.visible, "清理拖拽虚影后应立即隐藏该节点。")
	card_manager.queue_free()


func _test_auto_target_types_reject_manual_enemy_selection() -> void:
	# CardManager 的目标类型策略函数由点击确认和拖拽释放共用，不依赖战斗场景即可验证自动目标不会进入手动敌人选择分支。
	var card_manager = CARD_MANAGER_SCRIPT.new()
	# 单体敌人是传统点击选目标卡，必须保留人工选择能力。
	var single_enemy_type: int = SKILL_TARGETING_TYPE.Value.SingleEnemy
	# 扩散敌人依赖中心敌人计算相邻目标，也必须保留人工选择能力。
	var spread_enemy_type: int = SKILL_TARGETING_TYPE.Value.SpreadFromEnemy
	# 全体敌人会由卡牌固有目标规则展开，不应采纳鼠标下单个敌人。
	var all_enemies_type: int = SKILL_TARGETING_TYPE.Value.AllEnemies
	# 随机敌人必须在行动开始时重新随机一次，同样不应采纳点击目标。
	var random_enemy_type: int = SKILL_TARGETING_TYPE.Value.RandomEnemy
	# 全体单位属于自动范围目标，不能生成单体飞行动画目标。
	var all_units_type: int = SKILL_TARGETING_TYPE.Value.AllUnits

	_assert(bool(card_manager.call("_requires_manual_enemy_target", single_enemy_type)), "单体敌人牌应继续允许点击选择目标。")
	_assert(bool(card_manager.call("_requires_manual_enemy_target", spread_enemy_type)), "扩散敌人牌应继续允许点击选择中心目标。")
	_assert(not bool(card_manager.call("_requires_manual_enemy_target", all_enemies_type)), "全体敌人牌不应允许点击选择单个敌人。")
	_assert(not bool(card_manager.call("_requires_manual_enemy_target", random_enemy_type)), "随机敌人牌不应允许点击选择单个敌人。")
	_assert(not bool(card_manager.call("_requires_manual_enemy_target", all_units_type)), "全体单位牌不应允许点击选择单个敌人。")

	card_manager.queue_free()


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
