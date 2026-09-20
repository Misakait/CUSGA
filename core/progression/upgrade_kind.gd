extends RefCounted

## 可用金币升级项目枚举的 GDScript 等价实现，等价迁移自 core/progression/UpgradeKind.cs。
##
## 数值顺序与旧 C# 枚举逐字一致；旧存档与升级请求按整数记录升级项目，
## 迁移时不得插入、删除或重排成员（只能追加）。旧 C# 枚举仍保留给未迁移的 C# 进度脚本使用。
## GDScript 侧刻意为「能力式」边界：core/progression/player_progression.gd 用具名方法
## （GetWarehouseCapacity / TryUpgradeCarrySlots …）对外提供能力，界面不依赖这些整数，
## 因此本载体当前没有生产消费方；一致性由 tests/godot/test_enum_family_contract.gd 逐值锁定。

## 可用金币升级项目；0..1 分别对应原 C# UpgradeKind。
enum UpgradeKind {
	WarehouseCapacity = 0,
	CarrySlots = 1,
}
