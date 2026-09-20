extends RefCounted

## 状态叠加策略枚举的 GDScript 等价实现，等价迁移自 core/combat/status/StackPolicy.cs。
##
## 数值顺序与旧 C# 枚举逐字一致；状态资源（StatusEffectData）按整数序列化 Policy，
## 迁移时不得插入、删除或重排成员。旧 C# 枚举仍保留给未迁移的 C# 状态脚本使用。
## 生产消费方 entities/components/status_component.gd 自带同值 POLICY_* 常量与
## resources 侧 status_effect_data.gd 的整数默认值，一致性由
## tests/godot/test_enum_family_contract.gd 逐值锁定。

## 状态叠加策略；0..2 分别对应原 C# StackPolicy。
enum StackPolicy {
	ResetDuration = 0,
	AddDuration = 1,
	AddStackOnly = 2,
}
