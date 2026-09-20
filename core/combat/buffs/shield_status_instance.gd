extends "res://core/combat/status/status_effect_instance.gd"

## 护盾状态实例的生产 GDScript 实现，等价迁移自 C# ShieldStatusInstance。
##
## 护盾在扣血前阶段吸收伤害，把“实际吸收量 / 是否击破”写入本次载荷的表现记录，
## 并在耗尽时通过状态组件的 RemoveStatus 方法协议移除自身；重复施加时只与同样是护盾的实例累加。
## 脚本不声明 class_name，避免与 C# 类型表里的同名全局类冲突。

## 扣血前阶段枚举整数（StatusHookPhase.BeforeHealthDamage）。
const PHASE_BEFORE_HEALTH_DAMAGE: int = 7

## 扣血前阶段的执行优先级，与旧 C# 逐字一致（低于单次扣血上限，先消耗护盾）。
const BEFORE_HEALTH_DAMAGE_PRIORITY: int = 100

## 状态组件查找路径，顺序与旧 C# ComponentLookup.GetStatusComponentOrNull 完全一致。
const STATUS_COMPONENT_PATHS: Array[String] = [
	"StatusComponent",
	"Components/StatusComponent",
]
const STATUS_COMPONENT_UNIQUE_PATH: NodePath = ^"%StatusComponent"

## 状态组件上的移除方法与载荷上的护盾记录协议方法名。
const REMOVE_STATUS_METHOD: StringName = &"RemoveStatus"
const RECORD_SHIELD_ABSORPTION_METHOD: StringName = &"RecordShieldAbsorption"

## 护盾实例上的吸收量字段名。
const FIELD_SHIELD_AMOUNT: StringName = &"ShieldAmount"

## 当前剩余可吸收的伤害量。
var ShieldAmount: float = 0.0


## 构造护盾实例并立即把初始吸收量钳制到非负。
##
## @param data 状态数据资源（旧 C# 垫片或 GDScript 生产实现）。
## @param source 施加状态的来源节点。
## @param owner 状态的拥有者节点。
## @param shield_amount 初始可吸收伤害量。
## @return 无。
func _init(data: Resource, source: Node, owner: Node, shield_amount: float) -> void:
	super(data, source, owner)
	ShieldAmount = maxf(0.0, shield_amount)


## 提高扣血前阶段的执行优先级，保证护盾先于其他扣血前状态吸收伤害。
##
## @param phase 对应 StatusHookPhase 枚举整数。
## @return 该阶段的执行优先级。
func GetHookPriority(phase: int) -> int:
	if phase == PHASE_BEFORE_HEALTH_DAMAGE:
		return BEFORE_HEALTH_DAMAGE_PRIORITY

	return super.GetHookPriority(phase)


## 返回护盾在悬停提示里显示的剩余吸收量描述。
##
## @return 格式化后的剩余护盾说明。
func _get_display_description() -> String:
	return "抵挡%d点伤害" % roundi(ShieldAmount)


## 扣血前用护盾吸收伤害，并在耗尽时移除状态。
##
## @param payload 本次伤害载荷（旧 C# DamagePayload）。
## @param damage 进入修正前的伤害值。
## @return 吸收后的剩余伤害值。
func OnBeforeHealthDamage(payload: Variant, damage: float) -> float:
	if damage <= 0.0:
		return damage

	if ShieldAmount <= 0.0:
		return damage

	var absorbed: float = minf(ShieldAmount, damage)

	ShieldAmount -= absorbed
	damage -= absorbed

	# 护盾是唯一能准确声明“格挡”结果的状态；把事实写入本次载荷，避免表现层通过伤害差值猜测原因。
	_record_shield_absorption(payload, absorbed, ShieldAmount <= 0.0)

	if ShieldAmount <= 0.0:
		var status_component: Node = _get_status_component_or_null()
		if status_component != null:
			status_component.call(REMOVE_STATUS_METHOD, Id)

	return damage


## 重新施加同一状态时累加护盾吸收量。
##
## @param incoming 本次新施加进来的同 Id 状态实例。
## @return 无。
func OnReapplied(incoming: Variant) -> void:
	var incoming_object: Object = incoming as Object
	if incoming_object == null:
		return

	# 只有同样是护盾的实例才提供 ShieldAmount 字段，其他状态不得改变护盾数值。
	var raw_amount: Variant = incoming_object.get(FIELD_SHIELD_AMOUNT)
	if not (raw_amount is int or raw_amount is float):
		return

	ShieldAmount += float(raw_amount)


## 把护盾吸收结果写入载荷的表现记录。
##
## @param payload 本次伤害载荷（旧 C# DamagePayload）。
## @param absorbed 护盾本次实际吸收的伤害。
## @param was_broken 护盾是否在本次吸收后耗尽。
## @return 无。
func _record_shield_absorption(payload: Variant, absorbed: float, was_broken: bool) -> void:
	var payload_object: Object = payload as Object
	if payload_object == null:
		return

	if not payload_object.has_method(RECORD_SHIELD_ABSORPTION_METHOD):
		push_error("DamagePayload 缺少护盾吸收记录协议：%s" % RECORD_SHIELD_ABSORPTION_METHOD)
		return

	payload_object.call(RECORD_SHIELD_ABSORPTION_METHOD, absorbed, was_broken)


## 从拥有者查找状态组件。
##
## @return 状态组件节点；不存在时返回 null。
func _get_status_component_or_null() -> Node:
	if Owner == null:
		return null

	for path: String in STATUS_COMPONENT_PATHS:
		var node: Node = Owner.get_node_or_null(NodePath(path))
		if node != null:
			return node

	return Owner.get_node_or_null(STATUS_COMPONENT_UNIQUE_PATH)
