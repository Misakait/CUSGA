extends "res://core/combat/status/status_effect_instance.gd"

## 属性变化触发状态实例的生产 GDScript 实现，
## 等价迁移自 C# AttributeChangeTriggerStatusInstance。
##
## 属性提交后按 Type / Source 字段协议与 MatchesDirection 方法协议判定是否触发，再把配置的
## 效果逐条放进“仅施法者对拥有者”的技能执行上下文里执行；执行期间用 _is_executing 做重入保护，
## 避免效果本身再改属性导致无限递归。脚本不声明 class_name，避免与 C# 全局类型重名。

## 状态数据字段名，与旧 C# AttributeChangeTriggerStatusData 属性逐字一致。
const FIELD_TARGET_ATTRIBUTE: StringName = &"TargetAttribute"
const FIELD_DIRECTION: StringName = &"Direction"
const FIELD_EFFECTS: StringName = &"Effects"

## 属性变化上下文字段名与方法名。
const CONTEXT_FIELD_TYPE: StringName = &"Type"
const CONTEXT_FIELD_SOURCE: StringName = &"Source"
const CONTEXT_METHOD_MATCHES_DIRECTION: StringName = &"MatchesDirection"

## 效果执行协议方法名与技能执行上下文脚本路径（上下文已是 GDScript 生产实现）。
const EFFECT_EXECUTE_METHOD: StringName = &"Execute"
const EXECUTION_CONTEXT_SCRIPT_PATH: String = \
	"res://core/combat/skills/skill_execution_context.gd"

## 是否正在执行触发效果，用于重入保护。
var _is_executing: bool = false


## 属性变化后触发配置效果。
##
## @param context 属性变化上下文（GDScript 生产实现或旧 C# 垫片）。
## @return 无。
func OnAfterAttributeChanged(context: Variant) -> void:
	if _is_executing:
		return

	var context_object: Object = context as Object
	if context_object == null:
		return

	if _field_int(context_object, CONTEXT_FIELD_TYPE) != _read_int(FIELD_TARGET_ATTRIBUTE):
		return

	if not _context_matches_direction(context_object):
		return

	var effects: Array = _read_array(FIELD_EFFECTS)
	if effects.is_empty():
		return

	_is_executing = true

	for raw_effect: Variant in effects:
		var effect: Resource = raw_effect as Resource
		if effect == null:
			continue

		var change_source: Node = _field_value(context_object, CONTEXT_FIELD_SOURCE) as Node
		var effect_context: RefCounted = _build_single_target_context(
			_resolve_change_source(change_source),
			Owner
		)
		_execute_effect(effect, effect_context)

	_is_executing = false


## 解析触发效果使用的来源节点，回落顺序与旧 C# 的 changeSource ?? Source ?? Owner 一致。
##
## @param change_source 属性变化上下文提供的来源节点。
## @return 最终使用的来源节点。
func _resolve_change_source(change_source: Node) -> Node:
	if change_source != null:
		return change_source
	if Source != null:
		return Source
	return Owner


## 构造“仅来源对拥有者”的技能执行上下文。
##
## @param effect_source 本次效果的来源节点。
## @param target 本次效果的目标节点。
## @return 技能执行上下文；上下文脚本缺失时返回 null。
func _build_single_target_context(effect_source: Node, target: Node) -> RefCounted:
	var context_script: Script = load(EXECUTION_CONTEXT_SCRIPT_PATH)
	if context_script == null:
		push_error("SkillExecutionContext script is missing: %s" % EXECUTION_CONTEXT_SCRIPT_PATH)
		return null

	return context_script.FromSingleTarget(effect_source, target)


## 执行单条触发效果。
##
## @param effect 效果资源（GDScript 生产实现或旧 C# 垫片）。
## @param context 技能执行上下文。
## @return 无。
func _execute_effect(effect: Resource, context: RefCounted) -> void:
	if context == null:
		return

	if not effect.has_method(EFFECT_EXECUTE_METHOD):
		push_error("效果 '%s' 缺少 Execute 协议，已跳过。" % effect.resource_path)
		return

	effect.call(EFFECT_EXECUTE_METHOD, context)


## 询问属性变化上下文本次变化方向是否命中配置。
##
## @param context_object 属性变化上下文对象。
## @return 命中方向时返回 true；上下文缺少方向协议时返回 false。
func _context_matches_direction(context_object: Object) -> bool:
	if not context_object.has_method(CONTEXT_METHOD_MATCHES_DIRECTION):
		push_error("属性变化上下文缺少方向判定协议：%s" % CONTEXT_METHOD_MATCHES_DIRECTION)
		return false

	return bool(context_object.call(CONTEXT_METHOD_MATCHES_DIRECTION, _read_int(FIELD_DIRECTION)))
