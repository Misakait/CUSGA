extends RefCounted

## 伤害段数修正 Hook 的上下文，等价迁移自
## core/combat/effects/DamageEffectHitCountContext.cs。
##
## 段数修正状态（例如 HitCountModifierStatusInstance）需要同时看到
## 本次技能上下文、正在计算段数的效果与效果上配置的原始段数，才能判断
## 「只给多段效果加段」与「限次模式下是否已真正修正过」。
## 字段名与旧 C# 逐字一致，两种语言的状态实例都按字段协议读取。
## 不声明 class_name，避免与仍在使用的 C# 全局类型重名。

## 本次技能的施放者。
var Source: Node = null
## 本次技能执行上下文。
var SkillContext: Variant = null
## 正在计算段数的伤害效果资源。
var Effect: Resource = null
## 伤害效果资源上配置的原始段数。
var BaseHitCount: int = 1


## 构造段数修正上下文。
##
## @param source 本次技能的施放者。
## @param skill_context 本次技能执行上下文。
## @param effect 正在计算段数的伤害效果。
## @param base_hit_count 伤害效果资源上配置的原始段数。
## @return 无返回值。
func _init(
	source: Node, skill_context: Variant, effect: Resource, base_hit_count: int
) -> void:
	Source = source
	SkillContext = skill_context
	Effect = effect
	BaseHitCount = base_hit_count
