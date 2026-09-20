extends Node

## 商店规则服务与 GDScript UI 之间的动态桥接节点。
##
## 该脚本只负责把目录价格、商品排序和钱包/库存节点转换到稳定协议，
## 实际买卖副作用统一委托给 ShopService，避免迁移期间出现两套交易规则。
## 旧 C# ShopTradeBridge 继续保留并拥有生产场景，直到所有调用方完成切换。

## 交易规则服务脚本；服务本身不持有场景状态。
const SHOP_SERVICE_SCRIPT: GDScript = preload("res://core/shop/shop_service.gd")

## 商品目录资源；同时接受旧 C# ShopCatalog 与 GDScript shop_catalog.gd。
@export var Catalog: Resource

## 延迟创建服务实例，允许脱离场景树的测试夹具直接调用公开方法。
var _service: RefCounted = null


## 返回可复用的交易规则服务实例。
## @return 当前桥接节点持有的 ShopService 实例。
func _service_instance() -> RefCounted:
	if _service == null:
		_service = SHOP_SERVICE_SCRIPT.new()
	return _service


## 判断物品是否可购买。
## @param item 待判断的物品 Resource。
## @return 解析出的买价为正数时返回 true。
func IsPurchasable(item: Variant) -> bool:
	return GetBuyPrice(item) > 0


## 读取物品的单价买入价。
## @param item 待读取的物品 Resource。
## @return 自身买价；无自身定价但被目录显式上架时返回目录兜底价。
func GetBuyPrice(item: Variant) -> int:
	if item == null:
		return 0

	var own_price: int = _read_int(item, &"BuyPrice", 0)
	if own_price > 0:
		return own_price

	var default_price: int = _read_int(Catalog, &"DefaultBuyPrice", 0)
	if default_price > 0 and _contains_catalog_item(item):
		return default_price
	return 0


## 读取物品的单价卖出价。
## @param item 待读取的物品 Resource。
## @return 显式卖价；缺省时按解析后的买价折半。
func GetSellPrice(item: Variant) -> int:
	if item == null:
		return 0

	var sell_price: int = _read_int(item, &"SellPrice", 0)
	if sell_price > 0:
		return sell_price

	var buy_price: int = GetBuyPrice(item)
	return buy_price / 2 if buy_price > 0 else 0


## 读取钱包余额。
## @param wallet 提供 Gold 属性的钱包节点或对象。
## @return 当前金币；对象缺失或字段无效时返回 0。
func GetGold(wallet: Variant) -> int:
	return _read_int(wallet, &"Gold", 0)


## 读取仓库中指定物品的总数量。
## @param inventory 提供 ItemCnt 方法的仓库节点或对象。
## @param item 待统计的物品 Resource。
## @return 当前持有数量；协议不完整时返回 0。
func GetItemCount(inventory: Variant, item: Variant) -> int:
	if inventory == null or item == null or not inventory is Object:
		return 0
	if not (inventory as Object).has_method("ItemCnt"):
		return 0
	return int((inventory as Object).call("ItemCnt", item))


## 构建最终商品清单。
## @param all_items ItemsControl 提供的全部物品数组。
## @return 显式商品保持目录顺序，自动补入商品按 CardId 升序且去重。
func BuildStockList(all_items: Array) -> Array:
	var result: Array = []
	var included: Array = []

	for listed: Variant in _read_resource_array(Catalog, &"Goods"):
		if _is_item_candidate(listed) and not included.has(listed):
			included.append(listed)
			result.append(listed)

	# 目录为空时保持旧行为；显式开启时再补入其余自身定价物品。
	if Catalog == null or bool(_read_value(Catalog, &"AlsoIncludeEveryPricedItem", false)):
		var auto_included: Array = []
		if all_items != null:
			for candidate: Variant in all_items:
				if _is_item_candidate(candidate) and _read_int(candidate, &"BuyPrice", 0) > 0 and not included.has(candidate):
					included.append(candidate)
					auto_included.append(candidate)
		auto_included.sort_custom(_sort_by_card_id)
		result.append_array(auto_included)

	return result


## 判断能否完成一次购买，不产生副作用。
## @param wallet 钱包对象。
## @param inventory 接收商品的仓库对象。
## @param item 要购买的商品。
## @param quantity 购买数量。
## @return 所有前置条件满足时返回 true。
func CanBuy(wallet: Variant, inventory: Variant, item: Variant, quantity: int = 1) -> bool:
	return bool(_service_instance().call("CanBuyWithPrice", wallet, inventory, item, GetBuyPrice(item), quantity))


## 判断能否完成一次出售，不产生副作用。
## @param inventory 提供物品的仓库对象。
## @param item 要出售的物品。
## @param quantity 出售数量。
## @return 持有量足够且物品可定价时返回 true。
func CanSell(inventory: Variant, item: Variant, quantity: int = 1) -> bool:
	return bool(_service_instance().call("CanSellWithPrice", inventory, item, GetSellPrice(item), quantity))


## 执行一次购买并返回固定失败码。
## @param wallet 钱包对象。
## @param inventory 接收商品的仓库对象。
## @param item 要购买的商品。
## @param quantity 购买数量。
## @return ShopFailureReason 数值；0 表示成功。
func TryBuyWithReason(wallet: Variant, inventory: Variant, item: Variant, quantity: int = 1) -> int:
	return int(_service_instance().call("TryBuyWithPrice", wallet, inventory, item, GetBuyPrice(item), quantity))


## 执行一次出售并返回固定失败码。
## @param wallet 钱包对象；保留参数位置以兼容旧 Bridge 调用协议。
## @param inventory 提供物品的仓库对象。
## @param item 要出售的物品。
## @param quantity 出售数量。
## @return ShopFailureReason 数值；0 表示成功。
func TrySellWithReason(wallet: Variant, inventory: Variant, item: Variant, quantity: int = 1) -> int:
	return int(_service_instance().call("TrySellWithPrice", wallet, inventory, item, GetSellPrice(item), quantity))


## 读取目录字段；字段不存在时返回给定回退值。
## @param value 目标对象。
## @param property_name 字段名。
## @param fallback 读取失败时的值。
## @return 字段值或回退值。
func _read_value(value: Variant, property_name: StringName, fallback: Variant) -> Variant:
	if value == null or not value is Object:
		return fallback
	var raw: Variant = (value as Object).get(property_name)
	return fallback if raw == null else raw


## 读取整数属性。
## @param value 目标对象。
## @param property_name 字段名。
## @param fallback 读取失败时的整数。
## @return 整数字段或回退值。
func _read_int(value: Variant, property_name: StringName, fallback: int) -> int:
	var raw: Variant = _read_value(value, property_name, null)
	return fallback if raw == null else int(raw)


## 读取目录中的 Resource 数组，并过滤非 Resource 元素。
## @param catalog 旧 C# 或新 GDScript 目录。
## @param property_name 数组字段名。
## @return 有效 Resource 元素数组。
func _read_resource_array(catalog: Variant, property_name: StringName) -> Array:
	var raw: Variant = _read_value(catalog, property_name, [])
	var resources: Array = []
	if not raw is Array:
		return resources
	for value: Variant in raw:
		if value is Resource:
			resources.append(value)
	return resources


## 判断资源是否具有物品数据的稳定 CardId 字段。
## @param value 待判断的资源。
## @return 能够作为商品参与排序与交易时返回 true。
func _is_item_candidate(value: Variant) -> bool:
	return value is Resource and _read_value(value, &"CardId", null) != null


## 判断目录是否显式包含同一物品实例。
## @param item 待判断的物品。
## @return 目录 Goods 中存在同一 Resource 实例时返回 true。
func _contains_catalog_item(item: Variant) -> bool:
	if item == null:
		return false
	return _read_resource_array(Catalog, &"Goods").has(item)


## 按稳定 CardId 排序自动补入的商品。
## @param left 第一个商品。
## @param right 第二个商品。
## @return left 的 CardId 排在 right 之前时返回 true。
func _sort_by_card_id(left: Variant, right: Variant) -> bool:
	return String(_read_value(left, &"CardId", &"")) < String(_read_value(right, &"CardId", &""))
