extends SceneTree

const BATTLE_DECK_SCRIPT := "res://entities/components/BattleDeckComponent.cs"
const INVENTORY_SCRIPT := "res://entities/components/InventoryComponent.cs"
const ITEM_DATA_SCRIPT := "res://resources/item/ItemData.cs"
const SKILL_CARD_SCRIPT := "res://resources/item/card/SkillCardData.cs"

var _failures: Array[String] = []


func _init() -> void:
	call_deferred(&"_run")


func _run() -> void:
	await _test_battle_deck_expands_past_initial_capacity()
	await _test_regular_inventory_keeps_fixed_capacity()
	_finish()


func _test_battle_deck_expands_past_initial_capacity() -> void:
	var battle_deck = load(BATTLE_DECK_SCRIPT).new()
	root.add_child(battle_deck)
	await process_frame
	var skill_card = load(SKILL_CARD_SCRIPT).new()
	var initial_capacity: int = battle_deck.Capacity

	_assert(bool(battle_deck.CanAddItem(skill_card, initial_capacity + 1)), "出战卡组容量预检查应承认自动扩容后的批量加入。")

	var remaining := int(battle_deck.AddItem(skill_card, initial_capacity + 1))

	_assert(remaining == 0, "出战卡组超过初始格数后仍应全部放入技能卡。")
	_assert(battle_deck.GetSkillCards().size() == initial_capacity + 1, "出战卡组应保留所有已加入的技能卡。")
	_assert(battle_deck.Capacity == initial_capacity + 2, "出战卡组满后应自动扩容，并额外保留一个空槽。")
	_assert(battle_deck.GetStackAt(battle_deck.Capacity - 1).IsEmpty, "出战卡组末尾应保留一个可拖入的空槽。")

	battle_deck.queue_free()
	await process_frame


func _test_regular_inventory_keeps_fixed_capacity() -> void:
	var inventory = load(INVENTORY_SCRIPT).new()
	root.add_child(inventory)
	await process_frame
	var item = load(ITEM_DATA_SCRIPT).new()
	item.MaxStackSize = 1
	var initial_capacity: int = inventory.Capacity

	_assert(not bool(inventory.CanAddItem(item, initial_capacity + 1)), "普通背包容量预检查仍应拒绝超过固定容量的批量加入。")

	var remaining := int(inventory.AddItem(item, initial_capacity + 1))

	_assert(remaining == 1, "普通背包满后仍应返回放不下的剩余数量。")
	_assert(inventory.Capacity == initial_capacity, "普通背包不应套用出战卡组的自动扩容规则。")

	inventory.queue_free()
	await process_frame


func _assert(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("All battle deck capacity Godot tests passed.")
		quit(0)
		return

	for failure in _failures:
		push_error(failure)
	quit(1)
