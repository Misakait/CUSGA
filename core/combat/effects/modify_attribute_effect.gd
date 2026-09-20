extends "res://core/combat/effects/card_effect.gd"

## 属性修改效果的生产 GDScript 实现。
##
## 字段与默认值同旧 C# ModifyAttributeEffect；行为只做一件事：把固定加成写入目标属性
## 组件的永久加成，并保持旧的日志文本与警告时机。脚本不声明 class_name，避免与仍在
## 使用的 C# ModifyAttributeEffect 全局类型重名。

## 属性组件固定挂载路径，与旧 C# 实现一致。
const ATTRIBUTE_COMPONENT_PATH: String = "Components/AttributeComponent"

## 属性枚举的显示名，顺序与 C# AttributeType 完全一致，仅用于保持旧日志文本。
const ATTRIBUTE_NAMES: Array[String] = [
	"PhysAtk", "PhysDef", "MagPower", "MagResist", "Speed", "MaxHealth", "MaxEnergy",
	"FixedPhysPenetration", "PhysPenetrationRate", "FixedMagicPenetration",
	"MagicPenetrationRate", "CritRate", "CritDamage", "EvasionRate", "LifestealRate",
]

## 需要修改的属性枚举整数，沿用旧 C# 默认值 Speed。
@export var TargetAttribute: int = 4

## 固定加成数值，沿用旧 C# 默认值 20.0。
@export var Amount: float = 20.0

## 效果目标范围，沿用旧 C# 默认值 PrimaryOnly。
@export var TargetScope: int = SCOPE_PRIMARY_ONLY


## 执行属性修改效果。
##
## @param context 技能执行上下文，允许旧 C# SkillExecutionContext。
## @return 无。
func Execute(context: RefCounted) -> void:
	if context == null:
		push_error("ModifyAttributeEffect executed with null context.")
		return

	var source: Node = context.get("Source")
	for target: Node in _select_scope_nodes(context, TargetScope):
		if target == null:
			continue

		var attribute_component: Node = target.get_node_or_null(ATTRIBUTE_COMPONENT_PATH)
		if attribute_component == null:
			push_warning("Target '%s' has no AttributeComponent." % target.name)
			continue

		attribute_component.call("AddPermanentBonus", TargetAttribute, Amount, source)
		print("[修改属性效果] %s 使 %s 的 %s 增加了 %s 点" % [
			source.name,
			target.name,
			_attribute_name(TargetAttribute),
			_format_amount(Amount),
		])
		var effective: Variant = attribute_component.call("GetEffectiveValue", TargetAttribute)
		print("✅ 修改后 %s 的 %s = %s" % [
			target.name,
			_attribute_name(TargetAttribute),
			_format_amount(float(effective)),
		])


## 返回属性枚举的显示名，保持旧 C# 枚举格式化文本。
##
## @param attribute_type 属性枚举整数。
## @return 枚举名称；越界时回退为数字文本。
func _attribute_name(attribute_type: int) -> String:
	if attribute_type >= 0 and attribute_type < ATTRIBUTE_NAMES.size():
		return ATTRIBUTE_NAMES[attribute_type]
	return str(attribute_type)


## 格式化数值文本，保持旧 C# 浮点打印形式（整数不带小数位）。
##
## @param value 待格式化数值。
## @return 去掉多余小数位的文本。
func _format_amount(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(int(roundf(value)))
	return str(value)
