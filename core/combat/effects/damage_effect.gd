extends "res://core/combat/effects/card_effect.gd"

## 伤害效果的生产 GDScript 实现。
##
## 字段、默认值与旧 C# DamageEffect 逐字一致，执行顺序（段数修正 → 逐段选目标 → 单段
## 修正 → 构造伤害载荷 → 交给伤害接收组件）完全保持不变；技能执行上下文与目标条目已迁移
## 到 GDScript，伤害载荷仍是 C# 实现，全部通过字段/方法协议动态读取。
## 脚本不声明 class_name，避免与仍在使用的 C# DamageEffect 全局类型重名。

## 与 C# DamageHitTargetMode 对齐的段目标选择模式。
const HIT_TARGET_CONTEXT_TARGETS: int = 0
const HIT_TARGET_RANDOM_CANDIDATE: int = 1

## 目标上的生命组件查找路径，顺序与旧 C# 实现一致。
const HEALTH_COMPONENT_PATHS: Array[String] = [
	"Components/HealthComponent",
	"HealthComponent",
]

const RECEIVER_PATH: String = "Components/DamageReceiverComponent"
## 伤害载荷的生产脚本路径；旧 C# DamagePayload.cs 保留为兼容垫片与 C# 测试基线。
const PAYLOAD_SCRIPT_PATH: String = "res://core/combat/damage_payload.gd"
const HIT_COUNT_CONTEXT_SCRIPT_PATH: String = \
	"res://core/combat/effects/damage_effect_hit_count_context.gd"
const SEGMENT_CONTEXT_SCRIPT_PATH: String = \
	"res://core/combat/effects/damage_effect_segment_context.gd"

## 伤害基础数值，沿用旧 C# 默认值 10。
@export var BaseDamage: int = 10

## 伤害段数，沿用旧 C# 默认值 1。
@export var HitCount: int = 1

## 每段的目标选择模式，沿用旧 C# 默认值 ContextTargets。
@export var HitTargetMode: int = HIT_TARGET_CONTEXT_TARGETS

## 伤害类型（物理/法术/真实），沿用旧 C# 默认值 Physical。
@export var Type: int = 0

## 伤害五行属性，沿用旧 C# 默认值 None。
@export var Element: int = 0

## 效果目标范围，沿用旧 C# 默认值 PrimaryOnly。
@export var TargetScope: int = SCOPE_PRIMARY_ONLY

## 主目标伤害倍率，沿用旧 C# 默认值 1.0。
@export var PrimaryDamageMultiplier: float = 1.0

## 次目标伤害倍率，沿用旧 C# 默认值 1.0。
@export var SecondaryDamageMultiplier: float = 1.0

## 随机候选目标使用的随机源，保持旧 C# RandomNumberGenerator 的随机化时机。
var _target_rng := RandomNumberGenerator.new()


## 初始化随机源；等价于旧 C# 构造函数中的 Randomize。
func _init() -> void:
	_target_rng.randomize()


## 执行伤害效果。
##
## @param context 技能执行上下文，允许旧 C# SkillExecutionContext。
## @return 无。
func Execute(context: RefCounted) -> void:
	if context == null:
		push_error("DamageEffect executed with null context.")
		return

	var effective_hit_count := _calculate_effective_hit_count(context)
	if effective_hit_count <= 0:
		return

	if HitTargetMode == HIT_TARGET_RANDOM_CANDIDATE:
		_execute_random_candidate_hits(context, effective_hit_count)
		return

	_execute_context_target_hits(context, effective_hit_count)


## 按上下文目标逐段结算伤害。
##
## @param context 技能执行上下文。
## @param effective_hit_count 修正后的有效段数。
## @return 无。
func _execute_context_target_hits(context: RefCounted, effective_hit_count: int) -> void:
	for hit_index: int in range(effective_hit_count):
		for selection: Dictionary in _select_scope_targets(context, TargetScope):
			if selection["Unit"] == null:
				continue
			_apply_damage_to_selection(context, selection, hit_index, effective_hit_count)


## 每段从技能开始时锁定的候选池中重新随机选择有效目标。
##
## @param context 技能执行上下文。
## @param effective_hit_count 修正后的有效段数。
## @return 无。
func _execute_random_candidate_hits(context: RefCounted, effective_hit_count: int) -> void:
	for hit_index: int in range(effective_hit_count):
		var candidates := _select_valid_candidates(context.get("CandidateTargets"))
		if candidates.is_empty():
			return
		var target_node: Node = candidates[_target_rng.randi_range(0, candidates.size() - 1)]
		var selection := _make_selection(target_node, ROLE_PRIMARY, false)
		_apply_damage_to_selection(context, selection, hit_index, effective_hit_count)


## 在段数循环之前应用施法者状态的段数修正。
##
## @param context 技能执行上下文。
## @return 修正后的有效段数，最低为 0。
func _calculate_effective_hit_count(context: RefCounted) -> int:
	var hit_count: int = maxi(0, HitCount)
	var source: Node = context.get("Source")
	var status_component := _find_status_component(source)
	if status_component == null:
		return hit_count

	var hit_count_context: RefCounted = load(HIT_COUNT_CONTEXT_SCRIPT_PATH).new(
		source,
		context,
		self,
		hit_count
	)
	var modified: Variant = status_component.call(
		"ApplyDamageHitCountModifiers",
		hit_count_context,
		hit_count
	)
	return maxi(0, int(modified))


## 结算单个目标的一段伤害。
##
## @param context 技能执行上下文。
## @param selection 目标选择字典。
## @param hit_index 当前段序号。
## @param effective_hit_count 修正后的有效段数。
## @return 无。
func _apply_damage_to_selection(
	context: RefCounted,
	selection: Dictionary,
	hit_index: int,
	effective_hit_count: int
) -> void:
	var damage := _calculate_damage_for_target(selection)
	var source: Node = context.get("Source")
	var status_component := _find_status_component(source)
	if status_component != null:
		var segment_context: RefCounted = load(SEGMENT_CONTEXT_SCRIPT_PATH).new(
			source,
			context,
			self,
			selection,
			hit_index,
			effective_hit_count
		)
		var modified: Variant = status_component.call(
			"ApplyDamageEffectSegmentDamageModifiers",
			segment_context,
			damage
		)
		damage = int(modified)
	damage = maxi(0, damage)

	_apply_damage_to_node(
		source,
		selection["Unit"],
		damage,
		hit_index,
		effective_hit_count,
		int(selection["Role"])
	)


## 计算单个目标本段的基础伤害。
##
## @param selection 目标选择字典。
## @return 按主次目标倍率取整后的伤害，最低为 0。
func _calculate_damage_for_target(selection: Dictionary) -> int:
	var multiplier: float
	if bool(selection["IsSource"]):
		multiplier = PrimaryDamageMultiplier
	else:
		match int(selection["Role"]):
			ROLE_PRIMARY:
				multiplier = PrimaryDamageMultiplier
			ROLE_SECONDARY:
				multiplier = SecondaryDamageMultiplier
			_:
				multiplier = 1.0
	return maxi(0, roundi(BaseDamage * multiplier))


## 过滤出仍然可以承伤的候选目标。
##
## @param candidates 候选目标集合，通常是旧 C# Array<Node>。
## @return 有效候选节点数组。
func _select_valid_candidates(candidates: Variant) -> Array[Node]:
	var valid_candidates: Array[Node] = []
	if not (candidates is Array):
		return valid_candidates
	for candidate: Variant in candidates:
		if _is_valid_damage_candidate(candidate):
			valid_candidates.append(candidate)
	return valid_candidates


## 判断候选目标是否仍可作为伤害目标。
##
## @param candidate 候选对象，通常是节点。
## @return 有效时返回 true。
func _is_valid_damage_candidate(candidate: Variant) -> bool:
	if candidate == null or not (candidate is Node):
		return false
	var node: Node = candidate
	if not is_instance_valid(node) or node.is_queued_for_deletion():
		return false
	return _read_health_current_value(node) > 0


## 读取跨语言生命组件的当前生命值。
##
## @param target 目标节点。
## @return 当前生命值；组件缺失或字段类型不符时返回 0。
func _read_health_current_value(target: Node) -> int:
	for path: String in HEALTH_COMPONENT_PATHS:
		var health: Node = target.get_node_or_null(path)
		if health == null:
			continue
		var value: Variant = health.get("CurrentValue")
		if value is int or value is float:
			return int(value)
		return 0
	return 0


## 构造伤害载荷并交给目标上的伤害接收组件结算。
##
## @param source 伤害来源节点。
## @param target 伤害目标节点。
## @param damage 本段最终伤害值。
## @param hit_index 当前段序号。
## @param hit_count 本次效果的总段数。
## @param target_role_id 目标角色枚举整数。
## @return 无。
func _apply_damage_to_node(
	source: Node,
	target: Node,
	damage: int,
	hit_index: int,
	hit_count: int,
	target_role_id: int
) -> void:
	if damage <= 0:
		return

	var receiver: Node = target.get_node_or_null(RECEIVER_PATH)
	if receiver == null:
		push_warning("Target '%s' has no DamageReceiverComponent." % target.name)
		return

	var payload: Object = load(PAYLOAD_SCRIPT_PATH).new()
	payload.set("Source", source)
	payload.set("Target", target)
	payload.set("Damage", damage)
	payload.set("Type", Type)
	payload.set("Element", Element)
	payload.set("HitIndex", hit_index)
	payload.set("HitCount", hit_count)
	payload.set("TargetRoleId", target_role_id)

	receiver.call("ReceiveDamage", payload)

	print("[伤害效果] %s 对 %s 造成 %d 点伤害，基础伤害：%d" % [
		source.name,
		target.name,
		damage,
		BaseDamage,
	])
