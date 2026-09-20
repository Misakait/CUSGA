extends "res://core/combat/status/status_effect_instance.gd"

## 运行时每段基础伤害修正状态实例的生产 GDScript 实现，
## 等价迁移自 C# NextAttackDamageBonusStatusInstance。
##
## 在伤害载荷创建前按“每层每段固定加成 × 当前层数”提高本段基础伤害；AttackSkillUses > 0 时
## 属于限次模式，每次攻击技能完整执行后消耗一次，剩余次数归零后不再生效。
## 脚本不声明 class_name，避免与 C# 类型表里的同名全局类冲突。

## 状态数据字段名，与旧 C# NextAttackDamageBonusStatusData 属性逐字一致。
const FIELD_FLAT_SEGMENT_DAMAGE_BONUS_PER_STACK: StringName = &"FlatSegmentDamageBonusPerStack"
const FIELD_ATTACK_SKILL_USES: StringName = &"AttackSkillUses"

## 技能执行上下文字段与方法名（旧 C# SkillExecutionModifierContext）。
const CONTEXT_FIELD_IS_ATTACK_SKILL: StringName = &"IsAttackSkill"
const CONTEXT_METHOD_MARK_STATUS_FOR_CONSUMPTION: StringName = &"MarkStatusForConsumption"

## 限次模式下剩余可影响的攻击技能次数。
var _remaining_attack_skill_uses: int = 0


## 构造每段伤害修正实例，并从状态数据读取限次上限作为初始剩余次数。
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


## 根据当前层数修正单段伤害载荷中的基础伤害。
##
## @param _context 单段伤害修正上下文（旧 C# DamageEffectSegmentContext）。
## @param damage 当前本段基础伤害候选值。
## @return 修正后的本段基础伤害；不满足条件时原样返回。
func OnModifyDamageEffectSegmentDamage(_context: Variant, damage: int) -> int:
	var flat_bonus: int = _read_int(FIELD_FLAT_SEGMENT_DAMAGE_BONUS_PER_STACK)
	if flat_bonus == 0:
		return damage

	if _read_int(FIELD_ATTACK_SKILL_USES) > 0 and _remaining_attack_skill_uses <= 0:
		return damage

	return damage + flat_bonus * CurrentStacks


## 攻击技能完整执行后标记限次基础伤害状态需要扣减一次。
##
## @param context 本次技能执行修正上下文（旧 C# SkillExecutionModifierContext）。
## @return 无。
func OnAfterSkillExecution(context: Variant) -> void:
	if _read_int(FIELD_ATTACK_SKILL_USES) <= 0 or not _field_bool(
		context,
		CONTEXT_FIELD_IS_ATTACK_SKILL
	):
		return

	_mark_status_for_consumption(context, Id)


## 扣减一次限次基础伤害状态，并在剩余次数归零时要求移除状态。
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
