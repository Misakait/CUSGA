extends Node

## 合成组件的并行 GDScript 实现。
##
## 组件只负责配方书读取、库存绑定、服务调用和信号转发；材料扣除、产物空间
## 预检及失败原因仍由 CraftingService 统一处理，从而保持组件与 UI 的职责边界。

const CRAFTING_SERVICE_SCRIPT: GDScript = preload("res://core/crafting/crafting_service.gd")

## 与 C# CraftingFailureReason 保持相同整数顺序，供跨语言调用方使用。
enum CraftingFailureReason {
	None,
	InvalidRecipe,
	InvalidQuantity,
	MissingMaterials,
	NotEnoughSpace,
}

## 合成成功后发出；参数顺序保持 C# 信号协议。
signal CraftingCompleted(recipe, quantity: int, output_amount: int)
## 合成失败后发出；failure_reason 使用 CraftingFailureReason 整数值。
signal CraftingFailed(recipe, quantity: int, failure_reason: int)

## 配方书资源；保留 PascalCase 字段名以承接旧 C# 资源序列化值。
@export var RecipeBook: Resource

## 最近一次合成失败原因；成功时为 None。
var LastFailureReason: int = CraftingFailureReason.None
## 绑定的库存节点；在 _ready 中从同级组件容器解析。
var _inventory: Node = null
## 合成规则服务实例；服务不持有组件状态。
var _crafting_service: RefCounted = null


## 读取绑定库存，供 CraftingUI 和 GameplayPort 的稳定协议使用。
## @return 当前玩家库存节点；未完成 _ready 时返回 null。
var Inventory: Node:
	get:
		return _inventory


## 过滤配方书中的空条目并返回配方资源列表。
## @return 不包含 null 的配方数组，保留旧资源对象身份和顺序。
var Recipes: Array:
	get:
		var result: Array = []
		if RecipeBook == null:
			return result
		var raw_recipes: Variant = RecipeBook.get("Recipes")
		if not (raw_recipes is Array):
			return result
		for recipe: Variant in raw_recipes:
			if recipe != null:
				result.append(recipe)
		return result


## 节点进入场景树时绑定同级 InventoryComponent 并创建规则服务。
func _ready() -> void:
	_crafting_service = CRAFTING_SERVICE_SCRIPT.new()
	var parent_node := get_parent()
	if parent_node != null:
		_inventory = parent_node.get_node_or_null("InventoryComponent") as Node
	if _inventory == null:
		push_error("CraftingComponent 未找到同级 InventoryComponent。")


## 判断一次合成是否可执行。
## @param recipe 要检查的配方资源。
## @param quantity 合成次数，默认 1。
## @return 材料和产物空间均满足时返回 true。
func CanCraft(recipe: Variant, quantity: int = 1) -> bool:
	return _service().CanCraft(_inventory, recipe, quantity)


## 计算库存和配方共同允许的最大合成次数。
## @param recipe 要检查的配方资源。
## @return 可以完整执行的最大次数；输入无效时返回 0。
func MaxCraftableQuantity(recipe: Variant) -> int:
	return int(_service().MaxCraftableQuantity(_inventory, recipe))


## 合成一份配方。
## @param recipe 要执行的配方资源。
## @return 合成成功时返回 true。
func TryCraft(recipe: Variant, quantity: int = 1) -> bool:
	return TryCraftWithReason(recipe, quantity) == CraftingFailureReason.None


## 执行合成并返回与 C# out 参数等价的失败原因码。
## @param recipe 要执行的配方资源。
## @param quantity 合成次数。
## @return CraftingFailureReason 整数值；0 表示成功。
func TryCraftWithReason(recipe: Variant, quantity: int = 1) -> int:
	var reason: int = int(_service().TryCraftWithReason(_inventory, recipe, quantity))
	LastFailureReason = reason
	if reason == CraftingFailureReason.None:
		var output_amount: int = int(recipe.get("OutputAmount")) * quantity if recipe is Object else 0
		CraftingCompleted.emit(recipe, quantity, output_amount)
		print("成功合成了 %d 个 %s！" % [output_amount, _get_item_name(recipe)])
		return reason

	CraftingFailed.emit(recipe, quantity, reason)
	print(_get_failure_message(reason))
	return reason


## 保留 C# 组件的错误文本，便于旧日志和 UI 调试保持一致。
## @param failure_reason CraftingFailureReason 整数值。
## @return 面向玩家的失败提示文本。
func _get_failure_message(failure_reason: int) -> String:
	match failure_reason:
		CraftingFailureReason.MissingMaterials:
			return "材料不足，合成失败！"
		CraftingFailureReason.NotEnoughSpace:
			return "背包空间不足，合成失败！"
		CraftingFailureReason.InvalidQuantity:
			return "合成数量无效，合成失败！"
		_:
			return "配方无效，合成失败！"


## 从配方读取显示名称，兼容新旧 ItemData 的字段差异。
## @param recipe 当前配方资源。
## @return 输出物品显示名；字段缺失时返回空字符串。
func _get_item_name(recipe: Variant) -> String:
	if not (recipe is Object):
		return ""
	var output: Variant = recipe.get("OutputItem")
	if not (output is Object):
		return ""
	var display_name: Variant = output.get("DisplayName")
	if display_name != null and not String(display_name).is_empty():
		return String(display_name)
	var card_name: Variant = output.get("CardName")
	return "" if card_name == null else String(card_name)


## 延迟创建服务，兼容测试中直接调用公开方法而未进入场景树的实例。
## @return 可调用的 CraftingService 实例。
func _service() -> RefCounted:
	if _crafting_service == null:
		_crafting_service = CRAFTING_SERVICE_SCRIPT.new()
	return _crafting_service
