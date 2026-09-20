extends RefCounted

## 属性变化方向枚举的 GDScript 等价实现，等价迁移自 AttributeChangeDirection.cs。
##
## 数值顺序与该文件完全一致；属性变化上下文已按整数传递方向，
## 迁移时不得插入、删除或重排成员。C# 枚举仍保留给尚未迁移的 C# 状态钩子使用。
## attribute_change_context.gd 的 DIRECTION_* 常量必须与本枚举逐值一致（契约测试锁定）。

## 属性变化方向；0..2 分别对应原 C# AttributeChangeDirection。
enum AttributeChangeDirection {
	## 任意方向都触发。
	Any = 0,
	## 只在最终值上升时触发。
	Increase = 1,
	## 只在最终值下降时触发。
	Decrease = 2,
}
