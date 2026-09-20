extends RefCounted

## 合成失败原因枚举的 GDScript 等价实现，等价迁移自 core/crafting/CraftingFailureReason.cs。
##
## 数值顺序与旧 C# 枚举逐字一致；合成失败信号与界面提示都按整数传递原因码，
## 迁移时不得插入、删除或重排成员。旧 C# 枚举仍保留给未迁移的 C# 合成脚本使用。
## 生产消费方 core/crafting/crafting_service.gd 与 entities/components/crafting_component.gd
## 各自自带同值 enum CraftingFailureReason，三份真值的一致性由
## tests/godot/test_enum_family_contract.gd 逐值锁定。

## 合成失败原因；0..4 分别对应原 C# CraftingFailureReason。
enum CraftingFailureReason {
	None = 0,
	InvalidRecipe = 1,
	InvalidQuantity = 2,
	MissingMaterials = 3,
	NotEnoughSpace = 4,
}
