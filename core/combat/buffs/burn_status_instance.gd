extends "res://core/combat/status/status_effect_instance.gd"

## 灼烧状态实例的生产 GDScript 实现，等价迁移自 C# BurnStatusInstance。
##
## 拥有者回合开始时按“每层伤害 × 当前层数”结算一次持续伤害；伤害载荷仍是旧 C# DamagePayload，
## 由 GDScript 构造后交给伤害接收组件的方法协议结算，与旧 C# 的构造顺序逐字一致。
## 脚本不声明 class_name，避免与 C# 类型表里的同名全局类冲突。

## 状态数据字段名，与旧 C# BurnStatusData 属性逐字一致。
const FIELD_DAMAGE_PER_STACK: StringName = &"DamagePerStack"
const FIELD_DAMAGE_TYPE: StringName = &"DamageType"
const FIELD_ELEMENT: StringName = &"Element"
const FIELD_DAMAGE_MODIFIERS: StringName = &"DamageModifiers"

## 伤害接收组件相对拥有者的路径，与旧 C# 逐字一致。
const RECEIVER_PATH: NodePath = ^"Components/DamageReceiverComponent"

## 伤害载荷脚本路径；载荷已迁移到 GDScript，旧 C# DamagePayload.cs 保留为兼容垫片。
const PAYLOAD_SCRIPT_PATH: String = "res://core/combat/damage_payload.gd"


## 拥有者回合开始时结算一次灼烧伤害。
##
## @return 无。
func OnOwnerTurnStart() -> void:
	var damage_per_stack: float = _read_float(FIELD_DAMAGE_PER_STACK)
	if damage_per_stack <= 0.0:
		return

	# 伤害接收组件已迁移到 GDScript，这里只按节点名查找并按 ReceiveDamage 方法协议调用。
	var receiver: Node = Owner.get_node_or_null(RECEIVER_PATH)
	if receiver == null:
		push_warning("%s has Burn status but no DamageReceiverComponent." % Owner.name)
		return

	var damage: float = damage_per_stack * CurrentStacks

	var payload: Object = load(PAYLOAD_SCRIPT_PATH).new()
	payload.set("Source", Source if Source != null else Owner)
	payload.set("Target", Owner)
	payload.set("Damage", int(damage))
	payload.set("Type", _read_int(FIELD_DAMAGE_TYPE))
	payload.set("Element", _read_int(FIELD_ELEMENT))
	payload.set("DamageModifiers", _read_int(FIELD_DAMAGE_MODIFIERS))

	receiver.call("ReceiveDamage", payload)

	print("[Burn] %s takes %s burn damage. Stacks=%d" % [Owner.name, damage, CurrentStacks])
