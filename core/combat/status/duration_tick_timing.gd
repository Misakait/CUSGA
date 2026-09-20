extends RefCounted

## 持续时间扣减时机枚举的 GDScript 等价实现，等价迁移自 core/combat/status/DurationTickTiming.cs。
##
## 数值顺序与旧 C# 枚举逐字一致；状态资源按整数序列化 TickTiming，迁移时不得插入、删除或
## 重排成员。旧 C# 枚举仍保留给未迁移的 C# 状态脚本使用。
## 生产消费方 entities/components/status_component.gd 自带同值 TIMING_* 常量，
## 一致性由 tests/godot/test_enum_family_contract.gd 逐值锁定。

## 持续时间扣减时机；0..1 分别对应原 C# DurationTickTiming。
enum DurationTickTiming {
	Start = 0,
	End = 1,
}
