extends RefCounted

## 属性重算作用域枚举的 GDScript 等价实现，等价迁移自 AttributeRecalculateScope.cs。
##
## 数值顺序与该文件完全一致；重算请求已按整数传递，迁移时不得插入、删除或重排成员。
## C# 枚举仍保留给尚未迁移的 C# 属性组件与状态实例使用。

## 重算作用域；0..1 分别对应原 C# AttributeRecalculateScope。
enum AttributeRecalculateScope {
	## 只重算被点名的单条属性。
	SingleAttribute = 0,
	## 重算该宿主上的全部属性。
	AllAttributes = 1,
}
