extends "res://core/combat/status/status_effect_instance.gd"

## 属性变化拦截状态实例的生产 GDScript 实现，
## 等价迁移自 C# AttributeChangeGuardStatusInstance。
##
## 属性组件已迁移到 GDScript，上下文按 Type / OldValue / Delta / NewValue 字段协议与
## Cancel / MatchesDirection 方法协议读写，因此本实现同时兼容 GDScript 与旧 C# 上下文载体。
## 脚本不声明 class_name，避免与 C# 类型表里的同名全局类冲突。

## 状态数据字段名，与旧 C# AttributeChangeGuardStatusData 属性逐字一致。
const FIELD_TARGET_ATTRIBUTE: StringName = &"TargetAttribute"
const FIELD_DIRECTION: StringName = &"Direction"
const FIELD_CANCEL_CHANGE: StringName = &"CancelChange"
const FIELD_DELTA_MULTIPLIER: StringName = &"DeltaMultiplier"
const FIELD_ENABLE_MIN_VALUE: StringName = &"EnableMinValue"
const FIELD_MIN_VALUE: StringName = &"MinValue"
const FIELD_ENABLE_MAX_VALUE: StringName = &"EnableMaxValue"
const FIELD_MAX_VALUE: StringName = &"MaxValue"

## 属性变化上下文字段名。
const CONTEXT_FIELD_TYPE: StringName = &"Type"
const CONTEXT_FIELD_OLD_VALUE: StringName = &"OldValue"
const CONTEXT_FIELD_DELTA: StringName = &"Delta"
const CONTEXT_FIELD_NEW_VALUE: StringName = &"NewValue"

## 属性变化上下文方法名。
const CONTEXT_METHOD_MATCHES_DIRECTION: StringName = &"MatchesDirection"
const CONTEXT_METHOD_CANCEL: StringName = &"Cancel"


## 属性变化前按配置改写或取消本次变化。
##
## @param context 属性变化上下文（GDScript 生产实现或旧 C# 垫片）。
## @return 无。
func OnBeforeAttributeChange(context: Variant) -> void:
	var context_object: Object = context as Object
	if context_object == null:
		return

	if _field_int(context_object, CONTEXT_FIELD_TYPE) != _read_int(FIELD_TARGET_ATTRIBUTE):
		return

	if not _context_matches_direction(context_object):
		return

	# 取消优先级高于改写：配置为取消时不再计算 NewValue，避免无意义的中间值写回。
	if _read_bool(FIELD_CANCEL_CHANGE):
		context_object.call(CONTEXT_METHOD_CANCEL)
		return

	var new_value: float = (
		_field_float(context_object, CONTEXT_FIELD_OLD_VALUE)
		+ _field_float(context_object, CONTEXT_FIELD_DELTA) * _read_float(FIELD_DELTA_MULTIPLIER)
	)

	if _read_bool(FIELD_ENABLE_MIN_VALUE):
		new_value = maxf(new_value, _read_float(FIELD_MIN_VALUE))

	if _read_bool(FIELD_ENABLE_MAX_VALUE):
		new_value = minf(new_value, _read_float(FIELD_MAX_VALUE))

	context_object.set(CONTEXT_FIELD_NEW_VALUE, new_value)


## 询问属性变化上下文本次变化方向是否命中配置。
##
## @param context_object 属性变化上下文对象。
## @return 命中方向时返回 true；上下文缺少方向协议时返回 false。
func _context_matches_direction(context_object: Object) -> bool:
	if not context_object.has_method(CONTEXT_METHOD_MATCHES_DIRECTION):
		push_error("属性变化上下文缺少方向判定协议：%s" % CONTEXT_METHOD_MATCHES_DIRECTION)
		return false

	return bool(context_object.call(CONTEXT_METHOD_MATCHES_DIRECTION, _read_int(FIELD_DIRECTION)))
