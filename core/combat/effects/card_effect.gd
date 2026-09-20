extends Resource

## 战斗效果的生产 GDScript 基类。
##
## 旧 C# CardEffect 是抽象 Resource，只声明 Execute(SkillExecutionContext)；GDScript 无法
## 继承 C# 脚本，因此这里重新声明一份等价基类，供迁移后的效果脚本继承，并把目标解析、
## 状态组件查找这些跨语言共用逻辑集中在一处。
## 脚本不声明 class_name，避免与仍在使用的 C# CardEffect 全局类型重名。

## 目标范围枚举，取值与 C# SkillEffectTargetScope、skill_effect_target_scope.gd 完全一致。
const SCOPE_SOURCE: int = 0
const SCOPE_ALL_TARGETS: int = 1
const SCOPE_PRIMARY_ONLY: int = 2
const SCOPE_SECONDARY_ONLY: int = 3

## 目标角色枚举，取值与 C# SkillTargetRole、skill_target_role.gd 一致。
const ROLE_PRIMARY: int = 0
const ROLE_SECONDARY: int = 1

## 目标范围解析的生产实现；效果脚本不再各自复制一份判定规则，避免两种语言三份实现漂移。
const SCOPE_UTILITY: GDScript = \
	preload("res://core/combat/effects/skill_effect_target_scope_utility.gd")

## 记忆内的状态组件查找路径，顺序与 C# ComponentLookup 保持一致。
const STATUS_COMPONENT_PATHS: Array[String] = [
	"StatusComponent",
	"Components/StatusComponent",
]


## 执行效果。
##
## 旧 C# 抽象方法无法被 GDScript 覆盖，因此基类只保留协议与诊断；具体效果脚本必须
## 覆盖该方法。缺少实现时立即报错，避免静默丢功能。
##
## @param _context 技能执行上下文，允许旧 C# SkillExecutionContext。
## @return 无。
func Execute(_context: RefCounted) -> void:
	push_error("%s 未实现 Execute。" % _effect_name())


## 按旧 C# SkillEffectTargetScopeUtility 的规则解析效果目标。
##
## 返回值用字典描述，字段与 C# SkillEffectTargetSelection 对齐（Unit / Role /
## IsSource / IsPrimary / IsSecondary），避免 GDScript 侧构造 C# 结构体。
##
## @param context 技能执行上下文，可为空。
## @param scope 目标范围枚举整数。
## @return 目标选择字典数组，顺序与上下文中的目标顺序一致。
func _select_scope_targets(context: RefCounted, scope: int) -> Array[Dictionary]:
	var selections: Array[Dictionary] = []
	for selection: Variant in SCOPE_UTILITY.SelectTargets(context, scope):
		selections.append(_make_selection(
			selection.Unit,
			selection.Role,
			selection.IsSource
		))
	return selections


## 只返回节点数组，保持旧 C# SelectNodes 的调用语义。
##
## @param context 技能执行上下文，可为空。
## @param scope 目标范围枚举整数。
## @return 命中的目标节点数组。
func _select_scope_nodes(context: RefCounted, scope: int) -> Array[Node]:
	var nodes: Array[Node] = []
	for selection: Dictionary in _select_scope_targets(context, scope):
		nodes.append(selection["Unit"])
	return nodes


## 构造目标选择字典。
##
## @param unit 目标节点。
## @param role 目标角色枚举整数。
## @param is_source 是否为施放者自身。
## @return 描述单次目标选择的字典。
func _make_selection(unit: Node, role: int, is_source: bool) -> Dictionary:
	return {
		"Unit": unit,
		"Role": role,
		"IsSource": is_source,
		"IsPrimary": not is_source and role == ROLE_PRIMARY,
		"IsSecondary": not is_source and role == ROLE_SECONDARY,
	}


## 查找实体上的状态组件，兼容旧场景的直接子节点与 Components 容器结构。
##
## @param owner 持有组件的实体节点，可为空。
## @return 具备 AddStatus 协议的状态组件节点；缺失时返回 null。
func _find_status_component(owner: Node) -> Object:
	if owner == null or not is_instance_valid(owner):
		return null
	for path: String in STATUS_COMPONENT_PATHS:
		var node: Node = owner.get_node_or_null(path)
		if node != null and node.has_method("AddStatus"):
			return node
	var unique_node: Node = owner.get_node_or_null("%StatusComponent")
	if unique_node != null:
		return unique_node
	return null


## 返回效果脚本名，供诊断信息保持旧 C# nameof 风格。
##
## @return 不含路径与扩展名的脚本文件名。
func _effect_name() -> String:
	return get_script().resource_path.get_file().get_basename()
