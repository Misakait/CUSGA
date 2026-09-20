extends RefCounted

## 商店买卖规则的并行 GDScript 实现。
##
## 服务不持有钱包、库存或交易状态；所有外部依赖都通过稳定的属性/方法协议访问，
## 因而可以在迁移期间同时接收旧 C# 节点和并行 GDScript 节点。

## 与 C# ShopFailureReason 保持相同整数值，旧存档/UI 映射不得重排。
enum ShopFailureReason {
	None = 0,
	InvalidItem = 1,
	InvalidQuantity = 2,
	NotEnoughGold = 3,
	NotEnoughSpace = 4,
	MissingItem = 5,
	NotConfigured = 6,
}

## 最近一次带原因交易的结果码；成功时为 None。
var LastFailureReason: int = ShopFailureReason.None


## 判断物品是否配置了正数买入价。
## @param item 待判断的物品 Resource。
## @return 物品存在且 BuyPrice 大于 0 时返回 true。
func IsPurchasable(item: Variant) -> bool:
	return item != null and _read_int(item, "BuyPrice", 0) > 0


## 解析卖出单价，优先使用显式 SellPrice，缺失时按买价折半。
## @param item 待解析的物品 Resource。
## @return 有效卖出单价；不可出售时返回 0。
func ResolveSellPrice(item: Variant) -> int:
	if item == null:
		return 0
	var sell_price: int = _read_int(item, "SellPrice", 0)
	if sell_price > 0:
		return sell_price
	var buy_price: int = _read_int(item, "BuyPrice", 0)
	return buy_price / 2 if buy_price > 0 else 0


## 按物品自身买价判断是否可以购买。
## @param wallet 提供 Gold 属性的钱包节点。
## @param inventory 提供 CanAddItem 的库存节点。
## @param item 商品 Resource。
## @param quantity 购买数量，默认 1。
## @return 所有前置条件满足时返回 true。
func CanBuy(wallet: Variant, inventory: Variant, item: Variant, quantity: int = 1) -> bool:
	return _validate_buy(wallet, inventory, item, _read_int(item, "BuyPrice", 0), quantity).get("ok", false)


## 按指定单价判断是否可以购买，供目录兜底价格使用。
## @param wallet 提供 Gold 属性的钱包节点。
## @param inventory 接收商品的库存节点。
## @param item 商品 Resource。
## @param unit_price 单件买价。
## @param quantity 购买数量。
## @return 所有前置条件满足时返回 true。
func CanBuyWithPrice(wallet: Variant, inventory: Variant, item: Variant, unit_price: int, quantity: int) -> bool:
	return _validate_buy(wallet, inventory, item, unit_price, quantity).get("ok", false)


## 按物品自身买价执行购买并返回失败码。
## @param wallet 提供 Gold/TrySpend/Add 的钱包节点。
## @param inventory 提供 CanAddItem/AddItem 的库存节点。
## @param item 商品 Resource。
## @param quantity 购买数量。
## @return ShopFailureReason 整数值；成功为 0。
func TryBuyWithReason(wallet: Variant, inventory: Variant, item: Variant, quantity: int = 1) -> int:
	return TryBuyWithPrice(wallet, inventory, item, _read_int(item, "BuyPrice", 0), quantity)


## 按指定单价执行购买，确保失败时钱包和库存都不变。
## @param wallet 提供 Gold/TrySpend/Add 的钱包节点。
## @param inventory 提供 CanAddItem/AddItem 的库存节点。
## @param item 商品 Resource。
## @param unit_price 单件买价。
## @param quantity 购买数量。
## @return ShopFailureReason 整数值；成功为 0。
func TryBuyWithPrice(wallet: Variant, inventory: Variant, item: Variant, unit_price: int, quantity: int) -> int:
	var validation: Dictionary = _validate_buy(wallet, inventory, item, unit_price, quantity)
	if not bool(validation.get("ok", false)):
		return _remember_reason(int(validation.get("reason", ShopFailureReason.NotConfigured)))
	var total_price: int = int(validation["total"])
	if not wallet.has_method("TrySpend") or not bool(wallet.call("TrySpend", total_price)):
		return _remember_reason(ShopFailureReason.NotEnoughGold)
	var remaining: int = int(inventory.call("AddItem", item, quantity))
	if remaining > 0:
		# 这是库存预检与实际写入不一致的纵深防御分支，必须退回整笔款项。
		if wallet.has_method("Add"):
			wallet.call("Add", total_price)
		push_error("ShopService: 购买预检与库存写入不一致，已退回金币。")
		return _remember_reason(ShopFailureReason.NotEnoughSpace)
	return _remember_reason(ShopFailureReason.None)


## 按物品自身卖价判断是否可以出售。
## @param wallet 未使用但保留参数位置以对应 C# 服务调用边界。
## @param inventory 提供 ItemCnt 的库存节点。
## @param item 待出售物品。
## @param quantity 出售数量，默认 1。
## @return 持有量与价格均满足时返回 true。
func CanSell(_wallet: Variant, inventory: Variant, item: Variant, quantity: int = 1) -> bool:
	return _validate_sell(inventory, item, ResolveSellPrice(item), quantity).get("ok", false)


## 按指定单价判断是否可以出售。
## @param inventory 提供 ItemCnt 的库存节点。
## @param item 待出售物品。
## @param unit_price 单件卖价。
## @param quantity 出售数量。
## @return 持有量与价格均满足时返回 true。
func CanSellWithPrice(inventory: Variant, item: Variant, unit_price: int, quantity: int) -> bool:
	return _validate_sell(inventory, item, unit_price, quantity).get("ok", false)


## 按物品自身卖价执行出售并返回失败码。
## @param wallet 提供 Add 的钱包节点。
## @param inventory 提供 TryRemoveItem/ItemCnt 的库存节点。
## @param item 待出售物品。
## @param quantity 出售数量。
## @return ShopFailureReason 整数值；成功为 0。
func TrySellWithReason(wallet: Variant, inventory: Variant, item: Variant, quantity: int = 1) -> int:
	return TrySellWithPrice(wallet, inventory, item, ResolveSellPrice(item), quantity)


## 按指定单价执行出售，先移除物品再增加金币。
## @param wallet 提供 Add 的钱包节点。
## @param inventory 提供 TryRemoveItem/ItemCnt 的库存节点。
## @param item 待出售物品。
## @param unit_price 单件卖价。
## @param quantity 出售数量。
## @return ShopFailureReason 整数值；成功为 0。
func TrySellWithPrice(wallet: Variant, inventory: Variant, item: Variant, unit_price: int, quantity: int) -> int:
	if wallet == null or not wallet.has_method("Add"):
		return _remember_reason(ShopFailureReason.NotConfigured)
	var validation: Dictionary = _validate_sell(inventory, item, unit_price, quantity)
	if not bool(validation.get("ok", false)):
		return _remember_reason(int(validation.get("reason", ShopFailureReason.NotConfigured)))
	if inventory == null or not inventory.has_method("TryRemoveItem") or not bool(inventory.call("TryRemoveItem", item, quantity)):
		return _remember_reason(ShopFailureReason.MissingItem)
	wallet.call("Add", int(validation["total"]))
	return _remember_reason(ShopFailureReason.None)


## 集中校验购买条件，保证 CanBuy 与 TryBuy 使用同一规则。
func _validate_buy(wallet: Variant, inventory: Variant, item: Variant, unit_price: int, quantity: int) -> Dictionary:
	if wallet == null or inventory == null:
		return {"ok": false, "reason": ShopFailureReason.NotConfigured, "total": 0}
	if item == null or unit_price <= 0:
		return {"ok": false, "reason": ShopFailureReason.InvalidItem, "total": 0}
	if quantity <= 0:
		return {"ok": false, "reason": ShopFailureReason.InvalidQuantity, "total": 0}
	var total: int = _safe_total(unit_price, quantity)
	if total <= 0:
		return {"ok": false, "reason": ShopFailureReason.InvalidQuantity, "total": 0}
	if _read_int(wallet, "Gold", 0) < total:
		return {"ok": false, "reason": ShopFailureReason.NotEnoughGold, "total": 0}
	if not inventory.has_method("CanAddItem") or not bool(inventory.call("CanAddItem", item, quantity)):
		return {"ok": false, "reason": ShopFailureReason.NotEnoughSpace, "total": 0}
	return {"ok": true, "reason": ShopFailureReason.None, "total": total}


## 集中校验出售条件，保证 CanSell 与 TrySell 使用同一规则。
func _validate_sell(inventory: Variant, item: Variant, unit_price: int, quantity: int) -> Dictionary:
	if inventory == null:
		return {"ok": false, "reason": ShopFailureReason.NotConfigured, "total": 0}
	if item == null or unit_price <= 0:
		return {"ok": false, "reason": ShopFailureReason.InvalidItem, "total": 0}
	if quantity <= 0:
		return {"ok": false, "reason": ShopFailureReason.InvalidQuantity, "total": 0}
	var total: int = _safe_total(unit_price, quantity)
	if total <= 0:
		return {"ok": false, "reason": ShopFailureReason.InvalidQuantity, "total": 0}
	if not inventory.has_method("ItemCnt") or int(inventory.call("ItemCnt", item)) < quantity:
		return {"ok": false, "reason": ShopFailureReason.MissingItem, "total": 0}
	return {"ok": true, "reason": ShopFailureReason.None, "total": total}


## 以 64 位中间值检查总价，超过 C# int 上限时返回 0。
func _safe_total(unit_price: int, quantity: int) -> int:
	var total: int = unit_price * quantity
	return 0 if total <= 0 or total > 2147483647 else total


## 读取整数属性，隔离旧 C# 与新 GDScript 对象。
func _read_int(value: Variant, property_name: StringName, fallback: int) -> int:
	if not (value is Object):
		return fallback
	var raw: Variant = (value as Object).get(String(property_name))
	return fallback if raw == null else int(raw)


## 保存最近一次交易结果码并返回。
func _remember_reason(reason: int) -> int:
	LastFailureReason = reason
	return reason
