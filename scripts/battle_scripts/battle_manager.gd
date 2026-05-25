extends Node

signal battle_ended(is_victory: bool)

#region onready
@onready var deck_manager = $DeckManager
@onready var player_hand = $PlayerHand
@onready var control_lock = $ControlLock
@onready var player_manager = $PlayerManager
@onready var monster_manager = $MonsterManager
@onready var action_timeline = $UI/ActionTimeline
#endregion

#region exprot
@export_group("初始化参数")
@export var starting_deck_data: Array[SkillCardData] ##初始携带的卡组的卡牌数据。
@export var starting_monster_data: Array[MonsterData] ##初始怪物的卡牌数据。
@export var card_scene: PackedScene

@export_group("视觉缩放参数")
@export var monster_normal_scale: Vector2 = Vector2(1.5, 1.5) ## 怪物正常大小
@export var monster_turn_scale: Vector2 = Vector2(1.6, 1.6) ## 怪物回合时放大
@export var scale_tween_duration: float = 0.2 ## 缩放动画过渡时间

@export_group("游戏参数")
@export var turn_draw_count:int = 5 ##每回合摸牌数
@export var action_total:float = 10000.0 ##行动值总值
#endregion

#region 其他参数
const CONTEXT_SCRIPT_PATH : String = "res://core/combat/skills/SkillExecutionContext.cs"
const SKILL_TARGETING_TYPE_BRIDGE := preload("res://scripts/battle_scripts/skill_targeting_type_bridge.gd")

# 通过桥接器读取 C# 枚举，避免在 GDScript 中重复维护顺序。
@onready var _skill_targeting_type_map: Dictionary = SKILL_TARGETING_TYPE_BRIDGE.get_map()

## 战斗状态机的状态定义
enum BattleState {
	COMBAT_START,    ## 战斗初始化
	CALCULATE_TURN,  ## 基于速度计算行动顺序（谁先到0谁行动）
	PLAYER_TURN,     ## 玩家回合（可拖拽卡牌）
	ENEMY_TURN,      ## 敌人回合（执行AI逻辑）
	EXECUTE_ACTIONS, ## 执行行动队列（结算动画与效果）
	TURN_END,        ## 回合结束清理与胜负判定
	COMBAT_END       ## 战斗完全结束
}
var current_state: BattleState = BattleState.COMBAT_START ## 当前战斗状态

## 行动队列：用于存放玩家打出的卡牌或敌人的攻击行为。
## 确保所有行为排队依次执行，方便做动画延时与视觉表现。
var action_queue: Array[Action] = []

## 当前正在行动的实体（玩家 player_manager 或某个特定的怪物实体）
var active_entity: Variant = null
#endregion

## 获取当前场上所有的战斗实体，用于传给 UI 行动轴等系统
func get_all_combatants() -> Array:
	var combatants = []
	if player_manager:
		combatants.append(player_manager)
	if monster_manager and monster_manager.active_monsters:
		combatants.append_array(monster_manager.active_monsters)
	return combatants

func _unwrap_combat_entity(entity: Variant) -> Node:
	# 将包装器节点解包为真实的 C# 实体节点（用于技能结算）
	if entity and entity.has_method("get_combat_entity"):
		return entity.get_combat_entity()
	return entity

func _is_player_actor(actor: Variant) -> bool:
	# 判断是否是玩家行动实体（PlayerManager）
	return actor == player_manager

func _is_monster_actor(actor: Variant) -> bool:
	# 判断是否是场上怪物实体
	return monster_manager and monster_manager.active_monsters and monster_manager.active_monsters.has(actor)

func _get_enemies_for_source(source: Variant) -> Array:
	# 根据施法者/攻击者阵营动态取得敌人列表
	if _is_player_actor(source):
		if monster_manager and monster_manager.active_monsters:
			return monster_manager.active_monsters.duplicate()
		return []
	if _is_monster_actor(source):
		var enemies: Array = []
		if player_manager:
			enemies.append(player_manager)
		return enemies
	if monster_manager and monster_manager.active_monsters:
		return monster_manager.active_monsters.duplicate()
	return []

func _pick_random_from(list: Array):
	# 从列表中安全随机选择一个元素
	if not list or list.is_empty():
		return null
	return list.pick_random()

func _is_active_entity_valid() -> bool:
	# 避免引用已被销毁的节点，防止战斗流程中断
	if active_entity == null:
		return false
	if not is_instance_valid(active_entity):
		active_entity = null
		return false
	return true

func _ready():
	#初始化摸牌堆
	deck_manager.initialize_deck(starting_deck_data)

	# 先连接信号，确保初次生成怪物时不会漏掉回调
	monster_manager.monsters_spawned.connect(_on_monsters_spawned)
	monster_manager.monster_defeated.connect(_on_monster_defeated)
	#初始化怪物
	monster_manager.initialize_monsters(starting_monster_data)

#未测试
	_connect_combatant_attribute_signals(player_manager)
	for monster in monster_manager.active_monsters:
		_connect_combatant_attribute_signals(monster)

	change_state(BattleState.COMBAT_START)

#未测试
func _connect_combatant_attribute_signals(combatant: Variant):
	var real_entity = combatant.get_combat_entity() if combatant.has_method("get_combat_entity") else combatant
	if not real_entity or not real_entity.has_method("get_node_or_null"):
		return

	var attr_comp = real_entity.get_node_or_null("Components/AttributeComponent")
	if attr_comp and attr_comp.has_signal("AttributeChanged"):
		if not attr_comp.is_connected("AttributeChanged", _on_combatant_attribute_changed):
			attr_comp.connect("AttributeChanged", _on_combatant_attribute_changed.bind(combatant))

func _on_combatant_attribute_changed(event: RefCounted, combatant: Variant):
	# TypeId 4 是 Speed
	if event.get("TypeId") == 4:
		var old_speed = event.get("OldValue")
		var new_speed = event.get("NewValue")

		print("[BattleManager] 检测到速度变化! 实体: ", combatant.name, " old: ", old_speed, " new: ", new_speed)

		# 当速度发生改变时，按比例调整当前的行动值
		if old_speed != null and new_speed != null and old_speed > 0 and new_speed > 0:
			var ratio = float(old_speed) / float(new_speed)
			var current_av = null
			if combatant.has_method("get_meta") and combatant.has_meta("action_value"):
				current_av = combatant.get_meta("action_value")
			elif "action_value" in combatant:
				current_av = combatant.action_value

			if current_av != null:
				var new_av = current_av * ratio
				print("[BattleManager] 重算行动值! current_av: ", current_av, " ratio: ", ratio, " new_av: ", new_av)
				if combatant.has_method("set_meta") and combatant.has_meta("action_value"):
					combatant.set_meta("action_value", new_av)
				elif "action_value" in combatant:
					combatant.action_value = new_av
				else:
					if combatant.has_method("set_meta"):
						combatant.set_meta("action_value", new_av)

			# 更新行动轴UI，平滑重排
			if action_timeline:
				action_timeline.update_timeline(get_all_combatants(), active_entity, action_total)

## 处理中途生成的怪物（为新怪物分配初始行动值）

## 处理怪物死亡，立即刷新时间轴
func _on_monster_defeated(monster):
	if action_timeline:
		action_timeline.update_timeline(get_all_combatants(), active_entity, action_total)

func _on_monsters_spawned():
	for monster in monster_manager.active_monsters:
		if not monster.has_meta("action_value"):
			var speed = 100.0
			var real_entity = monster.get_combat_entity() if monster.has_method("get_combat_entity") else monster
			if real_entity and real_entity.has_method("get_node_or_null"):
				var attr_comp = real_entity.get_node_or_null("Components/AttributeComponent")
				if attr_comp and attr_comp.has_method("GetEffectiveValue"):
					var val = attr_comp.call("GetEffectiveValue", 4)
					if val != null and float(val) > 1.0:
						speed = float(val)
			monster.set_meta("action_value", action_total / speed)

		#未测试
		_connect_combatant_attribute_signals(monster)

	if action_timeline:
		action_timeline.update_timeline(get_all_combatants(), active_entity, action_total)

## 统一的状态切换入口，负责状态流转的分发
func change_state(new_state: BattleState):
	current_state = new_state
	match current_state:
		BattleState.COMBAT_START:
			_handle_combat_start()
		BattleState.CALCULATE_TURN:
			_handle_calculate_turn()
		BattleState.PLAYER_TURN:
			_handle_player_turn()
		BattleState.ENEMY_TURN:
			_handle_enemy_turn()
		BattleState.EXECUTE_ACTIONS:
			_handle_execute_actions()
		BattleState.TURN_END:
			_handle_turn_end()
		BattleState.COMBAT_END:
			_handle_combat_end()

## 处理战斗初始化：为所有场上实体分配初始的 action_value（行动值）。
## action_value = action_total / 速度，值越小说明越快到达行动点。
func _handle_combat_start():
	print("--- 战斗开始 ---")
	player_manager.reset_action_value(action_total)
	for monster in monster_manager.active_monsters:
		var speed = 100.0
		var real_entity = monster.get_combat_entity() if monster.has_method("get_combat_entity") else monster
		if real_entity and real_entity.has_method("get_node_or_null"):
			var attr_comp = real_entity.get_node_or_null("Components/AttributeComponent")
			if attr_comp and attr_comp.has_method("GetEffectiveValue"):
				var val = attr_comp.call("GetEffectiveValue", 4)
				if val != null and float(val) > 1.0:
					speed = float(val)

		monster.set_meta("action_value", action_total / speed)

	# 初始化完成后，进入计算回合阶段
	if action_timeline:
		action_timeline.update_timeline(get_all_combatants(), active_entity, action_total)
	change_state(BattleState.CALCULATE_TURN)

## 计算行动顺位（ATB系统）：找出当前场上 action_value 最小的实体。
## 将所有实体的 action_value 减去这个最小值，让最快的实体数值归零并获得行动权。
func _handle_calculate_turn():
	var min_av_entity = player_manager
	var min_av = player_manager.action_value

	# 遍历所有怪物，寻找最小行动值
	for monster in monster_manager.active_monsters:
		var av = monster.get_meta("action_value", 100.0)
		if av < min_av:
			min_av = av
			min_av_entity = monster

	# 全体扣除此最小行动值，模拟时间流逝
	player_manager.action_value -= min_av
	for monster in monster_manager.active_monsters:
		var current_av = monster.get_meta("action_value", 100.0)
		monster.set_meta("action_value", current_av - min_av)

	# 记录当前获得回合的实体并进入对应回合
	active_entity = min_av_entity
	if action_timeline:
		action_timeline.update_timeline(get_all_combatants(), active_entity, action_total)

	_notify_turn_started()

	if active_entity == player_manager:
		change_state(BattleState.PLAYER_TURN)
	else:
		change_state(BattleState.ENEMY_TURN)

#专门用于分发回合开始/结束信号的函数
func _notify_turn_status(method_name: String):
	if not _is_active_entity_valid():
		return

	var current_actor = active_entity.get_combat_entity() if active_entity.has_method("get_combat_entity") else active_entity
	var combatants = get_all_combatants()
	for c in combatants:
		var entity = c.get_combat_entity() if c.has_method("get_combat_entity") else c
		if entity:
			var status_comp = entity.get("Status")
			if not status_comp:
				status_comp = entity.get_node_or_null("Components/StatusComponent")
			if not status_comp:
				status_comp = entity.get_node_or_null("StatusComponent")

			if status_comp and status_comp.has_method(method_name):
				status_comp.call(method_name, current_actor)

func _notify_turn_started():
	_notify_turn_status("OnTurnStarted")

func _notify_turn_ended():
	_notify_turn_status("OnTurnEnded")

## 玩家回合逻辑：重置玩家行动值、恢复能量、抽牌并解锁控制让玩家出牌。
func _handle_player_turn():
	print("--- 玩家回合开始 ---")
	if not _is_active_entity_valid():
		change_state(BattleState.CALCULATE_TURN)
		return
	player_manager.reset_action_value(action_total)
	player_manager.recover_energy(player_manager.max_energy)
	# need_draw_interval=false 时不会 yield，避免 await 非协程返回值
	deck_manager.draw_cards(turn_draw_count, false)
	control_lock.unlock()

## 敌方回合逻辑：锁定玩家控制，生成敌方的行动放入队列，随后进入执行状态。
func _handle_enemy_turn():
	print("--- 敌人回合开始 ---")
	control_lock.lock()

	if not _is_active_entity_valid():
		change_state(BattleState.CALCULATE_TURN)
		return

	if active_entity and active_entity.has_node("Sprite2D"):
		var tween = create_tween()
		tween.tween_property(active_entity.get_node("Sprite2D"), "scale", monster_turn_scale, scale_tween_duration)

	# 怪物回合只读取 CombatSkillData；玩家 SkillCardData 在玩家出牌路径处理。
	var combat_skill = null
	if active_entity and active_entity.has_method("GetRandomCombatSkill"):
		combat_skill = active_entity.GetRandomCombatSkill()

	if combat_skill:
		var action = Action.new(active_entity, [], combat_skill, "skill", "SKILL")
		enqueue_action(action)
	else:
		# 兜底：没有技能时执行基础攻击
		var action = Action.new(active_entity, [player_manager], null, "attack", "ATTACK")
		enqueue_action(action)

	# 重置怪物的行动值
	var speed = 100.0
	var real_entity = active_entity.get_combat_entity() if active_entity.has_method("get_combat_entity") else active_entity
	if real_entity and real_entity.has_method("get_node_or_null"):
		var attr_comp = real_entity.get_node_or_null("Components/AttributeComponent")
		if attr_comp and attr_comp.has_method("GetEffectiveValue"):
			var val = attr_comp.call("GetEffectiveValue", 4)
			if val != null and float(val) > 1.0:
				speed = float(val)
	active_entity.set_meta("action_value", action_total / speed)

	if action_timeline:
		action_timeline.update_timeline(get_all_combatants(), active_entity, action_total)
	change_state(BattleState.EXECUTE_ACTIONS)

## 将一个产生的行动压入队列。
## 玩家出牌时会立刻切入 EXECUTE_ACTIONS 去结算那张牌。
func enqueue_action(action: Action):
	action_queue.append(action)
	if current_state == BattleState.PLAYER_TURN:
		change_state(BattleState.EXECUTE_ACTIONS)

## 递归执行行动队列中的每个行动，直到队列为空
func _handle_execute_actions():
	control_lock.lock()

	# 队列为空时判断去向
	if action_queue.is_empty():
		if not _is_active_entity_valid():
			change_state(BattleState.CALCULATE_TURN)
			return
		if active_entity == player_manager:
			# 玩家出牌动画演示完毕，返还控制权让玩家继续出牌
			current_state = BattleState.PLAYER_TURN
			control_lock.unlock()
		else:
			# 敌方动作播完，直接进入回合结束判定
			change_state(BattleState.TURN_END)
		return

	# 取出首个行动进行执行，并等待执行完成（await 阻塞）
	var action = action_queue.pop_front()
	await _execute_single_action(action)

	# 每次行动后检测是否导致一方死亡而结束战斗
	if player_manager.hp <= 0 or (monster_manager.active_monsters.is_empty() and monster_manager.upcoming_monsters.is_empty()):
		change_state(BattleState.COMBAT_END)
		return

	# 递归调用自身，继续执行队列中的下一个行动
	_handle_execute_actions()

## 真正结算和表现单一行动的逻辑
func _execute_single_action(action: Action):
	print(action.source, " 执行行动 ", action.action_type, " 目标 ", action.targets)

	if action.action_type == "CARD" or action.action_type == "SKILL":
		# 玩家卡牌和怪物技能共享目标解析；结算时分别调用 SkillCardData 或 CombatSkillData。
		var target = action.targets[0] if action.targets.size() > 0 else null
		var combat_skill = null
		if action.action_type == "CARD" and action.card_data and action.card_data.get("Skill") != null:
			combat_skill = action.card_data.Skill
		elif action.action_type == "SKILL":
			combat_skill = action.card_data

		if combat_skill:
			var ContextClass = load(CONTEXT_SCRIPT_PATH)
			var context = null

			# 尝试安全地获取技能目标的枚举值，默认为自身
			# 这里用字典映射，避免 GDScript 自己维护一份枚举顺序
			var target_self = _skill_targeting_type_map.get("Self", 0)
			var target_single_enemy = _skill_targeting_type_map.get("SingleEnemy", 1)
			var target_all_enemies = _skill_targeting_type_map.get("AllEnemies", 2)
			var target_any_single = _skill_targeting_type_map.get("AnySingleUnit", 3)
			var target_all_units = _skill_targeting_type_map.get("AllUnits", 4)
			var target_random_enemy = _skill_targeting_type_map.get("RandomEnemy", 5)
			var target_spread_from_enemy = _skill_targeting_type_map.get("SpreadFromEnemy", 6)

			var targeting_type: int = target_self
			if combat_skill.get("TargetingType") != null:
				targeting_type = int(combat_skill.TargetingType)

			# ---------------------------------------------------------
			# 【重要：C# 实体解包】
			# 由于目前的 action.source (行动发起者) 和 target (技能目标)
			# 可能是 GDScript 的包装器节点（如 PlayerManager ），而 C# 侧的
			# 技能特效组件（如 DamageEffect）在应用效果时，需要去获取
			# 目标身上的特定 C# 组件（如 DamageReceiverComponent 等）。
			# 所以在将 target 传入 SkillExecutionContext 之前，必须
			# 调用包装器提供的 get_combat_entity() 提取出真正的 C# 实体节点。
			# ---------------------------------------------------------
			var real_source = _unwrap_combat_entity(action.source)
			var real_target = _unwrap_combat_entity(target)

			# 基于解析到的类型，动态收集场上目标并分配至对应上下文工厂
			match targeting_type:
				target_self:
					# 目标为自身：直接传入卡牌施放者
					context = ContextClass.Self(real_source)

				target_single_enemy:
					# 单体敌人：若未显式指定目标，则自动从敌方中随机选择
					if not real_target:
						var enemy = _pick_random_from(_get_enemies_for_source(action.source))
						real_target = _unwrap_combat_entity(enemy)
					if real_target:
						context = ContextClass.FromSingleTarget(real_source, real_target)
					else:
						push_warning("单体技能未找到目标，退化为以自身为目标")
						context = ContextClass.Self(real_source)

				target_any_single:
					# 任意单体：若未显式指定目标，则从场上所有单位中随机选择
					if not real_target:
						var any_unit = _pick_random_from(get_all_combatants())
						real_target = _unwrap_combat_entity(any_unit)
					if real_target:
						context = ContextClass.FromSingleTarget(real_source, real_target)
					else:
						push_warning("任意单体技能未找到目标，退化为以自身为目标")
						context = ContextClass.Self(real_source)

				target_all_enemies:
					# 全体敌人：根据施放者阵营动态选择敌对单位
					var enemies: Array[Node] = []
					for enemy in _get_enemies_for_source(action.source):
						var real_enemy = _unwrap_combat_entity(enemy)
						if real_enemy:
							enemies.append(real_enemy)
					if enemies.is_empty():
						context = ContextClass.Self(real_source)
					else:
						context = ContextClass.FromPrimaryTargets(real_source, enemies)

				target_all_units:
					# 全体单位：复用写好的 get_all_combatants() 获取包含玩家在内的所有人
					var all_units: Array[Node] = []
					for unit in get_all_combatants():
						var real_unit = _unwrap_combat_entity(unit)
						if real_unit:
							all_units.append(real_unit)
					if all_units.is_empty():
						context = ContextClass.Self(real_source)
					else:
						context = ContextClass.FromPrimaryTargets(real_source, all_units)

				target_random_enemy:
					# 随机单体敌人：根据施放者阵营动态选择敌对单位
					var random_enemy = _pick_random_from(_get_enemies_for_source(action.source))
					random_enemy = _unwrap_combat_entity(random_enemy)
					if random_enemy:
						context = ContextClass.FromSingleTarget(real_source, random_enemy)
					else:
						context = ContextClass.Self(real_source)

				target_spread_from_enemy:
					# 扩散类型：获取主目标，并根据其在怪物列表中的位置，提取相邻（左右）的敌人作为次要目标
					var spread_primary = target
					if not spread_primary:
						spread_primary = _pick_random_from(_get_enemies_for_source(action.source))
					var real_primary = _unwrap_combat_entity(spread_primary)
					var secondary_targets: Array[Node] = []
					if spread_primary and monster_manager and monster_manager.active_monsters:
						var monsters = monster_manager.active_monsters
						var target_index = monsters.find(spread_primary)

						# 如果主目标存在于当前怪物列表中（find 返回 -1 表示未找到）
						if target_index != -1:
							# 提取左侧相邻敌人，并确保其不越过左边界 (index 0)
							if target_index > 0:
								var left_enemy = monsters[target_index - 1]
								var real_left = _unwrap_combat_entity(left_enemy)
								if real_left:
									secondary_targets.append(real_left)
							# 提取右侧相邻敌人，并确保其不越过右边界 (最大 size - 1)
							if target_index < monsters.size() - 1:
								var right_enemy = monsters[target_index + 1]
								var real_right = _unwrap_combat_entity(right_enemy)
								if real_right:
									secondary_targets.append(real_right)

					# 封装为上下文对象，将找出的左右侧相邻敌人作为 secondary_targets 传入
					if real_primary:
						context = ContextClass.FromSpread(real_source, real_primary, secondary_targets)
					else:
						context = ContextClass.Self(real_source)

				_:
					# 兜底情况的容错处理
					if real_target:
						context = ContextClass.FromSingleTarget(real_source, real_target)
					else:
						context = ContextClass.Self(real_source)

			if context != null and action.action_type == "CARD" and action.card_data and action.card_data.has_method("ApplyEffect"):
				action.card_data.ApplyEffect(context)
			elif context != null and action.action_type == "SKILL" and combat_skill.has_method("Execute"):
				combat_skill.Execute(context)

	elif action.action_type == "ATTACK":
		# 敌人基础攻击的临时占位逻辑
		if action.targets.size() > 0 and action.targets[0].has_method("take_damage"):
			action.targets[0].take_damage(10)

	# 模拟动画或效果执行时间。将来可替换为 await 动画节点(AnimationPlayer)发出的 finished 信号
	await get_tree().create_timer(0.5).timeout

## 处理回合结束阶段的清理：如丢弃手牌、结算Buff/Debuff等
func _handle_turn_end():
	print("--- 回合结束 ---")
	_notify_turn_ended()

	# 防止回合结束时引用已销毁的行动者节点
	var has_valid_actor := _is_active_entity_valid()

	if has_valid_actor and active_entity == player_manager:
		deck_manager.discard_hand() # 玩家回合结束必定弃置所有手牌
	elif has_valid_actor:
		if active_entity.has_node("Sprite2D"):
			var tween = create_tween()
			tween.tween_property(active_entity.get_node("Sprite2D"), "scale", monster_normal_scale, scale_tween_duration)

	# 再次做一次安全检测，确认是否应该转入战斗结束
	if player_manager.hp <= 0 or (monster_manager.active_monsters.is_empty() and monster_manager.upcoming_monsters.is_empty()):
		change_state(BattleState.COMBAT_END)
	else:
		# 未结束则转入重新计算回合权
		if action_timeline:
			action_timeline.update_timeline(get_all_combatants(), active_entity, action_total)
		change_state(BattleState.CALCULATE_TURN)

## 战斗结束结算（可扩展弹出结算界面或回到大地图）
func _handle_combat_end():
	print("--- 战斗结束 ---")
	control_lock.lock()

	var is_victory = monster_manager.active_monsters.is_empty() and monster_manager.upcoming_monsters.is_empty()
	battle_ended.emit(is_victory)

## 玩家点击"结束回合"按钮触发
func _on_turn_end_pressed() -> void:
	# 仅在明确处于 PLAYER_TURN 状态且未被锁定时允许直接结束回合
	if control_lock.is_lock or current_state != BattleState.PLAYER_TURN:
		return
	change_state(BattleState.TURN_END)

## 临时调试用的摸牌按钮
func _on_draw_card_pressed() -> void:
	# 同样必须是玩家回合阶段才允许使用
	if control_lock.is_lock or current_state != BattleState.PLAYER_TURN:
		return
	await deck_manager.draw_cards(3)
