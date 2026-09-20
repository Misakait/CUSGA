extends RefCounted

## 状态运行时实例的生产 GDScript 实现，等价迁移自 C# StatusEffectInstance。
##
## 字段名、方法名与默认值都与旧 C# 逐字一致，因此状态组件（GDScript 生产实现或 C# 垫片）
## 都能用同一套动态协议驱动本类：get("CurrentStacks")、call("OnApply")、call("IsExpired") 等。
## 数据字段一律按字段名从 Data 读取，旧 C# StatusEffectData 垫片与 GDScript 生产数据因此
## 共用同一条读取路径。脚本不声明 class_name，避免与 C# 类型表里的同名全局类冲突。

## 状态数据字段名，与旧 C# StatusEffectDataProtocol 的字段常量逐字一致。
const FIELD_ID: StringName = &"Id"
const FIELD_DESCRIPTION: StringName = &"Description"
const FIELD_MAX_STACKS: StringName = &"MaxStacks"
const FIELD_POLICY: StringName = &"Policy"
const FIELD_EXPIRE_POLICY: StringName = &"ExpirePolicy"
const FIELD_DURATION_TICK_TIMING: StringName = &"DurationTickTiming"
const FIELD_DEFAULT_HOOK_PRIORITY: StringName = &"DefaultHookPriority"
const FIELD_INIT_OWNER_TURN_DURATION: StringName = &"InitOwnerTurnDuration"
const FIELD_INIT_GLOBAL_TURN_DURATION: StringName = &"InitGlobalTurnDuration"
const FIELD_INIT_ROUND_DURATION: StringName = &"InitRoundDuration"

## 持续时间扣减时机枚举整数（DurationTickTiming.Start）。
const TIMING_START: int = 0

## 过期策略枚举整数（DurationExpirePolicy.FirstExpired）：任一已配置持续时间耗尽即过期。
const EXPIRE_POLICY_FIRST_EXPIRED: int = 0

## 过期策略枚举整数（DurationExpirePolicy.AllExpired）：所有已配置持续时间耗尽才过期。
const EXPIRE_POLICY_ALL_EXPIRED: int = 1

## 状态数据资源；可能是旧 C# StatusEffectData 垫片，也可能是 GDScript 生产实现。
var _data: Resource

## 状态数据资源；表现层与状态组件都通过该只读出口读取配置。
var Data: Resource:
	get:
		return _data

## 状态唯一标识，用于叠加、刷新、移除和存档定位。
var Id: StringName:
	get:
		return _read_string_name(FIELD_ID)

## 允许叠加的最大层数；0 表示没有层数上限。
var MaxStacks: int:
	get:
		return _read_int(FIELD_MAX_STACKS)

## 叠加策略枚举整数（StackPolicy）。
var Policy: int:
	get:
		return _read_int(FIELD_POLICY)

## 过期策略枚举整数（DurationExpirePolicy）。
var ExpirePolicy: int:
	get:
		return _read_int(FIELD_EXPIRE_POLICY)

## 持续时间扣减时机枚举整数（DurationTickTiming）。
var TickTiming: int:
	get:
		return _read_int(FIELD_DURATION_TICK_TIMING)

## 持续该单位自己 N 次行动的初始持续时间。
var InitOwnerTurnDuration: int:
	get:
		return _read_int(FIELD_INIT_OWNER_TURN_DURATION)

## 持续全场 N 次行动的初始持续时间。
var InitGlobalTurnDuration: int:
	get:
		return _read_int(FIELD_INIT_GLOBAL_TURN_DURATION)

## 持续 N 轮的初始持续时间。
var InitRoundDuration: int:
	get:
		return _read_int(FIELD_INIT_ROUND_DURATION)

## 施加该状态的来源节点。
var Source: Node

## 该状态的拥有者节点。
var Owner: Node

## 当前层数；刚施加时为 1。
var CurrentStacks: int = 1

## 剩余拥有者回合持续时间。
var OwnerTurnDuration: int = 0

## 剩余全局回合持续时间。
var GlobalTurnDuration: int = 0

## 剩余轮次持续时间。
var RoundDuration: int = 0

## 状态的应用序号，由状态组件写入，用于同优先级 Hook 的稳定排序。
var AppliedSequence: int = -1

## 表现层读取的运行时描述；默认取数据配置的描述，特殊状态覆盖 _get_display_description。
var DisplayDescription: String:
	get:
		return _get_display_description()


## 构造状态实例并立即按数据配置重置持续时间。
##
## @param data 状态数据资源（旧 C# 垫片或 GDScript 生产实现）。
## @param source 施加状态的来源节点。
## @param owner 状态的拥有者节点。
## @return 无。
func _init(data: Resource, source: Node, owner: Node) -> void:
	_data = data
	Source = source
	Owner = owner
	ResetDurations()


## 增加一层叠层。
##
## @return 成功叠加时返回 true；已达上限时返回 false。
func TryIncreaseStack() -> bool:
	if MaxStacks > 0 and CurrentStacks >= MaxStacks:
		return false

	CurrentStacks += 1
	OnStackIncreased(CurrentStacks)
	return true


## 移除一层叠层；仅剩一层时不允许扣层，避免状态在扣层路径上被静默清空。
##
## @return 成功扣层时返回 true；仅剩一层时返回 false。
func TryRemoveStack() -> bool:
	if CurrentStacks <= 1:
		return false

	CurrentStacks -= 1
	OnStackRemoved(CurrentStacks)
	return true


## 按数据配置重置三条持续时间。
##
## @return 无。
func ResetDurations() -> void:
	OwnerTurnDuration = InitOwnerTurnDuration
	GlobalTurnDuration = InitGlobalTurnDuration
	RoundDuration = InitRoundDuration


## 按另一份状态的初始持续时间累加持续时间（AddDuration 叠加策略使用）。
##
## @param other 本次新施加的同 Id 状态实例，允许任意语言实现。
## @return 无。
func AddDurationsFrom(other: Variant) -> void:
	OwnerTurnDuration += _field_int(other, FIELD_INIT_OWNER_TURN_DURATION)
	GlobalTurnDuration += _field_int(other, FIELD_INIT_GLOBAL_TURN_DURATION)
	RoundDuration += _field_int(other, FIELD_INIT_ROUND_DURATION)


## 推进拥有者回合：先触发回合开始 Hook，再按扣减时机推进拥有者回合持续时间。
##
## @return 持续时间发生变化时返回 true。
func TickOwnerTurn() -> bool:
	OnOwnerTurnStart()
	return TickOwnerTurnDuration(TIMING_START)


## 推进全局回合：先触发回合开始 Hook，再按扣减时机推进全局回合持续时间。
##
## @param current_actor 本次行动的单位。
## @return 持续时间发生变化时返回 true。
func TickGlobalTurn(current_actor: Node) -> bool:
	OnGlobalTurnStart(current_actor)
	return TickGlobalTurnDuration(TIMING_START)


## 推进轮次：先触发轮次开始 Hook，再按扣减时机推进轮次持续时间。
##
## @return 持续时间发生变化时返回 true。
func TickRound() -> bool:
	OnRoundStart()
	return TickRoundDuration(TIMING_START)


## 按扣减时机推进拥有者回合持续时间。
##
## @param timing 本次扣减时机枚举整数（DurationTickTiming）。
## @return 真正扣减时返回 true。
func TickOwnerTurnDuration(timing: int) -> bool:
	if not _should_tick_duration(timing) or OwnerTurnDuration <= 0:
		return false

	OwnerTurnDuration -= 1
	return true


## 按扣减时机推进全局回合持续时间。
##
## @param timing 本次扣减时机枚举整数（DurationTickTiming）。
## @return 真正扣减时返回 true。
func TickGlobalTurnDuration(timing: int) -> bool:
	if not _should_tick_duration(timing) or GlobalTurnDuration <= 0:
		return false

	GlobalTurnDuration -= 1
	return true


## 按扣减时机推进轮次持续时间。
##
## @param timing 本次扣减时机枚举整数（DurationTickTiming）。
## @return 真正扣减时返回 true。
func TickRoundDuration(timing: int) -> bool:
	if not _should_tick_duration(timing) or RoundDuration <= 0:
		return false

	RoundDuration -= 1
	return true


## 判断状态是否已经过期；未配置有限持续时间时永不过期。
##
## @return 过期时返回 true。
func IsExpired() -> bool:
	if not _has_finite_duration():
		return false

	var owner_expired: bool = InitOwnerTurnDuration > 0 and OwnerTurnDuration <= 0
	var global_expired: bool = InitGlobalTurnDuration > 0 and GlobalTurnDuration <= 0
	var round_expired: bool = InitRoundDuration > 0 and RoundDuration <= 0

	match ExpirePolicy:
		EXPIRE_POLICY_FIRST_EXPIRED:
			return owner_expired or global_expired or round_expired
		EXPIRE_POLICY_ALL_EXPIRED:
			return (
				_is_configured_duration_expired_or_unused(InitOwnerTurnDuration, OwnerTurnDuration)
				and _is_configured_duration_expired_or_unused(
					InitGlobalTurnDuration,
					GlobalTurnDuration
				)
				and _is_configured_duration_expired_or_unused(InitRoundDuration, RoundDuration)
			)
		_:
			return owner_expired or global_expired or round_expired


## 段数修正的非 ref 包装，供状态组件动态调用取得修正后的段数。
##
## @param context 伤害段数修正上下文（旧 C# DamageEffectHitCountContext）。
## @param hit_count 进入修正前的有效段数。
## @return 修正后的有效段数；内部走同一套 OnModifyDamageHitCount 覆盖点，语义不变。
func ApplyModifyDamageHitCount(context: Variant, hit_count: int) -> int:
	return OnModifyDamageHitCount(context, hit_count)


## 单段伤害修正的非 ref 包装，供状态组件动态调用取得修正后的伤害。
##
## @param context 单段伤害修正上下文（旧 C# DamageEffectSegmentContext）。
## @param damage 进入修正前的本段伤害。
## @return 修正后的本段伤害；内部走同一套 OnModifyDamageEffectSegmentDamage 覆盖点。
func ApplyModifyDamageEffectSegmentDamage(context: Variant, damage: int) -> int:
	return OnModifyDamageEffectSegmentDamage(context, damage)


## 攻击方输出伤害修正的非 ref 包装，供状态组件动态调用。
##
## @param payload 本次伤害载荷（旧 C# DamagePayload）。
## @param damage 进入修正前的伤害值。
## @return 修正后的伤害值。
func ApplyModifyOutgoingDamage(payload: Variant, damage: float) -> float:
	return OnModifyOutgoingDamage(payload, damage)


## 防御方减伤前修正的非 ref 包装，供状态组件动态调用。
##
## @param payload 本次伤害载荷（旧 C# DamagePayload）。
## @param damage 进入修正前的伤害值。
## @return 修正后的伤害值。
func ApplyModifyIncomingDamageBeforeMitigation(payload: Variant, damage: float) -> float:
	return OnModifyIncomingDamageBeforeMitigation(payload, damage)


## 防御方减伤后修正的非 ref 包装，供状态组件动态调用。
##
## @param payload 本次伤害载荷（旧 C# DamagePayload）。
## @param damage 进入修正前的伤害值。
## @return 修正后的伤害值。
func ApplyModifyIncomingDamageAfterMitigation(payload: Variant, damage: float) -> float:
	return OnModifyIncomingDamageAfterMitigation(payload, damage)


## 扣血前最终修正的非 ref 包装，供状态组件动态调用。
##
## @param payload 本次伤害载荷（旧 C# DamagePayload）。
## @param damage 进入修正前的伤害值。
## @return 修正后的伤害值。
func ApplyBeforeHealthDamage(payload: Variant, damage: float) -> float:
	return OnBeforeHealthDamage(payload, damage)


## Hook 默认优先级；数值越小越早执行。状态组件在同 phase 内按本值排序。
##
## @param _phase 对应 StatusHookPhase 枚举整数，基类不区分阶段。
## @return 该阶段的执行优先级。
func GetHookPriority(_phase: int) -> int:
	return _read_int(FIELD_DEFAULT_HOOK_PRIORITY)


## 状态被施加时调用。
##
## @return 无。
func OnApply() -> void:
	pass


## 状态被移除时调用。
##
## @return 无。
func OnRemove() -> void:
	pass


## 重新施加同一状态时调用。
##
## @param _incoming 本次新施加进来的同 Id 状态实例。
## @return 无。
func OnReapplied(_incoming: Variant) -> void:
	pass


## 叠层增加后调用。
##
## @param _current_stacks 变化后的层数。
## @return 无。
func OnStackIncreased(_current_stacks: int) -> void:
	pass


## 叠层减少后调用。
##
## @param _current_stacks 变化后的层数。
## @return 无。
func OnStackRemoved(_current_stacks: int) -> void:
	pass


## 拥有者回合开始时调用。
##
## @return 无。
func OnOwnerTurnStart() -> void:
	pass


## 全局回合开始时调用。
##
## @param _current_actor 本次开始行动的单位。
## @return 无。
func OnGlobalTurnStart(_current_actor: Node) -> void:
	pass


## 轮次开始时调用。
##
## @return 无。
func OnRoundStart() -> void:
	pass


## 拥有者回合结束时调用。
##
## @return 无。
func OnOwnerTurnEnd() -> void:
	pass


## 全局回合结束时调用。
##
## @param _current_actor 本次结束行动的单位。
## @return 无。
func OnGlobalTurnEnd(_current_actor: Node) -> void:
	pass


## 轮次结束时调用。
##
## @return 无。
func OnRoundEnd() -> void:
	pass


## 整张技能开始执行前调用，用于初始化技能级状态作用域。
##
## @param _context 本次技能执行修正上下文（旧 C# SkillExecutionModifierContext）。
## @return 无。
func OnBeforeSkillExecution(_context: Variant) -> void:
	pass


## 整张技能全部效果执行后调用，用于标记限次状态消费。
##
## @param _context 本次技能执行修正上下文（旧 C# SkillExecutionModifierContext）。
## @return 无。
func OnAfterSkillExecution(_context: Variant) -> void:
	pass


## 属性变化前拦截钩子。
##
## @param _context 属性变化上下文（旧 C# 或 GDScript 载体），实现方按
## Type / OldValue / Delta / NewValue 字段协议与 Cancel / MatchesDirection 方法协议读写。
## @return 无。
func OnBeforeAttributeChange(_context: Variant) -> void:
	pass


## 属性变化后钩子。
##
## @param _context 属性变化上下文（旧 C# 或 GDScript 载体）。
## @return 无。
func OnAfterAttributeChanged(_context: Variant) -> void:
	pass


## 在伤害效果进入段数循环前修正有效段数的覆盖点。
##
## @param _context 伤害段数修正上下文（旧 C# DamageEffectHitCountContext）。
## @param hit_count 当前有效段数候选值。
## @return 修正后的有效段数；基类不改动。
func OnModifyDamageHitCount(_context: Variant, hit_count: int) -> int:
	return hit_count


## 在单段伤害创建伤害载荷前修正本段基础伤害的覆盖点。
##
## @param _context 单段伤害修正上下文（旧 C# DamageEffectSegmentContext）。
## @param damage 当前本段基础伤害候选值。
## @return 修正后的本段基础伤害；基类不改动。
func OnModifyDamageEffectSegmentDamage(_context: Variant, damage: int) -> int:
	return damage


## 攻击方输出伤害修正覆盖点。
##
## @param _payload 本次伤害载荷（旧 C# DamagePayload）。
## @param damage 进入修正前的伤害值。
## @return 修正后的伤害值；基类不改动。
func OnModifyOutgoingDamage(_payload: Variant, damage: float) -> float:
	return damage


## 防御方减伤前修正覆盖点。
##
## @param _payload 本次伤害载荷（旧 C# DamagePayload）。
## @param damage 进入修正前的伤害值。
## @return 修正后的伤害值；基类不改动。
func OnModifyIncomingDamageBeforeMitigation(_payload: Variant, damage: float) -> float:
	return damage


## 防御方减伤后修正覆盖点。
##
## @param _payload 本次伤害载荷（旧 C# DamagePayload）。
## @param damage 进入修正前的伤害值。
## @return 修正后的伤害值；基类不改动。
func OnModifyIncomingDamageAfterMitigation(_payload: Variant, damage: float) -> float:
	return damage


## 扣血前最终修正覆盖点。
##
## @param _payload 本次伤害载荷（旧 C# DamagePayload）。
## @param damage 进入修正前的伤害值。
## @return 修正后的伤害值；基类不改动。
func OnBeforeHealthDamage(_payload: Variant, damage: float) -> float:
	return damage


## 返回状态在悬停提示里显示的运行时描述。
##
## @return 默认返回数据配置的描述；特殊状态可覆盖本方法展示运行时数值。
func _get_display_description() -> String:
	return _read_text(FIELD_DESCRIPTION)


## 扣减一次技能级限次状态使用次数。
##
## @return 状态应被移除时返回 true；基类默认允许移除。
func ConsumeMarkedSkillExecutionUse() -> bool:
	return true


## 属性修饰条目的跨语言出口，条目字段为 Type / Mode / ValuePerStack / Stacks / SourceId。
##
## @return 修饰条目字典数组；基类默认没有修饰条目。
func GetAttributeModifiers() -> Array:
	return []


## 属性修饰条目的跨语言出口；基类返回与 GetAttributeModifiers 相同的数据。
##
## @return 修饰条目字典数组。
func GetAttributeModifiersData() -> Array:
	return GetAttributeModifiers()


## 判断持续时间是否应在本次时机扣减。
##
## @param timing 本次扣减时机枚举整数（DurationTickTiming）。
## @return 与数据配置的扣减时机一致时返回 true。
func _should_tick_duration(timing: int) -> bool:
	return TickTiming == timing


## 判断某条持续时间是否属于“已配置但已耗尽”或“未配置”。
##
## @param initial 初始持续时间。
## @param current 当前剩余持续时间。
## @return 未配置或已耗尽时返回 true。
func _is_configured_duration_expired_or_unused(initial: int, current: int) -> bool:
	return initial <= 0 or current <= 0


## 判断状态数据是否配置了有限持续时间。
##
## @return 三条初始持续时间中有任意一条大于 0 时返回 true。
func _has_finite_duration() -> bool:
	return (
		InitOwnerTurnDuration > 0
		or InitGlobalTurnDuration > 0
		or InitRoundDuration > 0
	)


## 读取状态数据上的整数字段，兼容旧 C# 导出枚举与 GDScript 导出变量。
##
## @param field 字段名，必须与旧 C# 属性名逐字一致。
## @return 字段整数；数据或字段缺失时返回 0。
func _read_int(field: StringName) -> int:
	return _field_int(_data, field)


## 读取状态数据上的浮点字段。
##
## @param field 字段名，必须与旧 C# 属性名逐字一致。
## @return 字段浮点值；数据或字段缺失时返回 0.0。
func _read_float(field: StringName) -> float:
	return _field_float(_data, field)


## 读取状态数据上的布尔字段。
##
## @param field 字段名，必须与旧 C# 属性名逐字一致。
## @return 字段布尔值；数据或字段缺失时返回 false。
func _read_bool(field: StringName) -> bool:
	return _field_bool(_data, field)


## 读取状态数据上的文本字段。
##
## @param field 字段名，必须与旧 C# 属性名逐字一致。
## @return 字段文本；数据或字段缺失时返回空字符串。
func _read_text(field: StringName) -> String:
	return _field_text(_data, field)


## 读取状态数据上的 StringName 字段。
##
## @param field 字段名，必须与旧 C# 属性名逐字一致。
## @return 字段 StringName；数据或字段缺失时返回空 StringName。
func _read_string_name(field: StringName) -> StringName:
	return _field_string_name(_data, field)


## 读取状态数据上的数组字段。
##
## @param field 字段名，必须与旧 C# 属性名逐字一致。
## @return 字段数组；数据或字段缺失时返回空数组。
func _read_array(field: StringName) -> Array:
	return _field_array(_data, field)


## 读取任意跨语言对象上的字段原始值。
##
## @param source 旧 C# 垫片或 GDScript 生产对象，允许为空。
## @param field 字段名。
## @return 字段原始值；对象或字段缺失时返回 null。
func _field_value(source: Variant, field: StringName) -> Variant:
	var target: Object = source as Object
	if target == null:
		return null
	return target.get(field)


## 读取任意跨语言对象上的整数字段。
##
## @param source 旧 C# 垫片或 GDScript 生产对象，允许为空。
## @param field 字段名。
## @return 字段整数；类型不符或缺失时返回 0。
func _field_int(source: Variant, field: StringName) -> int:
	var value: Variant = _field_value(source, field)
	if value is int:
		return value
	if value is float:
		return int(value)
	return 0


## 读取任意跨语言对象上的浮点字段。
##
## @param source 旧 C# 垫片或 GDScript 生产对象，允许为空。
## @param field 字段名。
## @return 字段浮点值；类型不符或缺失时返回 0.0。
func _field_float(source: Variant, field: StringName) -> float:
	var value: Variant = _field_value(source, field)
	if value is int or value is float:
		return float(value)
	return 0.0


## 读取任意跨语言对象上的布尔字段。
##
## @param source 旧 C# 垫片或 GDScript 生产对象，允许为空。
## @param field 字段名。
## @return 字段布尔值；类型不符或缺失时返回 false。
func _field_bool(source: Variant, field: StringName) -> bool:
	var value: Variant = _field_value(source, field)
	return value is bool and value


## 读取任意跨语言对象上的文本字段。
##
## @param source 旧 C# 垫片或 GDScript 生产对象，允许为空。
## @param field 字段名。
## @return 字段文本；类型不符或缺失时返回空字符串。
func _field_text(source: Variant, field: StringName) -> String:
	var value: Variant = _field_value(source, field)
	if value is String:
		return value
	if value is StringName:
		return String(value)
	return ""


## 读取任意跨语言对象上的 StringName 字段。
##
## @param source 旧 C# 垫片或 GDScript 生产对象，允许为空。
## @param field 字段名。
## @return 字段 StringName；缺失时返回空 StringName。
func _field_string_name(source: Variant, field: StringName) -> StringName:
	var value: Variant = _field_value(source, field)
	if value == null:
		return &""
	return StringName(value)


## 读取任意跨语言对象上的数组字段。
##
## @param source 旧 C# 垫片或 GDScript 生产对象，允许为空。
## @param field 字段名。
## @return 字段数组；类型不符或缺失时返回空数组。
func _field_array(source: Variant, field: StringName) -> Array:
	var value: Variant = _field_value(source, field)
	if value is Array:
		return value
	return []
