extends RefCounted

## 多段伤害每段目标选择模式的 GDScript 等价实现。
##
## 数值顺序与 `DamageHitTargetMode.cs` 完全一致；伤害效果资源已按整数序列化，
## 迁移时不得插入、删除或重排成员。C# 枚举仍保留给旧 C# 伤害效果实现使用。

## 每段目标的选取方式；0..1 分别对应原 C# DamageHitTargetMode。
enum DamageHitTargetMode {
	## 每一段都使用技能上下文中已经解析好的目标。
	ContextTargets = 0,
	## 每一段都从技能开始时锁定的候选池中重新随机选择一个有效目标。
	RandomCandidatePerHit = 1,
}
