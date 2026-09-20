extends "res://core/combat/status/status_effect_instance.gd"

## 属性修正状态实例的生产 GDScript 实现，等价迁移自 C# AttributeModifierStatusInstance。
##
## 修正条目容器可能是旧 C# AttributeModifierStatusData 垫片或 GDScript 生产数据，
## 条目本身也可能是旧 C# 垫片或 GDScript 生产实现，因此统一按字段名读取，
## 行为与旧 C# AttributeModifierDataProtocol.TryRead 的默认值（PhysAtk / FlatAdd / 0）一致。
## 脚本不声明 class_name，避免与 C# 类型表里的同名全局类冲突。

## 状态数据上的修正条目容器字段名。
const FIELD_MODIFIERS: StringName = &"Modifiers"

## 修正条目字段名，与旧 C# AttributeModifierData 属性逐字一致。
const MODIFIER_FIELD_TYPE: StringName = &"Type"
const MODIFIER_FIELD_MODE: StringName = &"Mode"
const MODIFIER_FIELD_VALUE_PER_STACK: StringName = &"ValuePerStack"


## 返回属性修正条目，供属性组件按跨语言字典协议消费。
##
## @return 条目字典数组，字段为 Type / Mode / ValuePerStack / Stacks / SourceId，
## 与旧 C# AttributeModifierDataProtocol.ToDictionary 的键名逐字一致。
func GetAttributeModifiers() -> Array:
	var result: Array = []

	for raw_modifier: Variant in _read_array(FIELD_MODIFIERS):
		# 旧 C# 协议只接受 Resource 条目，非资源条目按原行为静默跳过。
		var modifier: Resource = raw_modifier as Resource
		if modifier == null:
			continue

		result.append({
			"Type": _field_int(modifier, MODIFIER_FIELD_TYPE),
			"Mode": _field_int(modifier, MODIFIER_FIELD_MODE),
			"ValuePerStack": _field_float(modifier, MODIFIER_FIELD_VALUE_PER_STACK),
			"Stacks": CurrentStacks,
			"SourceId": Id,
		})

	return result
