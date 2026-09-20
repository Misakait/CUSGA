extends RefCounted

## 属性重算请求的 GDScript 等价实现，等价迁移自 AttributeRecalculateRequest.cs。
##
## 旧 C# 用私有构造 + 静态工厂 Single / All 生成只读请求，并把可选副作用包成 Action。
## GDScript 没有 Action，这里用 Callable 表达同一语义：请求字段仍然只读，
## ApplyMutation() 在未提供 Callable 时什么都不做，与旧 C# 的可空 Action 一致。
## 字段名与旧 C# 逐字一致（Scope / Type / Source / Reason / AllowInterception / EmitEvents）。
## 不声明 class_name，避免与仍在使用的 C# 全局类型重名。

## 本脚本路径：静态工厂在没有 class_name 的前提下必须靠它构造实例。
const SELF_PATH: String = "res://core/attributes/attribute_recalculate_request.gd"

## 重算作用域整数，等价旧 C# AttributeRecalculateScope。
const SCOPE_SINGLE_ATTRIBUTE: int = 0
const SCOPE_ALL_ATTRIBUTES: int = 1

## 重算作用域（AttributeRecalculateScope 枚举整数）。
var Scope: int = SCOPE_SINGLE_ATTRIBUTE
## 单属性重算时的目标属性类型；全量重算时保持旧 C# 默认值 0（PhysAtk）。
var Type: int = 0
## 发起重算的节点。
var Source: Node = null
## 重算原因（AttributeChangeReason 枚举整数）。
var Reason: int = 0
## 是否允许状态实例拦截本次变化。
var AllowInterception: bool = true
## 是否对外发送变化事件。
var EmitEvents: bool = true
## 请求携带的可选副作用，等价旧 C# 私有字段 Action _mutation。
var _mutation: Variant = null


## 构造一条重算请求。
##
## 构造保持“私有”：调用方应走 Single / All 工厂，与旧 C# 的可见性完全一致。
##
## @param scope 重算作用域整数。
## @param type 目标属性类型整数。
## @param source 发起节点。
## @param reason 重算原因整数。
## @param mutation 可选副作用 Callable。
## @param allow_interception 是否允许拦截。
## @param emit_events 是否发送事件。
## @return 无返回值。
func _init(
	scope: int,
	type: int,
	source: Node,
	reason: int,
	mutation: Variant,
	allow_interception: bool,
	emit_events: bool
) -> void:
	Scope = scope
	Type = type
	Source = source
	Reason = reason
	_mutation = mutation
	AllowInterception = allow_interception
	EmitEvents = emit_events


## 构造单属性重算请求，等价旧 C# RecalculateRequest.Single。
##
## @param type 目标属性类型整数。
## @param source 发起节点。
## @param reason 重算原因整数。
## @param mutation 可选副作用 Callable。
## @param allow_interception 是否允许拦截，默认允许。
## @param emit_events 是否发送事件，默认发送。
## @return 作用域为 SingleAttribute 的重算请求。
static func Single(
	type: int,
	source: Node,
	reason: int,
	mutation: Variant = null,
	allow_interception: bool = true,
	emit_events: bool = true
) -> RefCounted:
	return load(SELF_PATH).new(
		SCOPE_SINGLE_ATTRIBUTE, type, source, reason, mutation, allow_interception, emit_events
	)


## 构造全量重算请求，等价旧 C# RecalculateRequest.All。
##
## 旧 C# 的 All 走 type: default，即 AttributeType.PhysAtk = 0，这里保持同一取值，
## 避免全量请求的目标类型与旧实现出现差异。
##
## @param source 发起节点。
## @param reason 重算原因整数。
## @param mutation 可选副作用 Callable。
## @param allow_interception 是否允许拦截，默认允许。
## @param emit_events 是否发送事件，默认发送。
## @return 作用域为 AllAttributes 的重算请求。
static func All(
	source: Node,
	reason: int,
	mutation: Variant = null,
	allow_interception: bool = true,
	emit_events: bool = true
) -> RefCounted:
	return load(SELF_PATH).new(
		SCOPE_ALL_ATTRIBUTES, 0, source, reason, mutation, allow_interception, emit_events
	)


## 执行请求携带的副作用，等价旧 C# ApplyMutation。
##
## @return 无返回值。
func ApplyMutation() -> void:
	if typeof(_mutation) != TYPE_CALLABLE:
		return

	# 显式转成 Callable，避免用 Variant 直接 call() 在参数错误时给出难以定位的报错。
	var mutation: Callable = _mutation
	if mutation.is_valid():
		mutation.call()
