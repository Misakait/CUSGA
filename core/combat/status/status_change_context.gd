extends RefCounted

## 状态变化上下文的 GDScript 生产实现，等价迁移自 C# StatusChangeContext。
##
## 这是跨语言载荷：状态组件构造它，表现层与属性组件读取它。旧 C# 版本把 Status 字段声明为
## StatusEffectInstance，而本批已把状态实例迁到 GDScript，GDScript 实例无法满足该强类型，
## 因此上下文同步迁到 GDScript：两侧状态实例（C# 垫片或 GDScript 生产实现）都能被同一套
## 字段协议承载。脚本不声明 class_name，避免与 C# 类型表里的同名全局类冲突。

## 发生状态变化的实体。
var Owner: Node

## 施加或刷新该状态的来源实体。
var Source: Node

## 发生变化的状态实例（旧 C# 垫片或 GDScript 生产实现）。
var Status: RefCounted

## 状态变化原因枚举整数（StatusChangeReason）。
var Reason: int


## 构造状态变化上下文。
##
## @param owner 发生状态变化的实体。
## @param source 施加或刷新该状态的来源实体。
## @param status 发生变化的状态实例。
## @param reason 状态变化原因枚举整数（StatusChangeReason）。
## @return 无。
func _init(owner: Node, source: Node, status: RefCounted, reason: int) -> void:
	Owner = owner
	Source = source
	Status = status
	Reason = reason
