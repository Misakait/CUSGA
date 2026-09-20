extends RefCounted

## 属性变化上下文，等价迁移自 core/attributes/AttributeChangeContext.cs。
##
## 属性组件与状态实例都可能来自任一语言，因此字段名、方法名与旧 C# 逐字一致：
## 变化前的拦截方（状态实例）可直接改写 NewValue，或调用 Cancel() 取消本次变化。

## 变化方向枚举，等价旧 C# AttributeChangeDirection。
const DIRECTION_ANY: int = 0
const DIRECTION_INCREASE: int = 1
const DIRECTION_DECREASE: int = 2

## 属性宿主组件节点。
var Owner: Node = null
## 变化来源节点。
var Source: Node = null
## 属性类型整数值。
var Type: int = 0
## 变化原因整数值。
var Reason: int = 0
## 属性类型整数值，等价旧 C# TypeId。
var TypeId: int = 0
## 变化原因整数值，等价旧 C# ReasonId。
var ReasonId: int = 0
## 变化前的最终值。
var OldValue: float = 0.0
## 拦截前的候选最终值。
var OriginalNewValue: float = 0.0
## 当前候选最终值，可被拦截方改写。
var NewValue: float = 0.0
## 是否已被拦截取消。
var IsCancelled: bool = false

## 本次变化的差值。
var Delta: float:
	get:
		return NewValue - OldValue
## 是否为提升。
var IsIncrease: bool:
	get:
		return Delta > 0.0
## 是否为降低。
var IsDecrease: bool:
	get:
		return Delta < 0.0


## 初始化上下文。
##
## @param owner 属性宿主组件节点。
## @param source 变化来源节点。
## @param type 属性类型整数值。
## @param reason 变化原因整数值。
## @param old_value 变化前的最终值。
## @param new_value 拦截前的候选最终值。
## @return 无返回值。
func Initialize(
	owner: Node, source: Node, type: int, reason: int, old_value: float, new_value: float
) -> void:
	Owner = owner
	Source = source
	Type = type
	Reason = reason
	TypeId = type
	ReasonId = reason
	OldValue = old_value
	OriginalNewValue = new_value
	NewValue = new_value
	IsCancelled = false


## 取消本次属性变化。
##
## @return 无返回值。
func Cancel() -> void:
	IsCancelled = true


## 判断本次变化方向是否匹配给定方向枚举。
##
## @param direction 旧 C# AttributeChangeDirection 整数值。
## @return 匹配时返回 true。
func MatchesDirection(direction: int) -> bool:
	if direction == DIRECTION_ANY:
		return true

	if direction == DIRECTION_INCREASE:
		return IsIncrease

	if direction == DIRECTION_DECREASE:
		return IsDecrease

	return false
