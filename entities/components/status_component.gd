extends Node

## 状态组件的 GDScript 生产实现，等价迁移自 StatusComponent.cs。
##
## 状态实例（GDScript 生产实现或旧 C# 垫片）才是状态行为的宿主，本脚本只负责状态集合、
## 叠层策略、持续时间推进与 Hook 分发，因此迁移期两侧可以逐方法互换：
## 方法名、信号名与枚举整数都与旧 C# 实现逐字一致。
## 脚本刻意不声明 class_name，避免与 C# 类型表里的同名全局类冲突。

## 状态变化信号；载荷与旧 C# 实现同为 StatusChangedEvent（RefCounted），
## 表现层不需要区分实现语言。
signal StatusChanged(change_event)

## 状态变化上下文与事件载体的脚本路径；两者已迁移到 GDScript，旧 C# 版本保留为兼容垫片。
const STATUS_CHANGE_CONTEXT_SCRIPT_PATH: String = \
	"res://core/combat/status/status_change_context.gd"
const STATUS_CHANGED_EVENT_SCRIPT_PATH: String = \
	"res://core/combat/status/status_changed_event.gd"

## StatusChangeReason 枚举整数（Applied=0、Removed=1、Refreshed=2、StackChanged=3、
## DurationTicked=4、StackExpired=5、Cleared=6）。
const REASON_APPLIED: int = 0
const REASON_REMOVED: int = 1
const REASON_REFRESHED: int = 2
const REASON_STACK_CHANGED: int = 3
const REASON_DURATION_TICKED: int = 4
const REASON_STACK_EXPIRED: int = 5

## StackPolicy 枚举整数（ResetDuration=0、AddDuration=1、AddStackOnly=2）。
const POLICY_RESET_DURATION: int = 0
const POLICY_ADD_DURATION: int = 1
const POLICY_ADD_STACK_ONLY: int = 2

## DurationTickTiming 枚举整数（Start=0、End=1）。
const TIMING_START: int = 0
const TIMING_END: int = 1

## StatusHookPhase 枚举整数，顺序与旧 C# 枚举逐字一致。
const PHASE_BEFORE_ATTRIBUTE_CHANGE: int = 0
const PHASE_AFTER_ATTRIBUTE_CHANGED: int = 1
const PHASE_MODIFY_OUTGOING_DAMAGE: int = 2
const PHASE_MODIFY_INCOMING_DAMAGE_BEFORE_MITIGATION: int = 3
const PHASE_MODIFY_INCOMING_DAMAGE_AFTER_MITIGATION: int = 4
const PHASE_MODIFY_DAMAGE_HIT_COUNT: int = 5
const PHASE_MODIFY_DAMAGE_EFFECT_SEGMENT_DAMAGE: int = 6
const PHASE_BEFORE_HEALTH_DAMAGE: int = 7
const PHASE_BEFORE_SKILL_EXECUTION: int = 8
const PHASE_AFTER_SKILL_EXECUTION: int = 9
const PHASE_GLOBAL_TURN_START: int = 10
const PHASE_OWNER_TURN_START: int = 11
const PHASE_GLOBAL_TURN_END: int = 12
const PHASE_OWNER_TURN_END: int = 13
const PHASE_ROUND_START: int = 14
const PHASE_ROUND_END: int = 15

## 以状态 Id 为键的状态实例集合；Dictionary 保持插入顺序，与旧 C# 字典行为一致。
var _statuses: Dictionary = {}

## 下一个状态的应用序号，用于同优先级 Hook 的稳定排序。
var _next_applied_sequence: int = 0

## 全局事件总线；旧实现只保留引用（相关广播逻辑已被注释），此处保持同样的初始化行为。
var _global_event_bus: Node

## 持有本组件的实体节点，等价旧 C# 的 Parent 属性。
var Parent: Node:
	get:
		return get_parent()

## 当前激活状态的可读快照，等价旧 C# 的 ActiveStatuses 属性。
var ActiveStatuses: Array:
	get:
		return GetActiveStatusesSnapshot()


## 缓存全局事件总线引用，行为与旧 C# _Ready 一致。
func _ready() -> void:
	_global_event_bus = get_node_or_null("/root/GlobalEventBus")


## 获取当前激活状态的快照，供 GDScript UI 安全遍历。
##
## @return 按当前字典顺序复制出的状态数组；调用方只能读取，不能通过该数组修改组件内部状态。
func GetActiveStatusesSnapshot() -> Array:
	var snapshot: Array = []
	for status: Variant in _statuses.values():
		snapshot.append(status)
	return snapshot


## 判断指定状态是否处于激活状态。
##
## @param status_id 状态唯一标识。
## @return 状态存在时返回 true。
func HasStatus(status_id: StringName) -> bool:
	return _statuses.has(status_id)


## 读取指定状态实例。
##
## @param status_id 状态唯一标识。
## @return 对应状态实例；不存在时返回 null。
func GetStatusOrNull(status_id: StringName) -> RefCounted:
	if not _statuses.has(status_id):
		return null
	return _statuses[status_id]


## 施加一个状态；已存在同 Id 状态时按叠层策略刷新。
##
## @param incoming 旧 C# StatusEffectInstance 派生实例；为空或 Id 为空时报错返回。
## @return 无。
func AddStatus(incoming: Variant) -> void:
	if incoming == null:
		push_error("StatusComponent received null status.")
		return

	var status_id: StringName = incoming.get("Id")
	if status_id == StringName():
		push_error("StatusEffectData has empty Id.")
		return

	if _statuses.has(status_id):
		var existing: RefCounted = _statuses[status_id]
		_apply_stack_policy(existing, incoming)
		existing.call("OnReapplied", incoming)
		var stack_changed: bool = bool(existing.call("TryIncreaseStack"))
		print("ReapplyStatus", incoming.get("Id"), "stackChanged", stack_changed)
		_notify_status_changed(
			existing,
			REASON_STACK_CHANGED if stack_changed else REASON_REFRESHED,
			incoming.get("Source")
		)
		return

	incoming.set("AppliedSequence", _next_applied_sequence)
	_next_applied_sequence += 1
	_statuses[status_id] = incoming
	incoming.call("OnApply")
	print("Owner:", get_parent().get_parent().name, ", AddStatus: ", incoming.get("Id"))
	_notify_status_changed(incoming, REASON_APPLIED, incoming.get("Source"))


## 移除指定状态。
##
## @param status_id 状态唯一标识。
## @return 状态存在并被移除时返回 true；否则返回 false。
func RemoveStatus(status_id: StringName) -> bool:
	if not _statuses.has(status_id):
		return false

	var status: RefCounted = _statuses[status_id]
	print("RemoveStatus", status_id)
	status.call("OnRemove")
	_statuses.erase(status_id)

	_notify_status_changed(status, REASON_REMOVED, status.get("Source"))
	return true


## 清空全部状态；逐个走 RemoveStatus 以保证 OnRemove 与通知语义不变。
##
## @return 无。
func ClearAllStatuses() -> void:
	for status_id: Variant in _statuses.keys():
		RemoveStatus(status_id)

	_statuses.clear()


## 任意单位开始行动时，由战斗系统调用。
## 触发回合开始 hook，并按配置在开始阶段扣减持续时间。
##
## @param current_actor 本次开始行动的单位。
## @return 无。
func OnTurnStarted(current_actor: Node) -> void:
	_process_turn_phase(
		current_actor,
		TIMING_START,
		PHASE_GLOBAL_TURN_START,
		PHASE_OWNER_TURN_START,
		"OnGlobalTurnStart",
		"OnOwnerTurnStart"
	)


## 任意单位结束行动时，由战斗系统调用。
## 触发回合结束 hook，并按配置在结束阶段扣减持续时间。
##
## @param current_actor 本次结束行动的单位。
## @return 无。
func OnTurnEnded(current_actor: Node) -> void:
	_process_turn_phase(
		current_actor,
		TIMING_END,
		PHASE_GLOBAL_TURN_END,
		PHASE_OWNER_TURN_END,
		"OnGlobalTurnEnd",
		"OnOwnerTurnEnd"
	)


## 当战斗系统判定“所有存活单位都至少行动过一次”时调用。
## StatusComponent 自己不负责判断 round 边界。
##
## @return 无。
func OnRoundStarted() -> void:
	print("OnRoundStarted")
	_process_round_phase(TIMING_START, PHASE_ROUND_START, "OnRoundStart")


## 当战斗系统判定一轮结束时调用。
## StatusComponent 自己不负责判断 round 边界。
##
## @return 无。
func OnRoundEnded() -> void:
	print("OnRoundEnded")
	_process_round_phase(TIMING_END, PHASE_ROUND_END, "OnRoundEnd")


## 发生在属性真正提交之前。
## 用于取消变化，修改变化，限制变化，转化变化。
##
## @param context 旧 C# AttributeChangeContext（RefCounted）。
## @return 无。
func ProcessBeforeAttributeChange(context: Variant) -> void:
	for status: Variant in _get_statuses_for_hook(PHASE_BEFORE_ATTRIBUTE_CHANGE):
		status.call("OnBeforeAttributeChange", context)
		if bool(context.get("IsCancelled")):
			break


## 发生在属性真正提交之后。
## 属性变化后触发额外效果（例如：法强提高时，抽一张牌）。
##
## @param context 旧 C# AttributeChangeContext（RefCounted）。
## @return 无。
func ProcessAfterAttributeChanged(context: Variant) -> void:
	for status: Variant in _get_statuses_for_hook(PHASE_AFTER_ATTRIBUTE_CHANGED):
		status.call("OnAfterAttributeChanged", context)


## 在整张技能开始执行前通知所有状态。
##
## @param context 本次技能执行修正上下文。
## @return 无。
func ProcessBeforeSkillExecution(context: Variant) -> void:
	var statuses: Array = _statuses.values()
	for status: Variant in _get_statuses_for_hook(PHASE_BEFORE_SKILL_EXECUTION, statuses):
		if not _is_active_status(status):
			continue

		status.call("OnBeforeSkillExecution", context)


## 在整张技能全部效果执行后通知所有状态，并统一扣减被标记的限次状态。
##
## @param context 本次技能执行修正上下文。
## @return 无。
func ProcessAfterSkillExecution(context: Variant) -> void:
	var statuses: Array = _statuses.values()
	for status: Variant in _get_statuses_for_hook(PHASE_AFTER_SKILL_EXECUTION, statuses):
		if not _is_active_status(status):
			continue

		status.call("OnAfterSkillExecution", context)

	_consume_marked_skill_execution_statuses(context)


## 段数修正的非 ref 包装，供 GDScript 伤害效果通过动态调用取得修正后的段数。
##
## @param context 旧 C# DamageEffectHitCountContext（RefCounted）。
## @param hit_count 进入修正前的有效段数。
## @return 修正后的有效段数；修正归零时返回 0。内部仍走同一套 Hook，语义不变。
func ApplyDamageHitCountModifiers(context: Variant, hit_count: int) -> int:
	var modified: int = hit_count
	for status: Variant in _get_statuses_for_hook(PHASE_MODIFY_DAMAGE_HIT_COUNT):
		modified = int(status.call("ApplyModifyDamageHitCount", context, modified))
		if modified <= 0:
			return 0

	return modified


## 单段伤害修正的非 ref 包装，供 GDScript 伤害效果通过动态调用取得修正后的伤害。
##
## @param context 旧 C# DamageEffectSegmentContext（RefCounted）。
## @param damage 进入修正前的本段伤害。
## @return 修正后的本段伤害；修正归零时返回 0。内部仍走同一套 Hook，语义不变。
func ApplyDamageEffectSegmentDamageModifiers(context: Variant, damage: int) -> int:
	var modified: int = damage
	for status: Variant in _get_statuses_for_hook(PHASE_MODIFY_DAMAGE_EFFECT_SEGMENT_DAMAGE):
		modified = int(status.call("ApplyModifyDamageEffectSegmentDamage", context, modified))
		if modified <= 0:
			return 0

	return modified


## 攻击方输出伤害修正的非 ref 包装，供 C# DamageReceiverComponent 动态调用。
##
## @param payload 本次伤害载荷（旧 C# DamagePayload）。
## @param damage 进入修正前的伤害值。
## @return 修正后的伤害值；修正归零时返回 0。内部仍走同一套 Hook，语义不变。
func ApplyModifyOutgoingDamage(payload: Variant, damage: float) -> float:
	return _apply_damage_hook(PHASE_MODIFY_OUTGOING_DAMAGE, "ApplyModifyOutgoingDamage", payload, damage)


## 防御方减伤前修正的非 ref 包装，供 C# DamageReceiverComponent 动态调用。
##
## @param payload 本次伤害载荷（旧 C# DamagePayload）。
## @param damage 进入修正前的伤害值。
## @return 修正后的伤害值；修正归零时返回 0。内部仍走同一套 Hook，语义不变。
func ApplyModifyIncomingDamageBeforeMitigation(payload: Variant, damage: float) -> float:
	return _apply_damage_hook(
		PHASE_MODIFY_INCOMING_DAMAGE_BEFORE_MITIGATION,
		"ApplyModifyIncomingDamageBeforeMitigation",
		payload,
		damage
	)


## 防御方减伤后修正的非 ref 包装，供 C# DamageReceiverComponent 动态调用。
##
## @param payload 本次伤害载荷（旧 C# DamagePayload）。
## @param damage 进入修正前的伤害值。
## @return 修正后的伤害值；修正归零时返回 0。内部仍走同一套 Hook，语义不变。
func ApplyModifyIncomingDamageAfterMitigation(payload: Variant, damage: float) -> float:
	return _apply_damage_hook(
		PHASE_MODIFY_INCOMING_DAMAGE_AFTER_MITIGATION,
		"ApplyModifyIncomingDamageAfterMitigation",
		payload,
		damage
	)


## 扣血前最终修正的非 ref 包装，供 C# DamageReceiverComponent 动态调用。
##
## @param payload 本次伤害载荷（旧 C# DamagePayload）。
## @param damage 进入修正前的伤害值。
## @return 修正后的伤害值；修正归零时返回 0。内部仍走同一套 Hook，语义不变。
func ApplyBeforeHealthDamage(payload: Variant, damage: float) -> float:
	return _apply_damage_hook(PHASE_BEFORE_HEALTH_DAMAGE, "ApplyBeforeHealthDamage", payload, damage)


## 按输出/承伤阶段分发伤害修正 Hook，并保证修正归零后立即停止后续 Hook。
##
## @param phase 对应 StatusHookPhase 枚举整数。
## @param hook_method 状态实例上等价旧 C# ref Hook 的非 ref 包装方法名。
## @param payload 本次伤害载荷。
## @param damage 进入修正前的伤害值。
## @return 修正后的伤害值；修正归零时返回 0。
func _apply_damage_hook(phase: int, hook_method: StringName, payload: Variant, damage: float) -> float:
	var modified: float = damage
	for status: Variant in _get_statuses_for_hook(phase):
		modified = float(status.call(hook_method, payload, modified))
		if modified <= 0.0:
			return 0.0

	return modified


## 回合阶段的通用处理：先依次触发全局/拥有者回合 Hook，再统一推进持续时间。
##
## @param current_actor 本次回合的单位。
## @param timing 持续时间推进时机（DurationTickTiming 枚举整数）。
## @param global_phase 全局回合 Hook 阶段。
## @param owner_phase 拥有者回合 Hook 阶段。
## @param global_hook 全局 Hook 方法名。
## @param owner_hook 拥有者 Hook 方法名。
## @return 无。
func _process_turn_phase(
	current_actor: Node,
	timing: int,
	global_phase: int,
	owner_phase: int,
	global_hook: StringName,
	owner_hook: StringName
) -> void:
	var statuses: Array = _statuses.values()

	# 全局回合 Hook 接收当前行动单位；拥有者回合 Hook 只依赖状态自身的拥有者判定。
	for status: Variant in _get_statuses_for_hook(global_phase, statuses):
		if not _is_active_status(status):
			continue

		status.call(global_hook, current_actor)

	for status: Variant in _get_statuses_for_hook(owner_phase, statuses):
		if not _is_active_status(status) or not _is_status_owner_turn(status, current_actor):
			continue

		status.call(owner_hook)

	_tick_turn_durations(statuses, current_actor, timing)


## 轮次阶段的通用处理：先触发轮次 Hook，再统一推进轮次持续时间。
##
## @param timing 持续时间推进时机（DurationTickTiming 枚举整数）。
## @param hook_phase 轮次 Hook 阶段。
## @param hook_method 轮次 Hook 方法名。
## @return 无。
func _process_round_phase(timing: int, hook_phase: int, hook_method: StringName) -> void:
	var statuses: Array = _statuses.values()

	for status: Variant in _get_statuses_for_hook(hook_phase, statuses):
		if not _is_active_status(status):
			continue

		status.call(hook_method)

	for status: Variant in statuses:
		if not _is_active_status(status) or not bool(status.call("TickRoundDuration", timing)):
			continue

		_resolve_expiration(status)


## 按配置推进全局回合与拥有者回合持续时间。
##
## @param statuses 本次需要推进的状态快照。
## @param current_actor 本次回合的单位。
## @param timing 持续时间推进时机（DurationTickTiming 枚举整数）。
## @return 无。
func _tick_turn_durations(statuses: Array, current_actor: Node, timing: int) -> void:
	for status: Variant in statuses:
		if not _is_active_status(status):
			continue

		var changed: bool = bool(status.call("TickGlobalTurnDuration", timing))

		# 与旧 C# 的 |= 语义一致：拥有者回合扣减必须无条件执行，不能被短路跳过。
		if _is_status_owner_turn(status, current_actor):
			var owner_changed: bool = bool(status.call("TickOwnerTurnDuration", timing))
			changed = changed or owner_changed

		if not changed or not _is_active_status(status):
			continue

		_resolve_expiration(status)


## 判断状态是否仍然挂在组件上（同 Id 的实例必须是同一个对象）。
##
## @param status 待判断的状态实例。
## @return 仍然是当前激活实例时返回 true。
func _is_active_status(status: Variant) -> bool:
	var status_id: Variant = status.get("Id")
	return _statuses.has(status_id) and _statuses[status_id] == status


## 判断本次行动单位是否算作该状态的拥有者回合。
##
## @param status 待判断的状态实例。
## @param current_actor 本次回合的单位。
## @return 属于拥有者（自身、宿主或其父节点）时返回 true。
func _is_status_owner_turn(status: Variant, current_actor: Node) -> bool:
	var parent: Node = get_parent()
	var host_root: Node = parent.get_parent() if parent != null else null
	var status_owner: Variant = status.get("Owner")
	return current_actor == status_owner or current_actor == parent or current_actor == host_root


## 持续时间归零后的处理：未过期则广播扣减，过期则先减层、再移除。
##
## @param status 待结算的状态实例。
## @return 无。
func _resolve_expiration(status: Variant) -> void:
	if not bool(status.call("IsExpired")):
		_notify_status_changed(status, REASON_DURATION_TICKED, status.get("Source"))
		return

	if bool(status.call("TryRemoveStack")):
		status.call("ResetDurations")
		_notify_status_changed(status, REASON_STACK_EXPIRED, status.get("Source"))
		return

	RemoveStatus(status.get("Id"))


## 按状态的叠层策略刷新持续时间。
##
## @param existing 已经挂在组件上的状态实例。
## @param incoming 本次新施加的状态实例。
## @return 无。
func _apply_stack_policy(existing: Variant, incoming: Variant) -> void:
	match int(existing.get("Policy")):
		POLICY_RESET_DURATION:
			existing.call("ResetDurations")
		POLICY_ADD_DURATION:
			existing.call("AddDurationsFrom", incoming)
		POLICY_ADD_STACK_ONLY:
			# AddStackOnly：只叠层，不动持续时间。
			pass
		_:
			push_warning("Unhandled stack policy: %s" % str(existing.get("Policy")))


## 扣减本次技能执行中被标记的限次状态使用次数。
##
## @param context 本次技能执行修正上下文。
## @return 无。
func _consume_marked_skill_execution_statuses(context: Variant) -> void:
	if context == null:
		return

	var marked: Array = context.call("GetStatusIdsMarkedForConsumptionSnapshot")
	for status_id: Variant in marked:
		if not _statuses.has(status_id):
			continue

		var status: RefCounted = _statuses[status_id]
		if bool(status.call("ConsumeMarkedSkillExecutionUse")):
			RemoveStatus(status_id)
			continue

		_notify_status_changed(status, REASON_REFRESHED, status.get("Source"))


## 按 Hook 优先级、应用序号、Id 的稳定顺序排列状态。
##
## @param phase 对应 StatusHookPhase 枚举整数。
## @param statuses 可选的状态集合；为空时使用当前全部状态。
## @return 排序后的状态数组副本。
func _get_statuses_for_hook(phase: int, statuses: Variant = null) -> Array:
	var source: Array = _statuses.values() if statuses == null else Array(statuses)
	var ordered: Array = source.duplicate()
	ordered.sort_custom(
		func(first: Variant, second: Variant) -> bool:
			return _is_hook_order_before(first, second, phase)
	)
	return ordered


## 比较两个状态在指定 Hook 阶段的先后顺序。
##
## @param first 左侧状态实例。
## @param second 右侧状态实例。
## @param phase 对应 StatusHookPhase 枚举整数。
## @return first 应排在 second 之前时返回 true。
func _is_hook_order_before(first: Variant, second: Variant, phase: int) -> bool:
	var first_priority: int = int(first.call("GetHookPriority", phase))
	var second_priority: int = int(second.call("GetHookPriority", phase))
	if first_priority != second_priority:
		return first_priority < second_priority

	var first_sequence: int = int(first.get("AppliedSequence"))
	var second_sequence: int = int(second.get("AppliedSequence"))
	if first_sequence != second_sequence:
		return first_sequence < second_sequence

	return String(first.get("Id")) < String(second.get("Id"))


## 广播一次状态变化：构造旧 C# 上下文与事件载体后发出同名信号。
##
## @param status 发生变化的状态实例。
## @param reason StatusChangeReason 枚举整数。
## @param source 施加或刷新该状态的来源实体。
## @return 无。
func _notify_status_changed(status: Variant, reason: int, source: Node) -> void:
	var context: RefCounted = load(STATUS_CHANGE_CONTEXT_SCRIPT_PATH).new(
		get_parent(),
		source,
		status,
		reason
	)
	var change_event: RefCounted = load(STATUS_CHANGED_EVENT_SCRIPT_PATH).new(context)
	emit_signal("StatusChanged", change_event)
