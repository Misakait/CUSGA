extends RefCounted

## 持续时间过期策略枚举的 GDScript 等价实现，等价迁移自 core/combat/status/DurationExpirePolicy.cs。
##
## 数值顺序与旧 C# 枚举逐字一致；状态资源按整数序列化 ExpirePolicy，表现层按同一整数决定
## 进度条语义，迁移时不得插入、删除或重排成员。旧 C# 枚举仍保留给未迁移的 C# 状态脚本使用。
## 生产消费方 core/combat/status/status_effect_instance.gd 自带同值 EXPIRE_POLICY_* 常量，
## 一致性由 tests/godot/test_enum_family_contract.gd 逐值锁定。

## 持续时间过期策略；0..1 分别对应原 C# DurationExpirePolicy。
enum DurationExpirePolicy {
	FirstExpired = 0,
	AllExpired = 1,
}
