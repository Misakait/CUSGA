extends RefCounted

## 五行属性枚举的 GDScript 等价实现，等价迁移自 core/constants/ElementType.cs。
##
## 数值顺序与 ElementType.cs 完全一致；伤害载荷、元素相克表、怪物元素展示名与存档都已按
## 整数序列化，迁移时不得插入、删除或重排成员。C# 枚举仍保留给未迁移的 C# 战斗脚本使用。
## 生产消费方 core/combat/damage_payload.gd 与 core/combat/elemental_system.gd 自带同值
## ELEMENT_* 常量，一致性由 tests/godot/test_core_constants_contract.gd 逐值锁定。

## 五行属性；0..5 分别对应原 C# ElementType。
enum ElementType {
	None = 0,
	Wood = 1,
	Metal = 2,
	Water = 3,
	Earth = 4,
	Fire = 5,
}
