extends RefCounted

## 技能效果目标范围枚举的 GDScript 等价实现。
##
## 数值顺序与 `SkillEffectTargetScope.cs` 完全一致；场景与 Resource 已按整数序列化，
## 迁移时不得插入、删除或重排成员。C# 枚举仍保留给尚未迁移的 C# 效果实现使用。

## 效果作用的目标范围；0..3 分别对应原 C# SkillEffectTargetScope。
enum SkillEffectTargetScope {
	Source = 0,
	AllTargets = 1,
	PrimaryOnly = 2,
	SecondaryOnly = 3,
}
