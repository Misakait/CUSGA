extends "res://core/combat/status/status_effect_instance.gd"

## 段数修正状态实例的生产 GDScript 实现，等价迁移自 C# HitCountModifierStatusInstance。
##
## 段数修正在伤害效果进入段数循环前生效，只对本身就是多段（基础段数 > 1）的效果加段；
## 限次模式下必须“真的修正过一次多段伤害”才允许消耗一次使用次数，因此用 _modified_skill_contexts
## 记录被改过的技能执行上下文（按引用比较，等价旧 C# HashSet<SkillExecutionContext>）。
## 脚本不声明 class_name，避免与 C# 类型表里的同名全局类冲突。

## 状态数据字段名，与旧 C# HitCountModifierStatusData 属性逐字一致。
const FIELD_FLAT_HIT_COUNT_BONUS_PER_STACK: StringName = &"FlatHitCountBonusPerStack"
const FIELD_ATTACK_SKILL_USES: StringName = &"AttackSkillUses"

## 段数修正上下文字段名（旧 C# DamageEffectHitCountContext 属性）。
const CONTEXT_FIELD_BASE_HIT_COUNT: StringName = &"BaseHitCount"
const CONTEXT_FIELD_SKILL_CONTEXT: StringName = &"SkillContext"

## 技能执行上下文字段与方法名（旧 C# SkillExecutionModifierContext）。
const CONTEXT_FIELD_IS_ATTACK_SKILL: StringName = &"IsAttackSkill"
const CONTEXT_METHOD_MARK_STATUS_FOR_CONSUMPTION: StringName = &"MarkStatusForConsumption"

## 限次模式下剩余可影响的攻击技能次数。
var _remaining_attack_skill_uses: int = 0

## 已被本状态真正修正过的技能执行上下文（按引用保存）。
var _modified_skill_contexts: Array = []


## 构造段数修正实例，并从状态数据读取限次上限作为初始剩余次数。
##
## @param data 状态数据资源（旧 C# 垫片或 GDScript 生产实现）。
## @param source 施加状态的来源节点。
## @param owner 状态的拥有者节点。
## @return 无。
func _init(data: Resource, source: Node, owner: Node) -> void:
	super(data, source, owner)
	_remaining_attack_skill_uses = maxi(0, _read_int(FIELD_ATTACK_SKILL_USES))


## 获取限次模式下剩余可影响的攻击技能次数。
var RemainingAttackSkillUses: int:
	get:
		return _remaining_attack_skill_uses


## 重新施加同一状态时刷新限次状态的剩余攻击技能次数。
##
## @param _incoming 本次新施加进来的同 Id 状态实例。
## @return 无。
func OnReapplied(_incoming: Variant) -> void:
	var uses: int = _read_int(FIELD_ATTACK_SKILL_USES)
	if uses <= 0:
		return

	_remaining_attack_skill_uses = maxi(_remaining_attack_skill_uses, uses)


## 根据当前层数修正伤害效果的有效段数。
##
## @param context 伤害段数修正上下文（旧 C# DamageEffectHitCountContext）。
## @param hit_count 当前有效段数候选值。
## @return 修正后的有效段数；不满足条件时原样返回。
func OnModifyDamageHitCount(context: Variant, hit_count: int) -> int:
	if _field_int(context, CONTEXT_FIELD_BASE_HIT_COUNT) <= 1:
		return hit_count

	var flat_bonus: int = _read_int(FIELD_FLAT_HIT_COUNT_BONUS_PER_STACK)
	if flat_bonus == 0:
		return hit_count

	var uses: int = _read_int(FIELD_ATTACK_SKILL_USES)
	if uses > 0 and _remaining_attack_skill_uses <= 0:
		return hit_count

	var modified_hit_count: int = hit_count + flat_bonus * CurrentStacks

	var skill_context: Variant = _field_value(context, CONTEXT_FIELD_SKILL_CONTEXT)
	if uses > 0 and skill_context != null:
		# 限次段数状态只在本次技能真正修正过多段伤害后才允许消耗。
		if not _modified_skill_contexts.has(skill_context):
			_modified_skill_contexts.append(skill_context)

	return modified_hit_count


## 攻击技能完整执行后标记限次段数状态需要扣减一次。
##
## @param context 本次技能执行修正上下文（旧 C# SkillExecutionModifierContext）。
## @return 无。
func OnAfterSkillExecution(context: Variant) -> void:
	if _read_int(FIELD_ATTACK_SKILL_USES) <= 0 or not _field_bool(
		context,
		CONTEXT_FIELD_IS_ATTACK_SKILL
	):
		return

	var skill_context: Variant = _field_value(context, CONTEXT_FIELD_SKILL_CONTEXT)
	var index: int = _modified_skill_contexts.find(skill_context)
	if index < 0:
		return

	_modified_skill_contexts.remove_at(index)
	_mark_status_for_consumption(context, Id)


## 扣减一次限次段数状态，并在剩余次数归零时要求移除状态。
##
## @return 剩余次数归零时返回 true；否则返回 false。
func ConsumeMarkedSkillExecutionUse() -> bool:
	if _read_int(FIELD_ATTACK_SKILL_USES) <= 0:
		return false

	_remaining_attack_skill_uses = maxi(0, _remaining_attack_skill_uses - 1)
	return _remaining_attack_skill_uses <= 0


## 通过方法协议把状态标记为待消费。
##
## @param context 本次技能执行修正上下文。
## @param status_id 需要标记的状态标识。
## @return 无。
func _mark_status_for_consumption(context: Variant, status_id: StringName) -> void:
	var context_object: Object = context as Object
	if context_object == null:
		return

	if not context_object.has_method(CONTEXT_METHOD_MARK_STATUS_FOR_CONSUMPTION):
		push_error("技能执行上下文缺少限次标记协议：%s" % CONTEXT_METHOD_MARK_STATUS_FOR_CONSUMPTION)
		return

	context_object.call(CONTEXT_METHOD_MARK_STATUS_FOR_CONSUMPTION, status_id)
