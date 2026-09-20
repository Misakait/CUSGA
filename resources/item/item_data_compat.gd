extends RefCounted

## 物品数据的跨语言读取边界。
##
## 普通生产物品、ResourceCardData 与 SkillCardData 由 GDScript Resource 提供；
## 装备、工具与迁移期测试输入仍可由 C# 派生类型提供。
## 本工具只读取稳定字段，不包装或复制原 Resource，避免改变 ItemStack 依赖的对象身份。

## 判断资源是否具备 ItemData 的稳定字段集合。
static func is_item_resource(value: Variant) -> bool:
	if not (value is Resource):
		return false
	var item: Resource = value as Resource
	return _has_property(item, &"CardId") \
		and _has_property(item, &"CardName") \
		and _has_property(item, &"MaxStackSize") \
		and _has_property(item, &"ItemTags") \
		and _has_property(item, &"BuyPrice") \
		and _has_property(item, &"SellPrice")

## 读取稳定卡牌标识；资源缺失或字段为空时返回调用方提供的回退值。
static func get_card_id(item: Variant, fallback: StringName = &"") -> StringName:
	var value: Variant = _get_property(item, &"CardId")
	return fallback if value == null else StringName(value)

## 读取展示名称，优先使用显示属性，再回退到序列化的 CardName。
static func get_display_name(item: Variant, fallback: String = "") -> String:
	var display_name: Variant = _get_property(item, &"DisplayName")
	if display_name != null and not String(display_name).is_empty():
		return String(display_name)
	var card_name: Variant = _get_property(item, &"CardName")
	return fallback if card_name == null or String(card_name).is_empty() else String(card_name)

## 读取展示描述，优先使用显示属性，再回退到序列化的 Description。
static func get_display_description(item: Variant, fallback: String = "") -> String:
	var display_description: Variant = _get_property(item, &"DisplayDescription")
	if display_description != null and not String(display_description).is_empty():
		return String(display_description)
	var description: Variant = _get_property(item, &"Description")
	return fallback if description == null or String(description).is_empty() else String(description)

## 读取展示图标，优先使用显示属性，再回退到序列化的 CardIcon。
static func get_display_icon(item: Variant, fallback: Texture2D = null) -> Texture2D:
	var display_icon: Variant = _get_property(item, &"DisplayIcon")
	if display_icon is Texture2D:
		return display_icon as Texture2D
	var card_icon: Variant = _get_property(item, &"CardIcon")
	return card_icon as Texture2D if card_icon is Texture2D else fallback

## 读取物品的实际最大堆叠数量；保留零值和负值，让调用方沿用旧校验语义。
static func get_max_stack_size(item: Variant, fallback: int = 99) -> int:
	var actual_value: Variant = _get_property(item, &"ActualMaxStackSize")
	if actual_value != null:
		return int(actual_value)
	var max_value: Variant = _get_property(item, &"MaxStackSize")
	return fallback if max_value == null else int(max_value)

## 读取物品标签并统一为 StringName 数组；未知或空字段返回空数组。
static func get_item_tags(item: Variant) -> Array[StringName]:
	var tags: Array[StringName] = []
	var raw_tags: Variant = _get_property(item, &"ItemTags")
	if not (raw_tags is Array):
		return tags
	for raw_tag in raw_tags:
		if raw_tag != null:
			tags.append(StringName(raw_tag))
	return tags

## 读取物品自身买入价；缺失字段使用零，保持未定价资源不可直接出售的语义。
static func get_buy_price(item: Variant, fallback: int = 0) -> int:
	var value: Variant = _get_property(item, &"BuyPrice")
	return fallback if value == null else int(value)

## 读取物品自身卖出价；缺失字段使用零，让商店层继续负责买价折半回退。
static func get_sell_price(item: Variant, fallback: int = 0) -> int:
	var value: Variant = _get_property(item, &"SellPrice")
	return fallback if value == null else int(value)

## 复用 ShopService 的卖价回退规则，但不把商店副作用放入 Resource 工具。
static func get_resolved_sell_price(item: Variant, fallback: int = 0) -> int:
	var sell_price: int = get_sell_price(item, fallback)
	if sell_price > 0:
		return sell_price
	var buy_price: int = get_buy_price(item, 0)
	return buy_price / 2 if buy_price > 0 else fallback

## 比较两个物品 Resource 的对象身份，保持 InventoryComponent 的引用相等语义。
static func same_item(left: Variant, right: Variant) -> bool:
	return left != null and right != null and left == right

## 读取对象属性；统一经过 Object.get，避免静态类型绑定到某一种语言实现。
static func _get_property(value: Variant, property_name: StringName) -> Variant:
	if not (value is Object):
		return null
	var object: Object = value as Object
	return object.get(String(property_name))

## 检查 Resource 的导出属性表，区分真正的 ItemData 与普通卡牌 Resource。
static func _has_property(resource: Resource, property_name: StringName) -> bool:
	for property_info in resource.get_property_list():
		if not (property_info is Dictionary):
			continue
		var name_value: Variant = property_info.get("name")
		if name_value != null and StringName(name_value) == property_name:
			return true
	return false
