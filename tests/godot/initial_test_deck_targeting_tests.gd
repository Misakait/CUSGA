extends SceneTree

const BATTLE_SCENE := preload("res://scenes/battle_scenes/battle.tscn")
const SKILL_TARGETING_TYPE := preload("res://scripts/generated/SkillTargetingType.gd")

# 累积断言失败信息，使牌池覆盖测试可一次报告所有漏掉的目标类型。
var _failures: Array[String] = []


func _init() -> void:
	call_deferred(&"_run")


func _run() -> void:
	# 实例化但不加入场景树，直接读取导出的初始牌组，避免测试触发完整战斗流程。
	var battle: Node = BATTLE_SCENE.instantiate()
	# 场景导出的测试卡数组是牌池覆盖断言的唯一数据来源。
	var starting_deck_data: Array = battle.get("starting_deck_data")
	# 以目标类型为键统计卡牌数，验证每种类型都有足够的抽取机会。
	var target_type_counts: Dictionary = {}
	# 所有目标类型必须在初始测试牌池中出现三次，避免 DeckManager 补入基础牌后掩盖遗漏。
	var required_target_types: Array[int] = [
		SKILL_TARGETING_TYPE.Value.Self,
		SKILL_TARGETING_TYPE.Value.SingleEnemy,
		SKILL_TARGETING_TYPE.Value.AllEnemies,
		SKILL_TARGETING_TYPE.Value.AnySingleUnit,
		SKILL_TARGETING_TYPE.Value.AllUnits,
		SKILL_TARGETING_TYPE.Value.RandomEnemy,
		SKILL_TARGETING_TYPE.Value.SpreadFromEnemy,
	]

	for card_data in starting_deck_data:
		# 当前测试卡需要同时拥有技能资源和目标类型；缺失时记录失败而不是让后续读取崩溃。
		if not card_data or not card_data.Skill:
			_failures.append("初始测试牌缺少 CombatSkillData。")
			continue
		# 目标类型以生成枚举的整数值统计，避免测试依赖资源文件名称或排列顺序。
		var targeting_type: int = int(card_data.Skill.TargetingType)
		target_type_counts[targeting_type] = int(target_type_counts.get(targeting_type, 0)) + 1

	_assert(starting_deck_data.size() == 21, "初始测试牌池应固定为七种类型各三张，共 21 张。")
	for targeting_type in required_target_types:
		_assert(int(target_type_counts.get(targeting_type, 0)) >= 3, "目标类型 %d 在初始测试牌池中至少需要三张。" % targeting_type)

	battle.queue_free()
	_finish()


func _assert(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("All initial test deck targeting Godot tests passed.")
		quit(0)
		return

	for failure in _failures:
		push_error(failure)
	quit(1)
