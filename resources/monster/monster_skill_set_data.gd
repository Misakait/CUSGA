extends Resource

## 描述怪物可使用的战斗技能集合。
##
## 使用通用 Resource 数组保持与旧 C# MonsterSkillEntryData 的字段协议一致，
## 同时允许技能条目在 GDScript 迁移阶段独立加载。

## 按配置顺序保存的怪物技能条目。
@export var Skills: Array[Resource] = []
