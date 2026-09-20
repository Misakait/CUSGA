extends RefCounted

## 状态变化事件的 GDScript 生产实现，等价迁移自 C# StatusChangedEvent。
##
## 事件在构造时把上下文里的数值快照下来，表现层因此不需要读取状态内部可变集合，
## 与旧 C# 的属性快照语义逐字一致。脚本不声明 class_name，避免与 C# 类型表里的同名全局类冲突。

## 跨语言可读字段名，与旧 C# 的 nameof(...) 取值逐字一致。
const FEEDBACK_OWNER: String = "Owner"
const FEEDBACK_SOURCE: String = "Source"
const FEEDBACK_STATUS_ID: String = "StatusId"
const FEEDBACK_REASON_ID: String = "ReasonId"
const FEEDBACK_CURRENT_STACKS: String = "CurrentStacks"
const FEEDBACK_OWNER_TURN_DURATION: String = "OwnerTurnDuration"
const FEEDBACK_GLOBAL_TURN_DURATION: String = "GlobalTurnDuration"
const FEEDBACK_ROUND_DURATION: String = "RoundDuration"

## 状态实例上的标识字段名；事件对外暴露的字段名是 StatusId，读取状态实例时用 Id。
const STATUS_FIELD_ID: String = "Id"

## 发生状态变化的实体。
var Owner: Node

## 施加或刷新该状态的来源实体。
var Source: Node

## 发生变化的状态标识。
var StatusId: StringName

## 状态变化原因枚举整数（StatusChangeReason）。
var Reason: int

## 变化后的当前叠层数。
var CurrentStacks: int

## 按拥有者回合计算的剩余持续时间。
var OwnerTurnDuration: int

## 按全局回合计算的剩余持续时间。
var GlobalTurnDuration: int

## 按轮次计算的剩余持续时间。
var RoundDuration: int

## 状态变化原因的稳定整数值，等价旧 C# 的 ReasonId。
var ReasonId: int:
	get:
		return Reason


## 构造状态变化事件并快照上下文中的状态数值。
##
## @param context 状态变化上下文（GDScript 生产实现或旧 C# 垫片）。
## @return 无。
func _init(context: RefCounted) -> void:
	Owner = context.get("Owner")
	Source = context.get("Source")

	var status: Variant = context.get("Status")
	StatusId = _read_status_id(status)
	Reason = int(context.get("Reason"))
	CurrentStacks = _read_int(status, FEEDBACK_CURRENT_STACKS)
	OwnerTurnDuration = _read_int(status, FEEDBACK_OWNER_TURN_DURATION)
	GlobalTurnDuration = _read_int(status, FEEDBACK_GLOBAL_TURN_DURATION)
	RoundDuration = _read_int(status, FEEDBACK_ROUND_DURATION)


## 为表现层读取整数字段提供稳定的跨语言入口。
##
## @param property_name 需要读取的字段名称。
## @return 对应的整数值；名称不受支持时返回 0。
func GetFeedbackInt(property_name: String) -> int:
	match property_name:
		FEEDBACK_REASON_ID:
			return ReasonId
		FEEDBACK_CURRENT_STACKS:
			return CurrentStacks
		FEEDBACK_OWNER_TURN_DURATION:
			return OwnerTurnDuration
		FEEDBACK_GLOBAL_TURN_DURATION:
			return GlobalTurnDuration
		FEEDBACK_ROUND_DURATION:
			return RoundDuration
		_:
			return 0


## 为表现层读取实体字段提供稳定的跨语言入口。
##
## @param property_name 需要读取的节点字段名称。
## @return 对应节点；名称不受支持时返回 null。
func GetFeedbackNode(property_name: String) -> Node:
	match property_name:
		FEEDBACK_OWNER:
			return Owner
		FEEDBACK_SOURCE:
			return Source
		_:
			return null


## 为表现层读取字符串字段提供稳定的跨语言入口。
##
## @param property_name 需要读取的字符串字段名称。
## @return 对应字符串；名称不受支持时返回空字符串。
func GetFeedbackString(property_name: String) -> String:
	if property_name == FEEDBACK_STATUS_ID:
		return String(StatusId)
	return ""


## 读取状态实例上的整数字段。
##
## @param status 状态实例（任意语言实现）。
## @param field 字段名。
## @return 字段整数；实例或字段缺失时返回 0。
func _read_int(status: Variant, field: String) -> int:
	var target: Object = status as Object
	if target == null:
		return 0

	var value: Variant = target.get(field)
	if value is int:
		return value
	if value is float:
		return int(value)
	return 0


## 读取状态实例的状态标识。
##
## @param status 状态实例（任意语言实现）。
## @return 状态标识；实例或字段缺失时返回空 StringName。
func _read_status_id(status: Variant) -> StringName:
	var target: Object = status as Object
	if target == null:
		return &""

	var value: Variant = target.get(STATUS_FIELD_ID)
	if value == null:
		return &""
	return StringName(value)
