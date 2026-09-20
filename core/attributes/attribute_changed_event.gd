extends RefCounted

## 属性变化事件载荷，等价迁移自 core/attributes/AttributeChangedEvent.cs。
##
## AttributeChanged 信号的生产消费方（属性摘要、角色属性、战斗管理器）都按
## TypeId / OldValue / NewValue 这类稳定字段名读取，因此这里逐字保留同一字段面。

## 属性宿主组件节点。
var Owner: Node = null
## 变化来源节点。
var Source: Node = null
## 属性类型整数值。
var Type: int = 0
## 属性类型整数值，等价旧 C# TypeId。
var TypeId: int = 0
## 变化原因整数值。
var Reason: int = 0
## 变化原因整数值，等价旧 C# ReasonId。
var ReasonId: int = 0
## 变化前的最终值。
var OldValue: float = 0.0
## 变化后的最终值。
var NewValue: float = 0.0

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


## 从属性变化上下文初始化事件载荷。
##
## @param context 旧 C# 或 GDScript 的属性变化上下文。
## @return 无返回值。
func Initialize(context: RefCounted) -> void:
	Owner = context.get("Owner") as Node
	Source = context.get("Source") as Node
	Type = int(context.get("Type"))
	TypeId = Type
	Reason = int(context.get("Reason"))
	ReasonId = Reason
	OldValue = float(context.get("OldValue"))
	NewValue = float(context.get("NewValue"))
