extends RefCounted

## 装备系统跨语言共享的稳定枚举值。
##
## 数值顺序与 `EquipmentTypes.cs` 完全一致；场景和 Resource 已按整数序列化，迁移时不得
## 插入、删除或重排成员。C# 枚举仍保留给尚未迁移的运行时组件使用。

## 装备槽位；0..15 分别对应原 C# EquipmentSlot。
enum EquipmentSlot {
	Helmet = 0,
	Chest = 1,
	Legs = 2,
	Boots = 3,
	Weapon = 4,
	Axe = 5,
	Pickaxe = 6,
	FishingRod = 7,
	LeftHandguard = 8,
	RightHandguard = 9,
	Torch = 10,
	Pendant = 11,
	Ring1 = 12,
	Ring2 = 13,
	Belt = 14,
	MagicItem = 15,
}

## 装备套装类型；0..3 分别对应原 C# EquipmentSet。
enum EquipmentSet {
	None = 0,
	Wooden = 1,
	Stone = 2,
	Iron = 3,
}
