extends "res://core/combat/effects/card_effect.gd"

## 状态施加效果的生产 GDScript 实现。
##
## 字段、默认值与旧 C# ApplyStatusCardEffect 一致；状态实例仍由保留的状态数据资源创建
## （C# StatusEffectData.CreateInstance），本脚本只按目标范围分发。注意旧实现对空上下文
## 不做检查，因此这里同样只在缺少状态资源时报错，保持诊断行为不变。
## 脚本不声明 class_name，避免与仍在使用的 C# ApplyStatusCardEffect 全局类型重名。

## 状态数据资源；旧 C# StatusEffectData 派生物与后续 GDScript 实现都可以。
@export var Status: Resource

## 效果目标范围，沿用旧 C# 默认值 AllTargets。
@export var TargetScope: int = SCOPE_ALL_TARGETS


## 执行状态施加效果。
##
## @param context 技能执行上下文，允许旧 C# SkillExecutionContext。
## @return 无。
func Execute(context: RefCounted) -> void:
	if Status == null:
		push_error("ApplyStatusCardEffect has no Status assigned.")
		return

	var source: Node = context.get("Source") if context != null else null
	for target: Node in _select_scope_nodes(context, TargetScope):
		var status_component := _find_status_component(target)
		if status_component == null:
			push_error("Target '%s' has no StatusComponent." % target.name)
			continue

		var instance: Variant = Status.call("CreateInstance", source, target)
		status_component.call("AddStatus", instance)
