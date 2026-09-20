extends RefCounted

## 一次伤害结算结果的 GDScript 生产实现，等价迁移自 core/combat/DamageResolutionResult.cs。
##
## 结果对象是表现层与日志的只读快照：字段名、构造参数顺序与 GetFeedback* 协议与旧 C# 逐字一致，
## 因此 GDScript 表现层（combat_feedback_director.gd）与仍在 C# 的消费者可以用同一套名字读取。
## 护盾吸收量与单次扣血上限来自载荷的结算追踪，而追踪对象在 C# 侧是非 Godot 的纯 CLR 类，
## GDScript 读不到；因此这里改为读载荷上的转发字段协议
## （ShieldAbsorbedDamage / ShieldWasBroken / CappedDamage），由载荷负责与追踪对象对账。
## 不声明 class_name，避免与仍在使用的 C# 全局类型重名。

## 载荷上用于读取结算元数据的字段名，与旧 C# DamagePayload 属性逐字一致。
const FIELD_SOURCE: StringName = &"Source"
const FIELD_TARGET: StringName = &"Target"
const FIELD_DAMAGE: StringName = &"Damage"
const FIELD_TYPE: StringName = &"Type"
const FIELD_ELEMENT: StringName = &"Element"
const FIELD_HIT_INDEX: StringName = &"HitIndex"
const FIELD_HIT_COUNT: StringName = &"HitCount"
const FIELD_TARGET_ROLE_ID: StringName = &"TargetRoleId"
const FIELD_SHIELD_ABSORBED_DAMAGE: StringName = &"ShieldAbsorbedDamage"
const FIELD_SHIELD_WAS_BROKEN: StringName = &"ShieldWasBroken"
const FIELD_CAPPED_DAMAGE: StringName = &"CappedDamage"

## 旧 C# 兜底值：DamageType.Physical = 0、ElementType.None = 0、HitCount 至少 1。
const DEFAULT_DAMAGE_TYPE: int = 0
const DEFAULT_ELEMENT: int = 0
const DEFAULT_HIT_COUNT: int = 1

## 本次伤害的来源实体。
var Source: Node = null
## 本次伤害的目标实体。
var Target: Node = null
## 进入伤害接收组件前的基础伤害数值。
var RequestedDamage: int = 0
## 护盾和单次伤害上限处理前的最终伤害候选值。
var PreGuardDamage: int = 0
## 本次实际从目标生命中扣除的数值。
var ActualDamage: int = 0
## 本次伤害采用的公式类型枚举整数（旧 C# DamageType）。
var Type: int = DEFAULT_DAMAGE_TYPE
## 本次伤害的五行属性枚举整数（旧 C# ElementType）。
var Element: int = DEFAULT_ELEMENT
## 本次结算是否被闪避完全规避。
var IsEvaded: bool = false
## 本次结算是否触发暴击。
var IsCritical: bool = false
## 本次实际扣血是否使目标生命归零。
var IsLethal: bool = false
## 本次伤害被护盾吸收的总量。
var ShieldAbsorbedDamage: int = 0
## 本次结算是否击破了参与吸收的护盾。
var ShieldWasBroken: bool = false
## 本次伤害是否触发单次伤害上限。
var WasCapped: bool = false
## 该段伤害在所属伤害效果内的从零开始索引。
var HitIndex: int = 0
## 所属伤害效果本次实际执行的总段数。
var HitCount: int = DEFAULT_HIT_COUNT
## 目标在技能目标选择中的角色枚举整数，用于表现层区分主目标和次目标。
var TargetRoleId: int = 0


## 使用已经完成的伤害数据创建只读结算结果。
##
## @param payload 本次伤害的输入载荷与表现元数据；允许为空（兜底结算）。
## @param pre_guard_damage 护盾和伤害上限处理前的最终伤害候选值。
## @param actual_damage 目标生命实际减少的数值。
## @param is_evaded 本次伤害是否被闪避。
## @param is_critical 本次伤害是否暴击。
## @param is_lethal 本次伤害是否使目标生命归零。
## @return 无返回值。
func _init(
	payload: Variant,
	pre_guard_damage: int,
	actual_damage: int,
	is_evaded: bool,
	is_critical: bool,
	is_lethal: bool
) -> void:
	Source = _read_node(payload, FIELD_SOURCE)
	Target = _read_node(payload, FIELD_TARGET)
	RequestedDamage = _read_int(payload, FIELD_DAMAGE)
	# 钳制规则与旧 C# 完全一致：前两个伤害值不允许为负，段数与段索引有稳定下界。
	PreGuardDamage = maxi(0, pre_guard_damage)
	ActualDamage = maxi(0, actual_damage)
	Type = _read_int(payload, FIELD_TYPE, DEFAULT_DAMAGE_TYPE)
	Element = _read_int(payload, FIELD_ELEMENT, DEFAULT_ELEMENT)
	IsEvaded = is_evaded
	IsCritical = is_critical
	IsLethal = is_lethal
	ShieldAbsorbedDamage = _read_int(payload, FIELD_SHIELD_ABSORBED_DAMAGE)
	ShieldWasBroken = _read_bool(payload, FIELD_SHIELD_WAS_BROKEN)
	WasCapped = _read_int(payload, FIELD_CAPPED_DAMAGE) > 0
	HitIndex = maxi(0, _read_int(payload, FIELD_HIT_INDEX))
	HitCount = maxi(DEFAULT_HIT_COUNT, _read_int(payload, FIELD_HIT_COUNT, DEFAULT_HIT_COUNT))
	TargetRoleId = _read_int(payload, FIELD_TARGET_ROLE_ID)


## 为表现层读取整数字段提供稳定的跨语言入口。
##
## 与旧 C# 一样只暴露只读读取，避免表现层参与权威战斗结算。
##
## @param property_name 需要读取的字段名称，与旧 C# 属性名逐字一致。
## @return 对应的整数值；名称不受支持时返回 0。
func GetFeedbackInt(property_name: String) -> int:
	match property_name:
		"RequestedDamage":
			return RequestedDamage
		"PreGuardDamage":
			return PreGuardDamage
		"ActualDamage":
			return ActualDamage
		"ShieldAbsorbedDamage":
			return ShieldAbsorbedDamage
		"HitIndex":
			return HitIndex
		"HitCount":
			return HitCount
		"TargetRoleId":
			return TargetRoleId
		_:
			return 0


## 为表现层读取布尔字段提供稳定的跨语言入口。
##
## @param property_name 需要读取的字段名称，与旧 C# 属性名逐字一致。
## @return 对应的布尔值；名称不受支持时返回 false。
func GetFeedbackBool(property_name: String) -> bool:
	match property_name:
		"IsEvaded":
			return IsEvaded
		"IsCritical":
			return IsCritical
		"IsLethal":
			return IsLethal
		"ShieldWasBroken":
			return ShieldWasBroken
		"WasCapped":
			return WasCapped
		_:
			return false


## 为表现层读取来源或目标节点提供稳定的跨语言入口。
##
## @param property_name 需要读取的节点字段名称，与旧 C# 属性名逐字一致。
## @return 对应节点；名称不受支持时返回 null。
func GetFeedbackNode(property_name: String) -> Node:
	match property_name:
		"Source":
			return Source
		"Target":
			return Target
		_:
			return null


## 读取载荷字段；载荷允许为空或不是可读取对象。
##
## @param source 旧 C# 垫片或 GDScript 生产载荷。
## @param field 字段名。
## @return 字段值；不可读取时返回 null。
func _read_field(source: Variant, field: StringName) -> Variant:
	var target: Object = source as Object
	if target == null:
		return null

	return target.get(field)


## 读取载荷上的节点字段。
##
## @param source 伤害载荷。
## @param field 字段名。
## @return 节点对象；缺失或类型不符时返回 null。
func _read_node(source: Variant, field: StringName) -> Node:
	return _read_field(source, field) as Node


## 读取载荷上的整数字段，兼容枚举导出为整数的行为。
##
## @param source 伤害载荷。
## @param field 字段名。
## @param fallback 字段缺失或类型不符时的兜底值。
## @return 字段整数或兜底值。
func _read_int(source: Variant, field: StringName, fallback: int = 0) -> int:
	var value: Variant = _read_field(source, field)
	if value is int or value is float:
		return int(value)

	return fallback


## 读取载荷上的布尔字段。
##
## @param source 伤害载荷。
## @param field 字段名。
## @return 字段布尔值；缺失或类型不符时返回 false。
func _read_bool(source: Variant, field: StringName) -> bool:
	var value: Variant = _read_field(source, field)
	return value is bool and value
