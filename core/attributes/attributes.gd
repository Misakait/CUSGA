extends RefCounted

## 属性类型枚举的 GDScript 等价实现，等价迁移自 core/attributes/Attributes.cs。
##
## 旧文件同时住着 AttributeType 枚举与 Attribute 类：类本体已迁到 attribute_value.gd，
## 这里只承载枚举本体，保持「一个 C# 文件对应一个同名 GDScript」的映射。
## 数值顺序与 Attributes.cs 完全一致；Resource、存档与场景都已按整数序列化，
## 迁移时不得插入、删除或重排成员。C# 枚举仍保留给尚未迁移的 C# 组件使用。

## 属性类型；0..14 分别对应原 C# AttributeType。
enum AttributeType {
	PhysAtk = 0,
	PhysDef = 1,
	MagPower = 2,
	MagResist = 3,
	Speed = 4,
	MaxHealth = 5,
	MaxEnergy = 6,
	FixedPhysPenetration = 7,
	PhysPenetrationRate = 8,
	FixedMagicPenetration = 9,
	MagicPenetrationRate = 10,
	CritRate = 11,
	CritDamage = 12,
	EvasionRate = 13,
	LifestealRate = 14,
}
