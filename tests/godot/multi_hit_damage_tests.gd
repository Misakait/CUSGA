extends SceneTree

const DAMAGE_EFFECT_SCRIPT := "res://core/combat/effects/DamageEffect.cs"
const COMBAT_SKILL_SCRIPT := "res://core/combat/skills/CombatSkillData.cs"
const CONTEXT_SCRIPT := "res://core/combat/skills/SkillExecutionContext.cs"
const HEALTH_SCRIPT := "res://entities/components/HealthComponent.cs"
const DAMAGE_RECEIVER_SCRIPT := "res://entities/components/DamageReceiverComponent.cs"
const STATUS_COMPONENT_SCRIPT := "res://entities/components/StatusComponent.cs"
const HIT_COUNT_STATUS_SCRIPT := "res://core/combat/buffs/HitCountModifierStatusData.cs"
const NEXT_ATTACK_DAMAGE_STATUS_SCRIPT := "res://core/combat/buffs/NextAttackDamageBonusStatusData.cs"

const DAMAGE_TYPE_REAL := 2
const ELEMENT_NONE := 0
const HIT_TARGET_MODE_RANDOM_CANDIDATE_PER_HIT := 1

var _failures: Array[String] = []
var _created_nodes: Array[Node] = []


func _init() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_test_fixed_target_hit_count()
	_test_random_candidate_mode_filters_dead_targets()
	_test_hit_count_status_uses_configured_attack_skill_count()
	_test_next_attack_damage_status_applies_to_every_segment()
	_test_non_attack_skill_does_not_consume_attack_skill_status()

	_finish()


func _test_fixed_target_hit_count() -> void:
	var source := _create_combat_entity("Source", 100, true)
	var target := _create_combat_entity("Target", 100, false)
	var damage_events: Array[int] = []
	_health(target).DamageTaken.connect(func(amount: int, _element_type: int) -> void:
		damage_events.append(amount)
	)
	var effect = _create_real_damage_effect(10, 3)
	var context = _context_script().FromSingleTarget(source, target, [target])

	effect.Execute(context)

	_assert(_health(target).CurrentValue == 70, "固定目标 3 段 10 点伤害应扣除 30 点生命。")
	_assert(damage_events.size() == 3, "固定目标 3 段伤害应产生 3 次独立 DamageTaken 事件。")
	_assert(damage_events.all(func(amount: int) -> bool: return amount == 10), "每段 DamageTaken 事件应保留独立的 10 点伤害。")


func _test_random_candidate_mode_filters_dead_targets() -> void:
	var source := _create_combat_entity("Source", 100, true)
	var dead_target := _create_combat_entity("DeadTarget", 1, false)
	var alive_target := _create_combat_entity("AliveTarget", 100, false)
	_health(dead_target).TakeDamage(1, ELEMENT_NONE)
	var effect = _create_real_damage_effect(10, 3)
	effect.HitTargetMode = HIT_TARGET_MODE_RANDOM_CANDIDATE_PER_HIT
	var context = _context_script().FromSingleTarget(
		source,
		dead_target,
		[dead_target, alive_target]
	)

	effect.Execute(context)

	_assert(_health(alive_target).CurrentValue == 70, "随机候选模式应过滤 0 血目标并命中仍存活目标。")
	_assert(_health(dead_target).CurrentValue == 0, "0 血候选目标不应继续受到伤害。")


func _test_hit_count_status_uses_configured_attack_skill_count() -> void:
	var source := _create_combat_entity("Source", 100, true)
	var target := _create_combat_entity("Target", 100, false)
	var status = load(HIT_COUNT_STATUS_SCRIPT).new()
	status.Id = &"hit_count_plus_two_two_uses"
	status.FlatHitCountBonusPerStack = 2
	status.AttackSkillUses = 2
	_status(source).AddStatus(status.CreateInstance(source, source))

	var non_attack_skill = load(COMBAT_SKILL_SCRIPT).new()
	var attack_skill = _create_combat_skill([_create_real_damage_effect(1, 1)])
	var context = _context_script().FromSingleTarget(source, target, [target])

	non_attack_skill.Execute(context)
	attack_skill.Execute(context)
	attack_skill.Execute(context)
	attack_skill.Execute(context)

	_assert(_health(target).CurrentValue == 93, "段数限次 Buff 应只影响前两张攻击牌。")
	_assert(not _status(source).HasStatus(status.Id), "段数限次 Buff 用完配置次数后应移除。")


func _test_next_attack_damage_status_applies_to_every_segment() -> void:
	var source := _create_combat_entity("Source", 100, true)
	var target := _create_combat_entity("Target", 200, false)
	var status = load(NEXT_ATTACK_DAMAGE_STATUS_SCRIPT).new()
	status.Id = &"next_two_attack_damage_plus_ten"
	status.FlatSegmentDamageBonusPerStack = 10
	status.AttackSkillUses = 2
	_status(source).AddStatus(status.CreateInstance(source, source))

	var attack_skill = _create_combat_skill([_create_real_damage_effect(1, 5)])
	var context = _context_script().FromSingleTarget(source, target, [target])

	attack_skill.Execute(context)
	attack_skill.Execute(context)
	attack_skill.Execute(context)

	_assert(_health(target).CurrentValue == 85, "每段基础伤害限次 Buff 应覆盖前两张攻击牌的全部 5 段。")
	_assert(not _status(source).HasStatus(status.Id), "每段基础伤害限次 Buff 用完配置次数后应移除。")


func _test_non_attack_skill_does_not_consume_attack_skill_status() -> void:
	var source := _create_combat_entity("Source", 100, true)
	var target := _create_combat_entity("Target", 100, false)
	var status = load(NEXT_ATTACK_DAMAGE_STATUS_SCRIPT).new()
	status.Id = &"next_attack_damage_plus_ten"
	status.FlatSegmentDamageBonusPerStack = 10
	status.AttackSkillUses = 1
	_status(source).AddStatus(status.CreateInstance(source, source))

	var non_attack_skill = load(COMBAT_SKILL_SCRIPT).new()
	var context = _context_script().FromSingleTarget(source, target, [target])

	non_attack_skill.Execute(context)

	_assert(_status(source).HasStatus(status.Id), "没有 DamageEffect 的技能不应消耗攻击牌限次 Buff。")


func _create_real_damage_effect(base_damage: int, hit_count: int):
	var effect = load(DAMAGE_EFFECT_SCRIPT).new()
	effect.BaseDamage = base_damage
	effect.HitCount = hit_count
	effect.Type = DAMAGE_TYPE_REAL
	effect.Element = ELEMENT_NONE
	return effect


func _create_combat_skill(effects: Array):
	var skill = load(COMBAT_SKILL_SCRIPT).new()
	for effect in effects:
		skill.Effects.append(effect)
	return skill


func _create_combat_entity(entity_name: String, max_health: int, with_status: bool) -> Node:
	var entity := Node.new()
	entity.name = entity_name
	_created_nodes.append(entity)
	var components := Node.new()
	components.name = "Components"
	entity.add_child(components)

	var health = load(HEALTH_SCRIPT).new()
	health.name = "HealthComponent"
	components.add_child(health)
	health.InitializeMax(max_health)

	var receiver = load(DAMAGE_RECEIVER_SCRIPT).new()
	receiver.name = "DamageReceiverComponent"
	receiver.RandomVarianceMin = 1.0
	receiver.RandomVarianceMax = 1.0
	components.add_child(receiver)

	if with_status:
		var status = load(STATUS_COMPONENT_SCRIPT).new()
		status.name = "StatusComponent"
		components.add_child(status)

	return entity


func _context_script():
	return load(CONTEXT_SCRIPT)


func _health(entity: Node):
	return entity.get_node("Components/HealthComponent")


func _status(entity: Node):
	return entity.get_node("Components/StatusComponent")


func _assert(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	for node in _created_nodes:
		if is_instance_valid(node):
			node.free()

	if _failures.is_empty():
		print("All multi-hit damage Godot tests passed.")
		quit(0)
		return

	for failure in _failures:
		push_error(failure)
	quit(1)
