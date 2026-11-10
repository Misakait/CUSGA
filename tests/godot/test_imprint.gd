@tool
extends McpTestSuite

## 使用固定候选卡，验证材料优先级、失败不扣费和实际入包。
const INVENTORY: GDScript = preload("res://entities/components/inventory_component.gd")
const SERVICE: GDScript = preload("res://core/imprint/imprint_service.gd")
const CARD: GDScript = preload("res://resources/item/card/skill_card_data.gd")

class FixedPool extends "res://core/imprint/imprint_service.gd":
	var card: Resource
	func _pool_for_element(_element: int) -> Array[Resource]:
		var cards: Array[Resource] = []
		if card != null:
			cards.append(card)
		return cards

func suite_name() -> String:
	return "imprint"

func test_payment_and_delivery() -> void:
	var inventory: Node = track(INVENTORY.new())
	var specific: Resource = load("res://items/imprint/wood_embryo.tres")
	var universal: Resource = load("res://items/imprint/universal_embryo.tres")
	var card: Resource = CARD.new()
	card.set("StarLevel", 3)
	inventory.call("AddItem", specific, 3)
	inventory.call("AddItem", universal, 8)
	var service := FixedPool.new()
	service.card = card
	var result: Dictionary = service.draw(inventory, 1, specific, universal, 10)
	assert_eq(result.cards.size(), 10, "十连必须交付十张卡")
	assert_eq(inventory.call("ItemCnt", specific), 0, "优先用完属性卡胚")
	assert_eq(inventory.call("ItemCnt", universal), 1, "其余消耗通用卡胚")
	assert_eq(inventory.call("ItemCnt", card), 10, "卡牌写入玩家背包")

func test_empty_pool_does_not_charge() -> void:
	var inventory: Node = track(INVENTORY.new())
	var specific: Resource = load("res://items/imprint/wood_embryo.tres")
	var universal: Resource = load("res://items/imprint/universal_embryo.tres")
	inventory.call("AddItem", specific, 1)
	var result: Dictionary = FixedPool.new().draw(inventory, 1, specific, universal, 1)
	assert_eq(result.cards.size(), 0, "空卡池不能抽取")
	assert_eq(inventory.call("ItemCnt", specific), 1, "空卡池不能扣材料")

func test_real_pools_exclude_filler_and_match_elements() -> void:
	var service: RefCounted = SERVICE.new()
	for element in [1, 4, 3, 5, 2]:
		var pool: Array = service.call("_pool_for_element", element)
		assert_true(not pool.is_empty(), "每个属性的正式卡池均应有卡")
		for card in pool:
			assert_eq(int(card.get("Element")), element, "卡牌属性必须匹配卡池")
			assert_true(int(card.get("StarLevel")) >= 3, "填充卡不能进入刻印池")

func test_panel_builds_and_reports_empty_balance() -> void:
	var inventory: Node = track(INVENTORY.new())
	var panel: Control = track(load("res://core/ui/inventory/imprint_panel.gd").new())
	var backpack: Control = track(Control.new())
	panel.call("setup", inventory, backpack)
	var balance: Label = panel.get("_balance")
	assert_true(balance.text.contains("木卡胚：0"), "面板应展示当前属性资源")
	assert_true(balance.text.contains("通用卡胚：0"), "面板应展示通用资源")
