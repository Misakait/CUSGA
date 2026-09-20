extends RefCounted

## 单段伤害进入接收者前的修正上下文，等价迁移自
## core/combat/effects/DamageEffectSegmentContext.cs。
##
## 每段伤害在创建载荷之前都会带上「本段序号 / 本次总段数 / 选中目标」，
## 让每段伤害修正状态（例如 NextAttackDamageBonusStatusInstance）按层数加值，
## 同时保留表现层需要的段号信息。字段名与旧 C# 逐字一致。
## 不声明 class_name，避免与仍在使用的 C# 全局类型重名。

## 本次技能的施放者。
var Source: Node = null
## 本次技能执行上下文。
var SkillContext: Variant = null
## 正在结算的伤害效果资源。
var Effect: Resource = null
## 本段伤害选中的目标（通常是目标选择字典，保持旧 C# Variant 语义）。
var Target: Variant = null
## 本段伤害的零基序号。
var HitIndex: int = 0
## 本次伤害效果修正后的总段数。
var EffectiveHitCount: int = 1


## 构造单段伤害修正上下文。
##
## @param source 本次技能的施放者。
## @param skill_context 本次技能执行上下文。
## @param effect 正在结算的伤害效果。
## @param target 本段伤害选中的目标。
## @param hit_index 本段伤害的零基序号。
## @param effective_hit_count 本次伤害效果修正后的总段数。
## @return 无返回值。
func _init(
	source: Node,
	skill_context: Variant,
	effect: Resource,
	target: Variant,
	hit_index: int,
	effective_hit_count: int
) -> void:
	Source = source
	SkillContext = skill_context
	Effect = effect
	Target = target
	HitIndex = hit_index
	EffectiveHitCount = effective_hit_count
