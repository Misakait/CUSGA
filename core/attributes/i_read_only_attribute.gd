extends RefCounted

## 只读属性视图的 GDScript 协议说明，等价迁移自 core/attributes/IReadOnlyAttribute.cs。
##
## GDScript 没有接口类型，所以这里不造一个“什么都不做”的空实现，而是把旧 C# 接口的
## 成员面写成可被契约测试与调用方读取的稳定描述：任何同时提供 REQUIRED_MEMBERS
## 全部成员的 RefCounted 就是等价实现，当前生产实现是 attribute_value.gd。
## C# 接口仍保留给尚未迁移的 C# 属性组件与状态实例使用。

## 只读属性视图必须提供的成员名；顺序与旧 C# IReadOnlyAttribute 的声明顺序一致。
const REQUIRED_MEMBERS: Array[StringName] = [
	&"Type",
	&"DisplayName",
	&"BaseValue",
	&"BonusValue",
	&"AllocatedPoints",
	&"GrowthPerPoint",
	&"RawValue",
]
