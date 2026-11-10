@tool
extends McpTestSuite

## 使用固定候选卡，验证材料优先级与选择确认前后的库存变化。
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
	assert_eq(inventory.call("ItemCnt", card), 0, "确认前卡牌不能进入玩家背包")

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
	assert_true(balance.text.contains("木卡胚  0"), "面板应展示当前属性资源")
	assert_true(balance.text.contains("通用卡胚  0"), "面板应展示通用资源")

## 验证重复资源按卡槽选择，且只有确认时才交付所选数量。
func test_confirm_claims_selected_duplicate_cards_only() -> void:
	var inventory: Node = track(INVENTORY.new())
	var panel: Control = track(load("res://core/ui/inventory/imprint_panel.gd").new())
	panel.call("setup", inventory, track(Control.new()))
	var card: Resource = CARD.new()
	var cards: Array = panel.get("_drawn_cards")
	cards.append(card)
	cards.append(card)
	var indices: Array = panel.get("_selected_indices")
	indices.append(1)
	var slots: Array = panel.get("_slots")
	var markers: Array = panel.get("_selection_labels")
	for index in 2:
		slots.append(track(Button.new()))
		markers.append(track(Label.new()))
	assert_eq(inventory.call("ItemCnt", card), 0, "确认之前不应获得卡牌")
	panel.call("_confirm_selection")
	assert_eq(inventory.call("ItemCnt", card), 1, "重复卡只交付被选择的那一张")
	assert_eq(cards.size(), 0, "确认后本批结果应结束")

## 空选择也可以确认，结果不写入背包。
func test_confirm_empty_selection_discards_results() -> void:
	var inventory: Node = track(INVENTORY.new())
	var panel: Control = track(load("res://core/ui/inventory/imprint_panel.gd").new())
	panel.call("setup", inventory, track(Control.new()))
	var card: Resource = CARD.new()
	var cards: Array = panel.get("_drawn_cards")
	cards.append(card)
	panel.call("_confirm_selection")
	assert_eq(inventory.call("ItemCnt", card), 0, "空选择不能自动获得卡牌")
	assert_eq(cards.size(), 0, "空选择确认后应结束本批结果")

## 复刻生产 HUD 的居中容器层级，验证全屏面板不受容器重新排版。
func test_backpack_opens_fullscreen_panel_above_hud() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var hud: Control = track(Control.new())
	hud.size = Vector2(1280, 720)
	tree.root.add_child(hud)
	var center := CenterContainer.new()
	hud.add_child(center)
	# 编辑器测试中非 @tool 场景脚本会退化为占位实例，直接构造控制器以执行真实回调。
	var backpack: Control = load("res://core/ui/inventory/inventory_ui_controller.gd").new()
	center.add_child(backpack)
	var other_hud := Control.new()
	hud.add_child(other_hud)
	var inventory: Node = INVENTORY.new()
	hud.add_child(inventory)
	backpack.set("_player_inventory", inventory)
	backpack.call("_on_imprint_button_pressed")
	var panel: Control = hud.get_node_or_null("ImprintPanel") as Control
	assert_true(panel != null, "刻印面板必须挂在 HUD 而不是居中容器下")
	if panel == null:
		return
	assert_eq(panel.get_parent(), hud, "全屏面板必须使用 HUD 坐标")
	assert_eq(panel.anchor_right, 1.0, "面板应铺满 HUD 宽度")
	assert_eq(panel.anchor_bottom, 1.0, "面板应铺满 HUD 高度")
	assert_true(panel.get_index() > other_hud.get_index(), "刻印面板应绘制在已有 HUD 之上")
