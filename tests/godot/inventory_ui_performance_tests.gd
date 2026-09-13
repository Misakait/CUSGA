extends SceneTree

const MAIN_SCENE := "res://scenes/Main.tscn"
const SKILL_CARD_SCRIPT := "res://resources/item/card/SkillCardData.cs"
const BRANCH_ITEM := "res://resources/item/card/res_cards/branch.tres"

var _failures: Array[String] = []


func _init() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var main: Node = load(MAIN_SCENE).instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	await _test_inventory_views_are_reused_and_rebound(main)
	await _test_crafting_refreshes_after_parent_visibility_returns(main)

	main.queue_free()
	await process_frame
	_finish()


func _test_inventory_views_are_reused_and_rebound(main: Node) -> void:
	var inventory_ui := main.get_node("UI/HUDLayer/HUDRoot/CenterOverlay/InventoryUI")
	var inventory := main.get_node("Player/Components/InventoryComponent")
	var battle_deck := main.get_node("Player/Components/BattleDeckComponent")
	var slot_grid: GridContainer = inventory_ui.get_node("%SlotGrid")
	var deck_grid: GridContainer = inventory_ui.get_node("%DeckSlotGrid")

	inventory_ui.Open(inventory)
	await process_frame
	var inventory_view_ids := _child_instance_ids(slot_grid)
	var inventory_capacity := int(inventory.Capacity)
	var branch_item = load(BRANCH_ITEM)
	var remaining := int(inventory.AddItem(branch_item, 1))
	await process_frame

	_assert(remaining == 0, "测试物品应能加入玩家背包。")
	_assert(inventory.Capacity == inventory_capacity, "普通背包变化不应改变容量。")
	_assert(_child_instance_ids(slot_grid) == inventory_view_ids, "普通背包变化应复用全部 SlotUI 实例。")

	inventory.SortByCardName()
	await process_frame
	for index in range(slot_grid.get_child_count()):
		var slot_view = slot_grid.get_child(index)
		_assert(slot_view.SlotIndex == index, "排序后 SlotUI 应绑定正确的槽位索引。")
		_assert(slot_view.Inventory == inventory, "排序后 SlotUI 应继续绑定玩家背包。")
		_assert(slot_view.CurrentStack == inventory.GetStackAt(index), "排序后 SlotUI 应改绑到当前 ItemStack 引用。")

	var initial_deck_capacity := int(battle_deck.Capacity)
	var initial_deck_view_ids := _child_instance_ids(deck_grid)
	var attempts := 0
	while battle_deck.Capacity == initial_deck_capacity and attempts <= initial_deck_capacity:
		var skill_card = load(SKILL_CARD_SCRIPT).new()
		skill_card.MaxStackSize = 1
		skill_card.CardName = "ui-test-card-%d" % attempts
		_assert(battle_deck.AddItem(skill_card, 1) == 0, "测试技能卡应能加入出战卡组。")
		attempts += 1

	await process_frame
	_assert(battle_deck.Capacity > initial_deck_capacity, "测试应触发出战卡组扩容。")
	_assert(deck_grid.get_child_count() == battle_deck.Capacity, "扩容后卡组视图数量应匹配容量。")
	for index in range(initial_deck_view_ids.size()):
		_assert(deck_grid.get_child(index).get_instance_id() == initial_deck_view_ids[index], "卡组扩容不得替换已有 SlotUI。")


func _test_crafting_refreshes_after_parent_visibility_returns(main: Node) -> void:
	var hud_layer: CanvasLayer = main.get_node("UI/HUDLayer")
	var crafting_ui := main.get_node("UI/HUDLayer/HUDRoot/CenterOverlay/CraftingUI")
	var crafting := main.get_node("Player/Components/CraftingComponent")
	var inventory := main.get_node("Player/Components/InventoryComponent")
	var ingredient_list: VBoxContainer = crafting_ui.get_node("%IngredientList")
	var branch_item = load(BRANCH_ITEM)

	crafting_ui.Open(crafting)
	await process_frame
	var owned_before := int(inventory.ItemCnt(branch_item))
	var row_before := ingredient_list.get_child(0)
	var row_id_before := row_before.get_instance_id()
	var text_before := _ingredient_text(row_before)

	hud_layer.hide()
	await process_frame
	_assert(not crafting_ui.is_visible_in_tree(), "隐藏 HUDLayer 后 CraftingUI 应从场景树中不可见。")
	_assert(inventory.AddItem(branch_item, 1) == 0, "隐藏期间测试材料应能加入背包。")
	await process_frame
	_assert(ingredient_list.get_child(0).get_instance_id() == row_id_before, "隐藏期间库存变化不得重建材料行。")
	_assert(_ingredient_text(ingredient_list.get_child(0)) == text_before, "隐藏期间库存变化不得刷新材料文本。")

	hud_layer.show()
	await process_frame
	await process_frame
	var refreshed_text := _ingredient_text(ingredient_list.get_child(0))
	_assert(crafting_ui.is_visible_in_tree(), "恢复 HUDLayer 后 CraftingUI 应重新可见。")
	_assert(refreshed_text != text_before, "CraftingUI 恢复可见时应补做一次库存刷新。")
	_assert(refreshed_text.contains("拥有 %d" % (owned_before + 1)), "恢复刷新应显示当前材料拥有量。")


func _child_instance_ids(parent: Node) -> Array[int]:
	var ids: Array[int] = []
	for child in parent.get_children():
		ids.append(child.get_instance_id())
	return ids


func _ingredient_text(row: Node) -> String:
	for child in row.get_children():
		if child is Label:
			return child.text
	return ""


func _assert(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("All inventory UI performance Godot tests passed.")
		quit(0)
		return

	for failure in _failures:
		push_error(failure)
	quit(1)
