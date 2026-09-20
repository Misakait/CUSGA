extends RefCounted

## 属性变化原因枚举的 GDScript 等价实现，等价迁移自 AttributeChangeReason.cs。
##
## 数值顺序与该文件完全一致；重算请求、属性变化事件与状态钩子都已按整数传递原因，
## 迁移时不得插入、删除或重排成员。C# 枚举仍保留给尚未迁移的 C# 状态实例使用。
## attribute_component.gd 的 REASON_* 常量必须与本枚举逐值一致（契约测试锁定）。

## 属性变化原因；0..5 分别对应原 C# AttributeChangeReason。
enum AttributeChangeReason {
	## 组件初始化时的首次写入。
	Initialization = 0,
	## 玩家投入属性点变化。
	AllocatedPointChanged = 1,
	## 天赋、装备、永久药水等永久加成变化。
	PermanentBonusChanged = 2,
	## 基础值被直接改写。
	BaseValueChanged = 3,
	## 状态（Buff / Debuff）带来的变化。
	StatusChanged = 4,
	## 外部强制全量重算。
	ForcedRecalculation = 5,
}
