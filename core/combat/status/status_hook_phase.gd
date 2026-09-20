extends RefCounted

## 状态 Hook 阶段枚举的 GDScript 等价实现，等价迁移自 core/combat/status/StatusHookPhase.cs。
##
## 数值顺序与旧 C# 枚举逐字一致；状态脚本按阶段整数注册与分发 Hook，顺序同时决定同优先级
## Hook 的稳定排序，迁移时不得插入、删除或重排成员。旧 C# 枚举仍保留给未迁移的 C# 状态脚本使用。
## 生产消费方 entities/components/status_component.gd 自带同值 PHASE_* 常量（0..15 全覆盖），
## 一致性由 tests/godot/test_enum_family_contract.gd 逐值锁定。

## 状态 Hook 阶段；0..15 分别对应原 C# StatusHookPhase。
enum StatusHookPhase {
	BeforeAttributeChange = 0,
	AfterAttributeChanged = 1,
	ModifyOutgoingDamage = 2,
	ModifyIncomingDamageBeforeMitigation = 3,
	ModifyIncomingDamageAfterMitigation = 4,
	ModifyDamageHitCount = 5,
	ModifyDamageEffectSegmentDamage = 6,
	BeforeHealthDamage = 7,
	BeforeSkillExecution = 8,
	AfterSkillExecution = 9,
	GlobalTurnStart = 10,
	OwnerTurnStart = 11,
	GlobalTurnEnd = 12,
	OwnerTurnEnd = 13,
	RoundStart = 14,
	RoundEnd = 15,
}
