@tool
extends McpTestSuite

## 点击模式目标确认契约套件。
##
## 本套件锁定「必须指定敌人的卡牌不能对自己使用」这条不变量：
## 单体、任意单体与扩散牌在未选中有效敌人时，既不能通过确认入口施放，
## 也要让点击模式操作栏的“确定”按钮处于禁用状态；
## 只有自身、全体敌人、随机敌人与全体单位等自动目标牌才允许在没有显式敌人时确认。
##
## 套件全部用「脚本 new() + 伪依赖」构造，不进入战斗场景树，
## 因此可以稳定覆盖确认入口的拒绝路径，也不会依赖编辑器当前打开哪个场景。

## 待验证的卡牌输入管理器脚本。
const CARD_MANAGER_SCRIPT: GDScript = preload("res://scripts/card_scripts/card_manager.gd")

## 待验证的点击模式操作栏脚本。
const CLICK_MODE_ACTION_BAR_SCRIPT: GDScript = preload("res://scripts/battle_scripts/click_mode_action_bar.gd")

## 待验证的卡牌包装数据脚本，用于按目标类型构造最小卡牌资源。
const SKILL_CARD_DATA_SCRIPT: GDScript = preload("res://resources/item/card/skill_card_data.gd")

## 待验证的战斗技能数据脚本，用于构造带指定目标类型的技能。
const COMBAT_SKILL_DATA_SCRIPT: GDScript = preload("res://core/combat/skills/combat_skill_data.gd")

## 生产手牌节点脚本；确认入口持有 SkillCard 类型引用，必须用同一脚本构造替身。
const SKILL_CARD_SCRIPT: GDScript = preload("res://scripts/card_scripts/skill_card.gd")

## 生成的目标类型枚举，取值与 C# SkillTargetingType 逐项一致。
const SKILL_TARGETING_TYPE: GDScript = preload("res://scripts/generated/SkillTargetingType.gd")

## 生产战斗场景路径，用于锁定操作栏按钮的节点路径契约。
const BATTLE_SCENE_PATH: String = "res://scenes/battle_scenes/battle.tscn"

## 生产单体伤害牌资源（“金击”），用于验证真实数据仍落在必须手动选目标的集合里。
const SINGLE_ENEMY_CARD_PATH: String = "res://resources/skill_cards/metal_phys_jinji.tres"


## 只提供在场敌人数组协议的伪怪物管理器。
class FakeMonsterManager extends Node:
	## 当前仍在场的怪物节点；确认目标判定只接受这里的节点。
	var active_monsters: Array[Node] = []


## 只提供战斗状态与怪物管理器协议的伪战斗管理器。
class FakeBattleManager extends Node:
	## 与生产 BattleManager.BattleState 同序的状态枚举；PLAYER_TURN 的整型值为 2。
	enum BattleState {
		COMBAT_START,
		CALCULATE_TURN,
		PLAYER_TURN,
		ENEMY_TURN,
		EXECUTE_ACTIONS,
		TURN_END,
		COMBAT_END,
	}

	## 当前战斗状态；默认停在玩家回合，使确认路径不被回合守卫提前拦下。
	var current_state: int = BattleState.PLAYER_TURN

	## 场上敌人来源；构造时同步建立，保证 active_monsters 协议始终可读。
	var monster_manager: FakeMonsterManager = null

	## 建立伪怪物管理器，使 CardManager 的在场敌人查询始终可用。
	## @return void 无返回值。
	func _init() -> void:
		monster_manager = FakeMonsterManager.new()
		add_child(monster_manager)


## 只提供输入锁字段的伪控制锁。
class FakeControlLock extends Node:
	## 是否锁定玩家输入；默认 false，让确认路径走到真正的目标判定。
	var is_lock: bool = false


## 记录能量读数与消耗的伪玩家管理器。
class FakePlayerManager extends Node:
	## 当前可用能量；默认远高于测试卡牌费用，避免能量守卫掩盖目标规则。
	var energy: int = 999

	## 每次确认实际扣除的能量点数。
	var consumed_energy: Array[int] = []

	## 记录一次能量扣除。
	## @param amount 本次扣除的能量点数。
	## @return void 无返回值。
	func consume_energy(amount: int) -> void:
		consumed_energy.append(amount)
		energy -= amount


## 记录出牌请求的伪牌堆管理器。
class FakeDeckManager extends Node:
	## 每次确认实际提交的卡牌与目标。
	var play_card_calls: Array[Dictionary] = []

	## 记录一次出牌请求。
	## @param card 被确认施放的卡牌节点。
	## @param target 施放目标；自动或自身目标牌可能为空。
	## @return void 无返回值。
	func play_card(card, target = null) -> void:
		play_card_calls.append({"card": card, "target": target})


## 只暴露卡牌数据字段的最小卡牌替身。
##
## 目标类型判定只读取 `data.Skill.TargetingType`，因此不必构造完整手牌节点。
class FakeCard extends Node:
	## 卡牌包装资源，提供与生产 SkillCardData 相同的 Skill 字段协议。
	var data: Resource = null


## 返回 GodotAI 使用的稳定套件名称。
## @return String 点击模式目标契约套件名。
func suite_name() -> String:
	return "click_mode_target_contract"


## 验证必须指定敌人的三种目标类型在缺少在场敌人时一律拒绝确认。
## @return void 无返回值。
func test_manual_enemy_types_require_a_live_enemy() -> void:
	var manager: Node2D = CARD_MANAGER_SCRIPT.new()
	track(manager)
	var battle: FakeBattleManager = _install_fake_battle_manager(manager)
	# 在场敌人是唯一被接受的显式目标。
	var live_monster: Node2D = _new_monster(battle)
	# 已离场敌人用于证明判定读取的是当前战场，而不是“曾经选中过”的历史状态。
	var left_monster: Node2D = _new_monster(battle)
	battle.monster_manager.active_monsters.erase(left_monster)

	# 必须由玩家指定敌人的三种目标类型：单体敌人、任意单体与扩散敌人。
	var manual_types: Array[int] = [
		SKILL_TARGETING_TYPE.Value.SingleEnemy,
		SKILL_TARGETING_TYPE.Value.AnySingleUnit,
		SKILL_TARGETING_TYPE.Value.SpreadFromEnemy,
	]
	for targeting_type: int in manual_types:
		var card: Node = _new_card(targeting_type)
		assert_false(
			bool(manager.call("_is_click_selection_target_ready", card, null)),
			"目标类型 %d 未选中敌人时不得允许确认，否则会对自己施放。" % targeting_type
		)
		assert_false(
			bool(manager.call("_is_click_selection_target_ready", card, left_monster)),
			"目标类型 %d 不得把已离场敌人当作可确认目标。" % targeting_type
		)
		assert_true(
			bool(manager.call("_is_click_selection_target_ready", card, live_monster)),
			"目标类型 %d 选中在场敌人后必须允许确认。" % targeting_type
		)


## 验证自动与自身目标牌不需要显式敌人即可确认。
## @return void 无返回值。
func test_auto_and_self_types_confirm_without_enemy() -> void:
	var manager: Node2D = CARD_MANAGER_SCRIPT.new()
	track(manager)
	_install_fake_battle_manager(manager)

	# 这些目标类型由卡牌固有规则展开，玩家不需要也不应该指定单个敌人。
	var automatic_types: Array[int] = [
		SKILL_TARGETING_TYPE.Value.Self,
		SKILL_TARGETING_TYPE.Value.AllEnemies,
		SKILL_TARGETING_TYPE.Value.RandomEnemy,
		SKILL_TARGETING_TYPE.Value.AllUnits,
	]
	for targeting_type: int in automatic_types:
		var card: Node = _new_card(targeting_type)
		assert_true(
			bool(manager.call("_is_click_selection_target_ready", card, null)),
			"目标类型 %d 属于自动或自身目标，未选敌人时仍必须允许确认。" % targeting_type
		)


## 验证没有任何卡牌数据时确认会被拒绝，避免空选择进入施放流程。
## @return void 无返回值。
func test_missing_card_cannot_be_ready() -> void:
	var manager: Node2D = CARD_MANAGER_SCRIPT.new()
	track(manager)
	var battle: FakeBattleManager = _install_fake_battle_manager(manager)
	var monster: Node2D = _new_monster(battle)

	assert_false(
		bool(manager.call("_is_click_selection_target_ready", null, monster)),
		"没有待确认卡牌时不得具备可确认状态。"
	)


## 验证确认入口在未选中敌人时拒绝整次施放，且不扣能量、不提交行动队列。
## @return void 无返回值。
func test_confirm_entry_refuses_card_without_enemy_target() -> void:
	# CardManager 只做逻辑断言，因此不进入场景树，避免触发对 PlayerHand 等正式节点的 @onready 查找。
	var manager: Node2D = CARD_MANAGER_SCRIPT.new()
	track(manager)
	var battle: FakeBattleManager = _install_fake_battle_manager(manager)
	# 场上存在一名敌人：本用例验证的正是“有敌人可选但玩家没有选”这条路径。
	_new_monster(battle)

	var player: FakePlayerManager = FakePlayerManager.new()
	track(player)
	var deck: FakeDeckManager = FakeDeckManager.new()
	track(deck)
	var control_lock: FakeControlLock = FakeControlLock.new()
	track(control_lock)
	manager.set("player_manager", player)
	manager.set("deck_manager", deck)
	manager.set("control_lock", control_lock)

	# 生产单体伤害牌，其目标类型为 SingleEnemy，正是会错误命中玩家自身的那一类卡牌。
	var jinji: Node = _new_skill_card(SINGLE_ENEMY_CARD_PATH)
	manager.set("_selected_click_card", jinji)
	manager.set("_selected_click_target", null)

	assert_false(
		bool(manager.call("_can_confirm_click_selection")),
		"单体伤害牌未选中敌人时不得具备可确认状态。"
	)
	assert_true(
		manager.call("_get_confirmed_click_mode_target") == null,
		"缺少有效敌人时确认目标不得回退为玩家自身。"
	)

	manager.call("_confirm_click_mode_card")

	assert_eq((deck.play_card_calls as Array).size(), 0, "未选中敌人时确认不得把卡牌提交给行动队列。")
	assert_eq((player.consumed_energy as Array).size(), 0, "未选中敌人时确认不得消耗能量。")
	assert_true(
		manager.get("_selected_click_card") == jinji,
		"被拒绝的确认必须保留当前选择，允许玩家补选目标后再次确认。"
	)


## 验证选中在场敌人后目标规则恢复放行，并且确认目标就是该敌人。
## @return void 无返回值。
func test_confirm_selection_accepts_selected_live_enemy() -> void:
	var manager: Node2D = CARD_MANAGER_SCRIPT.new()
	track(manager)
	var battle: FakeBattleManager = _install_fake_battle_manager(manager)
	var monster: Node2D = _new_monster(battle)
	# 已离场敌人用于证明“选中过就不再校验”这种错误实现不会通过。
	var left_monster: Node2D = _new_monster(battle)
	battle.monster_manager.active_monsters.erase(left_monster)

	var player: FakePlayerManager = FakePlayerManager.new()
	track(player)
	manager.set("player_manager", player)

	var jinji: Node = _new_skill_card(SINGLE_ENEMY_CARD_PATH)
	manager.set("_selected_click_card", jinji)

	manager.set("_selected_click_target", left_monster)
	assert_false(
		bool(manager.call("_can_confirm_click_selection")),
		"选中已离场敌人时不得具备可确认状态。"
	)

	manager.set("_selected_click_target", monster)
	assert_true(
		bool(manager.call("_can_confirm_click_selection")),
		"选中在场敌人后必须恢复可确认状态。"
	)
	assert_true(
		manager.call("_get_confirmed_click_mode_target") == monster,
		"选中在场敌人后确认目标必须是该敌人，而不是玩家自身。"
	)


## 验证生产单体伤害牌仍然属于必须手动选择敌人的集合。
## @return void 无返回值。
func test_single_enemy_production_card_requires_manual_target() -> void:
	var manager: Node2D = CARD_MANAGER_SCRIPT.new()
	track(manager)
	var battle: FakeBattleManager = _install_fake_battle_manager(manager)
	var monster: Node2D = _new_monster(battle)

	var card_data: Resource = load(SINGLE_ENEMY_CARD_PATH)
	assert_true(card_data != null, "必须能加载单体伤害卡牌资源。")
	if card_data == null:
		return

	var card: FakeCard = FakeCard.new()
	track(card)
	card.data = card_data

	var targeting_type: int = int(manager.call("_get_card_targeting_type", card))
	assert_true(
		bool(manager.call("_requires_manual_enemy_target", targeting_type)),
		"单体伤害牌必须保留手动选择敌人的目标规则。"
	)
	assert_false(
		bool(manager.call("_is_click_selection_target_ready", card, null)),
		"单体伤害牌未选中敌人时不得允许确认。"
	)
	assert_true(
		bool(manager.call("_is_click_selection_target_ready", card, monster)),
		"单体伤害牌选中在场敌人后必须允许确认。"
	)


## 验证未选目标时“确定”按钮被禁用，并验证隐藏操作栏会清除该禁用状态。
## @return void 无返回值。
func test_action_bar_disables_confirm_button_without_target() -> void:
	var bar: HBoxContainer = _new_action_bar()
	var confirm_button: Button = bar.get_node("ConfirmButton") as Button

	assert_true(confirm_button != null, "操作栏必须保留 ConfirmButton 固定路径。")
	if confirm_button == null:
		return
	assert_false(confirm_button.disabled, "操作栏显示时确认按钮默认必须可用。")

	bar.call("set_confirm_available", false)
	assert_true(confirm_button.disabled, "未选中有效目标时确认按钮必须禁用。")

	bar.call("set_confirm_available", true)
	assert_false(confirm_button.disabled, "选中有效目标后确认按钮必须恢复可用。")

	# 隐藏操作栏代表本次选择结束；禁用状态若被保留，会让下一次选卡出现置灰按钮。
	bar.call("set_confirm_available", false)
	bar.call("set_actions_available", false)
	assert_false(bar.visible, "set_actions_available(false) 必须隐藏操作栏。")
	assert_false(confirm_button.disabled, "操作栏隐藏后必须清除确认按钮的禁用状态。")


## 验证卡牌管理器会把当前选择的确认可用性同步到操作栏。
## @return void 无返回值。
func test_card_manager_syncs_confirm_availability_to_action_bar() -> void:
	var manager: Node2D = CARD_MANAGER_SCRIPT.new()
	track(manager)
	_install_fake_battle_manager(manager)

	var bar: HBoxContainer = _new_action_bar()
	var confirm_button: Button = bar.get_node("ConfirmButton") as Button
	manager.set("_click_mode_action_bar", bar)

	# 没有待确认卡牌时必须禁用，避免空选择被当成可施放状态。
	manager.call("_refresh_click_mode_confirm_availability")
	assert_true(confirm_button.disabled, "没有待确认卡牌时确认按钮必须禁用。")

	# 注入一张单体伤害牌但仍未选中敌人：禁用状态必须继续保持。
	var jinji: Node = _new_skill_card(SINGLE_ENEMY_CARD_PATH)
	manager.set("_selected_click_card", jinji)
	manager.set("_selected_click_target", null)
	manager.call("_refresh_click_mode_confirm_availability")
	assert_true(confirm_button.disabled, "单体伤害牌未选中敌人时确认按钮必须保持禁用。")


## 验证生产战斗场景仍按固定路径提供确认与取消按钮。
## @return void 无返回值。
func test_battle_scene_keeps_action_bar_button_paths() -> void:
	var scene_text: String = FileAccess.get_file_as_string(BATTLE_SCENE_PATH)
	assert_false(scene_text.is_empty(), "必须能读到战斗场景。")
	assert_contains(
		scene_text,
		"[node name=\"ConfirmButton\" type=\"Button\" parent=\"UI/ClickModeActionBar\"",
		"操作栏必须保留 ConfirmButton 固定路径。"
	)
	assert_contains(
		scene_text,
		"[node name=\"CancelButton\" type=\"Button\" parent=\"UI/ClickModeActionBar\"",
		"操作栏必须保留 CancelButton 固定路径。"
	)


## 建立伪战斗管理器并注入卡牌管理器。
## @param manager 待注入的卡牌管理器实例。
## @return FakeBattleManager 已注入的伪战斗管理器。
func _install_fake_battle_manager(manager: Node) -> FakeBattleManager:
	var battle: FakeBattleManager = FakeBattleManager.new()
	track(battle)
	manager.set("battle_manager", battle)
	return battle


## 创建一名只提供节点身份的在场敌人。
## 目标规则只校验节点的存活与在场状态，因此无需构造完整怪物场景。
## @param battle 提供 active_monsters 的伪战斗管理器。
## @return Node2D 已登记为在场敌人的节点。
func _new_monster(battle: FakeBattleManager) -> Node2D:
	var monster: Node2D = Node2D.new()
	track(monster)
	battle.monster_manager.active_monsters.append(monster)
	return monster


## 构造一张只带目标类型数据的最小卡牌。
## @param targeting_type SkillTargetingType 枚举整型值。
## @return Node 携带 Skill.TargetingType 协议的卡牌替身。
func _new_card(targeting_type: int) -> Node:
	var skill: Resource = COMBAT_SKILL_DATA_SCRIPT.new()
	skill.set("TargetingType", targeting_type)
	var card_data: Resource = SKILL_CARD_DATA_SCRIPT.new()
	card_data.set("Skill", skill)
	var card: FakeCard = FakeCard.new()
	track(card)
	card.data = card_data
	return card


## 用真实卡牌资源构造一张未进入场景树的手牌节点。
## 确认入口持有 SkillCard 类型引用，因此这里必须使用生产手牌脚本构造实例。
## @param resource_path 卡牌包装资源路径。
## @return Node 带 data 的 SkillCard 实例。
func _new_skill_card(resource_path: String) -> Node:
	var card: Node = SKILL_CARD_SCRIPT.new()
	track(card)
	card.set("data", load(resource_path))
	return card


## 用生产脚本与最小按钮子树构造点击模式操作栏，并交给引擎正常触发 _ready。
## @return HBoxContainer 已进入测试场景树的操作栏实例。
func _new_action_bar() -> HBoxContainer:
	var scene_tree: SceneTree = Engine.get_main_loop() as SceneTree
	var bar: HBoxContainer = CLICK_MODE_ACTION_BAR_SCRIPT.new()
	bar.name = "ClickModeActionBarContractProbe"
	# 按钮名必须与生产场景逐字一致：操作栏脚本依赖 $ConfirmButton / $CancelButton 固定路径。
	var confirm_button: Button = Button.new()
	confirm_button.name = "ConfirmButton"
	bar.add_child(confirm_button)
	var cancel_button: Button = Button.new()
	cancel_button.name = "CancelButton"
	bar.add_child(cancel_button)
	track(bar)
	# 入树让引擎调用一次 _ready，从而完成 @onready 按钮引用与按钮信号连接。
	scene_tree.root.add_child(bar)
	return bar
