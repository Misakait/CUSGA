extends RefCounted

## 技能效果目标范围解析的生产 GDScript 实现，等价迁移自 C# SkillEffectTargetScopeUtility。
##
## 旧 C# 用 `yield return` 惰性枚举，GDScript 侧改为一次性返回数组——调用方在本项目里都是
## 立即遍历，语义等价且避免跨语言迭代器。判定规则逐条对齐旧 C#：
##   Source          → 只返回施放者自身（来源为空则空结果）
##   AllTargets      → 所有 Unit 非空的目标
##   PrimaryOnly     → Unit 非空且 IsPrimary
##   SecondaryOnly   → Unit 非空且 IsSecondary
##   其它取值        → 空结果
## 不声明 class_name，避免与仍在使用的 C# 全局类型重名。

## 目标范围枚举整数，取值与 C# SkillEffectTargetScope 逐字一致。
const SCOPE_SOURCE: int = 0
const SCOPE_ALL_TARGETS: int = 1
const SCOPE_PRIMARY_ONLY: int = 2
const SCOPE_SECONDARY_ONLY: int = 3

## 目标选择条目脚本路径。
const SELECTION_SCRIPT_PATH: String = \
	"res://core/combat/effects/skill_effect_target_selection.gd"


## 按范围解析技能效果目标，等价旧 C# SelectTargets。
##
## @param context 技能执行上下文（旧 C# SkillExecutionContext 或 skill_execution_context.gd）。
## @param scope 目标范围枚举整数。
## @return 目标选择条目数组，顺序与上下文中的目标顺序一致。
static func SelectTargets(context: Variant, scope: int) -> Array:
	var selections: Array = []
	if context == null:
		return selections

	var context_object: Object = context as Object
	if context_object == null:
		return selections

	var source: Node = context_object.get("Source") as Node
	if scope == SCOPE_SOURCE:
		if source != null:
			selections.append(_selection_script().FromSource(source))
		return selections

	var targets: Variant = context_object.get("Targets")
	if not (targets is Array):
		return selections

	for target: Variant in targets:
		var target_object: Object = target as Object
		if target_object == null:
			continue

		var unit: Node = target_object.get("Unit") as Node
		if unit == null:
			continue

		if not _scope_matches(target_object, scope):
			continue

		selections.append(_selection_script().FromTarget(target_object))

	return selections


## 按范围解析技能效果目标节点，等价旧 C# SelectNodes。
##
## @param context 技能执行上下文。
## @param scope 目标范围枚举整数。
## @return 命中的目标节点数组。
static func SelectNodes(context: Variant, scope: int) -> Array[Node]:
	var nodes: Array[Node] = []
	for selection: Variant in SelectTargets(context, scope):
		var selection_object: Object = selection as Object
		if selection_object == null:
			continue

		var unit: Node = selection_object.get("Unit") as Node
		if unit != null:
			nodes.append(unit)

	return nodes


## 判断单个上下文目标是否落在指定范围内，等价旧 C# 的 switch 表达式。
##
## @param target 上下文中的目标对象。
## @param scope 目标范围枚举整数。
## @return 命中时返回 true。
static func _scope_matches(target: Object, scope: int) -> bool:
	match scope:
		SCOPE_ALL_TARGETS:
			return true
		SCOPE_PRIMARY_ONLY:
			return bool(target.get("IsPrimary"))
		SCOPE_SECONDARY_ONLY:
			return bool(target.get("IsSecondary"))
		_:
			return false


## 加载目标选择条目脚本，供两个静态入口共用。
##
## @return 目标选择条目脚本资源。
static func _selection_script() -> Script:
	return load(SELECTION_SCRIPT_PATH)
