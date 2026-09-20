extends Resource

## 描述商店显式上架的商品，以及未定价商品的兜底买价。
##
## 目录只保存序列化配置；商品筛选、价格解析和交易副作用仍由 ShopTradeBridge
## 与 ShopService 负责。Goods 使用通用 Resource，允许迁移期间继续接收 C# ItemData。

## 显式上架的商品清单，数组顺序就是商店货架顺序。
@export var Goods: Array[Resource] = []

## 是否在显式清单之外自动补入所有配置了正数买价的物品。
@export var AlsoIncludeEveryPricedItem: bool = false

## 显式上架但没有自身买价时使用的兜底价格。
@export_range(0, 999999, 1, "or_greater") var DefaultBuyPrice: int = 100


## 判断物品是否被本目录显式上架。
##
## @param item 待判断的物品资源。
## @return 物品非空且出现在 Goods 中时返回 true。
func ContainsExplicitly(item: Resource) -> bool:
	if item == null:
		return false

	for listed: Resource in Goods:
		if listed == item:
			return true

	return false
