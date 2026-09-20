extends RefCounted

## 技能目标角色枚举的 GDScript 等价实现。
##
## 数值顺序与 `SkillTargetRole.cs` 完全一致；技能目标条目已按整数序列化，
## 迁移时不得插入、删除或重排成员。C# 枚举仍保留给旧 C# 目标条目与工具类使用。

## 目标在技能中的角色；0..1 分别对应原 C# SkillTargetRole。
enum SkillTargetRole {
	Primary = 0,
	Secondary = 1,
}
