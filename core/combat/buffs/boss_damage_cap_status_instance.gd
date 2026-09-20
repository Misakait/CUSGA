extends "res://core/combat/status/status_effect_instance.gd"

## Boss 单次扣血上限状态实例的生产 GDScript 实现，等价迁移自 C# BossDamageCapStatusInstance。
##
## 生命组件已迁移到 GDScript，这里只按稳定属性读取上限，再把本次伤害钳制到
## “当前最大生命 × MaxHealthDamageRatio”，并把因上限削减的数值写回本次载荷的表现记录。
## 脚本不声明 class_name，避免与 C# 类型表里的同名全局类冲突。

## 状态数据上的单次扣血上限比例字段名。
const FIELD_MAX_HEALTH_DAMAGE_RATIO: StringName = &"MaxHealthDamageRatio"

## 生命组件相对拥有者的路径，与旧 C# GetNodeOrNull("HealthComponent") 逐字一致。
const HEALTH_COMPONENT_PATH: NodePath = ^"HealthComponent"

## 生命组件上的最大生命字段名。
const FIELD_MAX_VALUE: StringName = &"MaxValue"

## 扣血前阶段枚举整数（StatusHookPhase.BeforeHealthDamage）。
const PHASE_BEFORE_HEALTH_DAMAGE: int = 7

## 扣血前阶段的执行优先级，与旧 C# 逐字一致。
const BEFORE_HEALTH_DAMAGE_PRIORITY: int = 1000

## 载荷上的伤害上限记录协议方法名。
const RECORD_DAMAGE_CAP_METHOD: StringName = &"RecordDamageCap"


## 提高扣血前阶段的执行优先级，保证先按上限钳制再交给其他扣血前状态处理。
##
## @param phase 对应 StatusHookPhase 枚举整数。
## @return 该阶段的执行优先级。
func GetHookPriority(phase: int) -> int:
	if phase == PHASE_BEFORE_HEALTH_DAMAGE:
		return BEFORE_HEALTH_DAMAGE_PRIORITY

	return super.GetHookPriority(phase)


## 扣血前把本次伤害钳制到单次上限，并记录被削减的数值。
##
## @param payload 本次伤害载荷（旧 C# DamagePayload）。
## @param damage 进入修正前的伤害值。
## @return 钳制后的伤害值；缺少生命组件或上限为 0 时原样返回。
func OnBeforeHealthDamage(payload: Variant, damage: float) -> float:
	if damage <= 0.0:
		return damage

	var health: Node = Owner.get_node_or_null(HEALTH_COMPONENT_PATH)
	if health == null:
		push_warning("%s has BossDamageCap but no HealthComponent." % Owner.name)
		return damage

	var max_value: Variant = health.get(FIELD_MAX_VALUE)
	var current_max_value: float = 0.0
	if max_value is int or max_value is float:
		current_max_value = float(max_value)

	var max_allowed_damage: float = current_max_value * _read_float(
		FIELD_MAX_HEALTH_DAMAGE_RATIO
	)
	var uncapped_damage: float = damage
	var capped_damage: float = minf(damage, max_allowed_damage)

	# 伤害上限与护盾都发生在扣血前，但它们的表现语义不同，必须分开记录。
	_record_damage_cap(payload, uncapped_damage - capped_damage)
	return capped_damage


## 把因单次伤害上限削减的数值写入载荷的表现记录。
##
## @param payload 本次伤害载荷（旧 C# DamagePayload）。
## @param reduced_damage 因上限而未进入后续结算的伤害量。
## @return 无。
func _record_damage_cap(payload: Variant, reduced_damage: float) -> void:
	var payload_object: Object = payload as Object
	if payload_object == null:
		return

	if not payload_object.has_method(RECORD_DAMAGE_CAP_METHOD):
		push_error("DamagePayload 缺少伤害上限记录协议：%s" % RECORD_DAMAGE_CAP_METHOD)
		return

	payload_object.call(RECORD_DAMAGE_CAP_METHOD, reduced_damage)
