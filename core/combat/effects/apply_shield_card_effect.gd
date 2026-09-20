extends "res://core/combat/effects/card_effect.gd"

## 护盾施加效果的生产 GDScript 实现。
##
## 字段、默认值与旧 C# ApplyShieldCardEffect 一致；护盾实例仍由保留的状态数据资源
## 创建（C# ShieldStatusData.CreateInstance），本脚本只负责按目标范围分发。
## 脚本不声明 class_name，避免与仍在使用的 C# ApplyShieldCardEffect 全局类型重名。

## 护盾状态数据资源；旧 C# ShieldStatusData 与后续 GDScript 实现都可以。
@export var ShieldStatus: Resource

## 效果目标范围，沿用旧 C# 默认值 AllTargets。
@export var TargetScope: int = SCOPE_ALL_TARGETS


## 执行护盾施加效果。
##
## @param context 技能执行上下文，允许旧 C# SkillExecutionContext。
## @return 无。
func Execute(context: RefCounted) -> void:
	if context == null:
		push_error("ApplyShieldCardEffect executed with null context.")
		return

	if ShieldStatus == null:
		push_error("ApplyShieldCardEffect has no ShieldStatus assigned.")
		return

	var source: Node = context.get("Source")
	for target: Node in _select_scope_nodes(context, TargetScope):
		var status_component := _find_status_component(target)
		if status_component == null:
			push_error("Target '%s' has no StatusComponent." % target.name)
			continue

		var shield_amount: Variant = ShieldStatus.get("DefaultShieldAmount")
		var instance: Variant = ShieldStatus.call(
			"CreateInstance",
			source,
			target,
			shield_amount
		)
		status_component.call("AddStatus", instance)
