extends RefCounted

## 商店交易失败原因枚举的 GDScript 等价实现，等价迁移自 core/shop/ShopFailureReason.cs。
##
## 数值顺序与旧 C# 枚举逐字一致；交易结果与界面提示文案都按整数映射失败原因，
## 迁移时不得插入、删除或重排成员（只能追加）。旧 C# 枚举仍保留给未迁移的 C# 商店脚本使用。
## 生产消费方 core/shop/shop_service.gd 自带同值 enum ShopFailureReason，一致性由
## tests/godot/test_enum_family_contract.gd 逐值锁定。

## 商店交易失败原因；0..6 分别对应原 C# ShopFailureReason。
enum ShopFailureReason {
	None = 0,
	InvalidItem = 1,
	InvalidQuantity = 2,
	NotEnoughGold = 3,
	NotEnoughSpace = 4,
	MissingItem = 5,
	NotConfigured = 6,
}
