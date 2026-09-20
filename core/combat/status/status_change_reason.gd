extends RefCounted

## 状态变化原因枚举的 GDScript 等价实现，等价迁移自 core/combat/status/StatusChangeReason.cs。
##
## 数值顺序与旧 C# 枚举逐字一致；状态变化事件（StatusChangedEvent）与会话日志都按整数记录
## 变化原因，迁移时不得插入、删除或重排成员。旧 C# 枚举仍保留给未迁移的 C# 状态脚本使用。
## 生产消费方 entities/components/status_component.gd 自带同值 REASON_* 常量（旧实现的
## Cleared=6 在该文件里只有注释、没有常量），两侧一致性由
## tests/godot/test_enum_family_contract.gd 逐值锁定。

## 状态变化原因；0..6 分别对应原 C# StatusChangeReason。
enum StatusChangeReason {
	Applied = 0,
	Removed = 1,
	Refreshed = 2,
	StackChanged = 3,
	DurationTicked = 4,
	StackExpired = 5,
	Cleared = 6,
}
