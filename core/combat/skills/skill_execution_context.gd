extends RefCounted

## 技能执行上下文的 GDScript 生产实现，等价迁移自 core/combat/skills/SkillExecutionContext.cs。
##
## 迁移的直接动因：旧 C# 的静态工厂（Self / FromSingleTarget / FromPrimaryTargets / FromSpread）
## 无法从 GDScript 调用——`load("...SkillExecutionContext.cs").FromSingleTarget(...)` 会在运行时
## 报 Nonexistent function，而 battle_manager.gd / skill_card.gd /
## attribute_change_trigger_status_instance.gd 都依赖这些工厂。换成 GDScript 后静态函数可以
## 直接在脚本资源上调用，工厂名、参数顺序与字段名保持与旧 C# 逐字一致。
## 不声明 class_name，避免与仍在使用的 C# 全局类型重名。

## 本脚本路径：静态工厂在没有 class_name 的前提下必须靠它构造实例。
const SELF_PATH: String = "res://core/combat/skills/skill_execution_context.gd"
## 目标条目脚本路径。
const TARGET_SCRIPT_PATH: String = "res://core/combat/skills/skill_target.gd"

## 目标角色枚举整数，取值与旧 C# SkillTargetRole 一致。
const ROLE_PRIMARY: int = 0
const ROLE_SECONDARY: int = 1

## 技能施放者。
var Source: Node = null
## 技能目标条目数组，顺序与旧 C# Array<SkillTarget> 一致。
var Targets: Array = []
## 技能开始时锁定的随机候选目标池，等价旧 C# CandidateTargets。
var CandidateTargets: Array[Node] = []


## 构造技能执行上下文。
##
## @param source 技能施放者。
## @param targets 目标条目数组；为空时使用空数组。
## @param candidate_targets 技能开始时锁定的随机候选目标池；为空时使用空数组。
## @return 无返回值。
func _init(source: Node, targets: Array = [], candidate_targets: Variant = null) -> void:
	Source = source
	Targets = targets if targets != null else []
	CandidateTargets = _normalize_candidates(candidate_targets)


## 主目标节点，等价旧 C# PrimaryTarget。
##
## 旧 C# 在 Targets[0] 为 null 时会在读取 Unit 处抛空引用；GDScript 侧改为返回 null，
## 属于更安全的等价处理，不改变任何正常路径行为。
##
## @return 主目标节点；没有目标时返回 null。
var PrimaryTarget: Node:
	get:
		for target: Variant in Targets:
			var target_object: Object = target as Object
			if target_object != null and bool(target_object.get("IsPrimary")):
				return target_object.get("Unit") as Node

		if Targets.is_empty():
			return null

		var first: Object = Targets[0] as Object
		return first.get("Unit") as Node if first != null else null


## 创建以施放者自身为主目标的技能执行上下文。
##
## @param source 技能施放者。
## @param candidate_targets 技能开始时锁定的随机候选目标池。
## @return 以施放者为主目标的技能上下文。
static func Self(source: Node, candidate_targets: Variant = null) -> RefCounted:
	var target_script: Script = load(TARGET_SCRIPT_PATH)
	return load(SELF_PATH).new(
		source,
		[target_script.new(source, ROLE_PRIMARY)],
		candidate_targets
	)


## 创建单目标技能执行上下文。
##
## @param source 技能施放者。
## @param target 技能主目标。
## @param candidate_targets 候选目标池；为空时使用主目标作为候选。
## @return 包含单个主目标的技能上下文。
static func FromSingleTarget(
	source: Node, target: Node, candidate_targets: Variant = null
) -> RefCounted:
	var targets: Array = []
	var target_script: Script = load(TARGET_SCRIPT_PATH)

	if target != null:
		targets.append(target_script.new(target, ROLE_PRIMARY))

	var candidates: Variant = (
		candidate_targets if candidate_targets != null else TargetsToNodes(targets)
	)
	return load(SELF_PATH).new(source, targets, candidates)


## 创建多个主目标的技能执行上下文。
##
## @param source 技能施放者。
## @param target_nodes 主目标节点集合。
## @param candidate_targets 候选目标池；为空时使用主目标集合作为候选。
## @return 包含多个主目标的技能上下文。
static func FromPrimaryTargets(
	source: Node, target_nodes: Variant, candidate_targets: Variant = null
) -> RefCounted:
	var targets: Array = []
	var target_script: Script = load(TARGET_SCRIPT_PATH)

	if target_nodes is Array:
		for node: Variant in target_nodes:
			if node == null:
				continue
			targets.append(target_script.new(node, ROLE_PRIMARY))

	var candidates: Variant = (
		candidate_targets if candidate_targets != null else TargetsToNodes(targets)
	)
	return load(SELF_PATH).new(source, targets, candidates)


## 创建扩散技能执行上下文：主目标排在前，次目标去重后依次追加。
##
## @param source 技能施放者。
## @param primary_target 扩散技能主目标。
## @param secondary_targets 扩散技能次目标集合。
## @param candidate_targets 候选目标池；为空时使用主次目标作为候选。
## @return 包含主目标与次目标的技能上下文。
static func FromSpread(
	source: Node,
	primary_target: Node,
	secondary_targets: Variant,
	candidate_targets: Variant = null
) -> RefCounted:
	var targets: Array = []
	var target_script: Script = load(TARGET_SCRIPT_PATH)

	if primary_target != null:
		targets.append(target_script.new(primary_target, ROLE_PRIMARY))

	if secondary_targets is Array:
		for secondary: Variant in secondary_targets:
			if secondary == null or secondary == primary_target:
				continue
			targets.append(target_script.new(secondary, ROLE_SECONDARY))

	var candidates: Variant = (
		candidate_targets if candidate_targets != null else TargetsToNodes(targets)
	)
	return load(SELF_PATH).new(source, targets, candidates)


## 把目标条目数组折算成节点数组，等价旧 C# TargetsToNodes。
##
## @param targets 目标条目数组。
## @return 目标节点数组；空条目会被跳过。
static func TargetsToNodes(targets: Variant) -> Array[Node]:
	var nodes: Array[Node] = []

	if not (targets is Array):
		return nodes

	for target: Variant in targets:
		var target_object: Object = target as Object
		if target_object == null:
			continue

		var unit: Node = target_object.get("Unit") as Node
		if unit == null:
			continue

		nodes.append(unit)

	return nodes


## 归一化候选目标池，等价旧 C# NormalizeCandidates。
##
## @param candidate_targets 候选目标池，可以是任意 Variant。
## @return 去掉空条目的节点数组。
func _normalize_candidates(candidate_targets: Variant) -> Array[Node]:
	var normalized: Array[Node] = []

	if not (candidate_targets is Array):
		return normalized

	for target: Variant in candidate_targets:
		if target == null:
			continue

		normalized.append(target as Node)

	return normalized
