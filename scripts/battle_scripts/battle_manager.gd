extends Node

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
## C# 中 SkillTargetingType 枚举的 GDScript 映射常量，避免魔法数字
enum SkillTargetingType {
	SELF = 0,               ## 自身
	SINGLE_ENEMY = 1,       ## 单体敌人
	ALL_ENEMIES = 2,        ## 全体敌人
	ANY_SINGLE_UNIT = 3,    ## 任意单体
	ALL_UNITS = 4,          ## 全体单位
	RANDOM_ENEMY = 5,       ## 随机单体敌人
	SPREAD_FROM_ENEMY = 6   ## 从单体敌人扩散
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

func _ready():
	#初始化摸牌堆
	deck_manager.initialize_deck(starting_deck_data)
	#初始化怪物
	monster_manager.initialize_monsters(starting_monster_data)
	monster_manager.monsters_spawned.connect(_on_monsters_spawned)
	monster_manager.monster_defeated.connect(_on_monster_defeated)


	change_state(BattleState.COMBAT_START)

## 处理中途生成的怪物（为新怪物分配初始行动值）

## 处理怪物死亡，立即刷新时间轴
func _on_monster_defeated(monster):
	if action_timeline:
		action_timeline.update_timeline(get_all_combatants(), active_entity)

func _on_monsters_spawned():
	for monster in monster_manager.active_monsters:
		if not monster.has_meta("action_value"):
			monster.set_meta("action_value", action_total / 100.0)
	if action_timeline:
		action_timeline.update_timeline(get_all_combatants(), active_entity)

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
## action_value = 10000 / 速度，值越小说明越快到达行动点。
func _handle_combat_start():
	print("--- 战斗开始 ---")
	player_manager.reset_action_value()
	for monster in monster_manager.active_monsters:
		# 假设怪物默认速度为100（后续可从 MonsterData 中读取动态速度）
		monster.set_meta("action_value", action_total / 100.0)

	# 初始化完成后，进入计算回合阶段
	if action_timeline:
		action_timeline.update_timeline(get_all_combatants(), active_entity)
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
		action_timeline.update_timeline(get_all_combatants(), active_entity)

	if active_entity == player_manager:
		change_state(BattleState.PLAYER_TURN)
	else:
		change_state(BattleState.ENEMY_TURN)

## 玩家回合逻辑：重置玩家行动值、恢复能量、抽牌并解锁控制让玩家出牌。
func _handle_player_turn():
	print("--- 玩家回合开始 ---")
	active_entity.reset_action_value()
	player_manager.recover_energy(player_manager.max_energy)
	deck_manager.draw_cards(turn_draw_count, false)
	control_lock.unlock()

## 敌方回合逻辑：锁定玩家控制，生成敌方的行动放入队列，随后进入执行状态。
func _handle_enemy_turn():
	print("--- 敌人回合开始 ---")
	control_lock.lock()

	if active_entity and active_entity.has_node("Sprite2D"):
		var tween = create_tween()
		tween.tween_property(active_entity.get_node("Sprite2D"), "scale", monster_turn_scale, scale_tween_duration)

	# 简单的敌人AI逻辑：对玩家造成攻击
	# 后续可替换为读取怪物的技能表或行为树进行决策
	var action = Action.new(active_entity, [player_manager], null, "attack", "ATTACK")
	enqueue_action(action)

	# 重置怪物的行动值
	active_entity.set_meta("action_value", action_total / 100.0)
	if action_timeline:
		action_timeline.update_timeline(get_all_combatants(), active_entity)
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

	if action.action_type == "CARD":
		# 如果是玩家打出的卡牌，提取 C# 侧的卡牌逻辑并应用其效果(ApplyEffect)
		var target = action.targets[0] if action.targets.size() > 0 else null
		if action.card_data and action.card_data.has_method("ApplyEffect"):
			var ContextClass = load(CONTEXT_SCRIPT_PATH)
			var context = null
			
			# 尝试安全地获取技能目标的枚举值，默认为自身
			var targeting_type: int = SkillTargetingType.SELF
			if action.card_data.get("Skill") != null and action.card_data.Skill.get("TargetingType") != null:
				targeting_type = action.card_data.Skill.TargetingType
			
			# 基于解析到的类型，动态收集场上目标并分配至对应上下文工厂
			match targeting_type:
				SkillTargetingType.SELF:
					# 目标为自身：直接传入卡牌施放者
					context = ContextClass.Self(action.source)
					
				SkillTargetingType.SINGLE_ENEMY, SkillTargetingType.ANY_SINGLE_UNIT:
					# 单体目标：依赖玩家拖拽或操作时传入的具体 target
					if target:
						context = ContextClass.FromSingleTarget(action.source, target)
					else:
						# 若发生未选中目标强行释放的异常情况，容错回退为自身
						push_warning("单体技能未找到目标，退化为以自身为目标")
						context = ContextClass.Self(action.source)
						
				SkillTargetingType.ALL_ENEMIES:
					# 全体敌人：从怪物管理器中提取所有存活怪物传入数组
					var enemies: Array[Node] = []
					if monster_manager and monster_manager.active_monsters:
						enemies.assign(monster_manager.active_monsters)
					context = ContextClass.FromPrimaryTargets(action.source, enemies)
					
				SkillTargetingType.ALL_UNITS:
					# 全体单位：复用写好的 get_all_combatants() 获取包含玩家在内的所有人
					var all_units: Array[Node] = []
					all_units.assign(get_all_combatants())
					context = ContextClass.FromPrimaryTargets(action.source, all_units)
					
				SkillTargetingType.RANDOM_ENEMY:
					# 随机单体敌人：在场上存活的怪物中随机抽取一个
					var random_target = null
					if monster_manager and monster_manager.active_monsters and monster_manager.active_monsters.size() > 0:
						random_target = monster_manager.active_monsters.pick_random()
					
					if random_target:
						context = ContextClass.FromSingleTarget(action.source, random_target)
					else:
						context = ContextClass.Self(action.source)
						
				SkillTargetingType.SPREAD_FROM_ENEMY:
					# 扩散类型：获取主目标，并根据其在怪物列表中的位置，提取相邻（左右）的敌人作为次要目标
					var secondary_targets: Array[Node] = []
					if target and monster_manager and monster_manager.active_monsters:
						var monsters = monster_manager.active_monsters
						var target_index = monsters.find(target)
						
						# 如果主目标存在于当前怪物列表中（find 返回 -1 表示未找到）
						if target_index != -1:
							# 提取左侧相邻敌人，并确保其不越过左边界 (index 0)
							if target_index > 0:
								secondary_targets.append(monsters[target_index - 1])
							# 提取右侧相邻敌人，并确保其不越过右边界 (最大 size - 1)
							if target_index < monsters.size() - 1:
								secondary_targets.append(monsters[target_index + 1])
								
					# 封装为上下文对象，将找出的左右侧相邻敌人作为 secondary_targets 传入
					context = ContextClass.FromSpread(action.source, target, secondary_targets)
					
				_:
					# 兜底情况的容错处理
					if target:
						context = ContextClass.FromSingleTarget(action.source, target)
					else:
						context = ContextClass.Self(action.source)

			if context != null:
				action.card_data.ApplyEffect(context)

	elif action.action_type == "ATTACK":
		# 敌人基础攻击的临时占位逻辑
		if action.targets.size() > 0 and action.targets[0].has_method("take_damage"):
			action.targets[0].take_damage(10)

	# 模拟动画或效果执行时间。将来可替换为 await 动画节点(AnimationPlayer)发出的 finished 信号
	await get_tree().create_timer(0.5).timeout

## 处理回合结束阶段的清理：如丢弃手牌、结算Buff/Debuff等
func _handle_turn_end():
	print("--- 回合结束 ---")
	if active_entity == player_manager:
		deck_manager.discard_hand() # 玩家回合结束必定弃置所有手牌
	else:
		if active_entity and active_entity.has_node("Sprite2D"):
			var tween = create_tween()
			tween.tween_property(active_entity.get_node("Sprite2D"), "scale", monster_normal_scale, scale_tween_duration)

	# 再次做一次安全检测，确认是否应该转入战斗结束
	if player_manager.hp <= 0 or (monster_manager.active_monsters.is_empty() and monster_manager.upcoming_monsters.is_empty()):
		change_state(BattleState.COMBAT_END)
	else:
		# 未结束则转入重新计算回合权
		if action_timeline:
			action_timeline.update_timeline(get_all_combatants(), active_entity)
		change_state(BattleState.CALCULATE_TURN)

## 战斗结束结算（可扩展弹出结算界面或回到大地图）
func _handle_combat_end():
	print("--- 战斗结束 ---")
	control_lock.lock()

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
	deck_manager.draw_cards(3)
