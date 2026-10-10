@tool
extends McpTestSuite

## 新商店的隔离数据契约；非工具 UI 的真实输入和缓存生命周期由运行场景验证。
const SOURCE: GDScript = preload("res://core/ui/shop/shop_source_slot.gd")
const BRIDGE: GDScript = preload("res://core/shop/shop_trade_bridge.gd")
const INVENTORY: GDScript = preload("res://entities/components/inventory_component.gd")
const WALLET: GDScript = preload("res://core/autoloads/player_wallet.gd")
const ITEM: GDScript = preload("res://resources/item/item_data.gd")
const STACK: GDScript = preload("res://resources/item/item_stack.gd")

## 返回发现名称；返回 shop_new_contract。
func suite_name() -> String:
	return "shop_new_contract"

## 验证出售只移除来源装备，不误扣末尾同类装备；返回无。
func test_sale_removes_exact_source_equipment() -> void:
	var fixture: Dictionary = _fixture()
	var inventory: Node = fixture["inventory"]
	var wallet: Node = fixture["wallet"]
	var bridge: Node = fixture["bridge"]
	var item: Resource = _item(1)
	_set_stack(inventory, 0, item, 1, {"power": 13})
	_set_stack(inventory, 3, item, 1, {"power": 77})
	var adapter: RefCounted = _adapter(inventory, 0)
	assert_eq(int(bridge.call("TrySellWithReason", wallet, adapter, item, 1)), 0)
	assert_eq(int(wallet.get("Gold")), 24)
	assert_true(bool(inventory.call("GetStackAt", 0).get("IsEmpty")))
	var remaining: Variant = inventory.call("GetStackAt", 3)
	assert_eq(remaining.get("Item"), item)
	assert_eq(remaining.get("Amount"), 1)
	assert_eq(remaining.get("RolledAttributes"), {"power": 77})

## 验证批量出售单价与数量、属性、原槽对象身份保持正确；返回无。
func test_partial_sale_preserves_attributes_and_slot_identity() -> void:
	var fixture: Dictionary = _fixture()
	var inventory: Node = fixture["inventory"]
	var wallet: Node = fixture["wallet"]
	var bridge: Node = fixture["bridge"]
	var item: Resource = _item(99)
	_set_stack(inventory, 0, item, 5, {"power": 13})
	var original: Variant = inventory.call("GetStackAt", 0)
	assert_eq(int(bridge.call("TrySellWithReason", wallet, _adapter(inventory, 0), item, 2)), 0)
	assert_eq(int(wallet.get("Gold")), 48)
	assert_eq(inventory.call("GetStackAt", 0), original)
	assert_eq(original.get("Amount"), 3)
	assert_eq(original.get("RolledAttributes"), {"power": 13})

## 验证零数与超过来源数量整笔失败，不从其它堆叠补扣；返回无。
func test_zero_and_insufficient_source_are_atomic() -> void:
	var fixture: Dictionary = _fixture()
	var inventory: Node = fixture["inventory"]
	var wallet: Node = fixture["wallet"]
	var bridge: Node = fixture["bridge"]
	var item: Resource = _item(99)
	_set_stack(inventory, 0, item, 2)
	_set_stack(inventory, 3, item, 9)
	var adapter: RefCounted = _adapter(inventory, 0)
	assert_eq(int(bridge.call("TrySellWithReason", wallet, adapter, item, 0)), 2)
	assert_eq(int(bridge.call("TrySellWithReason", wallet, adapter, item, 3)), 5)
	assert_eq(int(wallet.get("Gold")), 0)
	assert_eq(inventory.call("GetStackAt", 0).get("Amount"), 2)
	assert_eq(inventory.call("GetStackAt", 3).get("Amount"), 9)

## 验证数量、属性、资源或排序造成的来源变化都拒绝；返回无。
func test_stale_snapshot_rejects_each_identity_change() -> void:
	var fixture: Dictionary = _fixture()
	var inventory: Node = fixture["inventory"]
	var item: Resource = _item(99)
	_set_stack(inventory, 0, item, 5, {"power": 13})
	var snapshot: Dictionary = SOURCE.call("snapshot", inventory, 0)
	assert_true(bool(SOURCE.call("matches", inventory, snapshot)))
	_set_stack(inventory, 0, item, 6, {"power": 13})
	assert_false(bool(SOURCE.call("matches", inventory, snapshot)))
	_set_stack(inventory, 0, item, 5, {"power": 14})
	assert_false(bool(SOURCE.call("matches", inventory, snapshot)))
	_set_stack(inventory, 0, _item(99), 5, {"power": 13})
	assert_false(bool(SOURCE.call("matches", inventory, snapshot)))
	_set_stack(inventory, 0, item, 5, {"power": 13})
	var another: Resource = _item(99)
	another.set("CardName", "AAA")
	_set_stack(inventory, 1, another, 1)
	inventory.call("SortByCardName")
	assert_false(bool(SOURCE.call("matches", inventory, snapshot)))

## 验证过期快照在服务预检阶段失败且无金币和库存变更；返回无。
func test_stale_adapter_does_not_credit_wallet() -> void:
	var fixture: Dictionary = _fixture()
	var inventory: Node = fixture["inventory"]
	var item: Resource = _item(99)
	_set_stack(inventory, 0, item, 5)
	var adapter: RefCounted = _adapter(inventory, 0)
	_set_stack(inventory, 0, item, 6)
	assert_eq(int((fixture["bridge"] as Node).call("TrySellWithReason", fixture["wallet"], adapter, item, 1)), 5)
	assert_eq((fixture["wallet"] as Node).get("Gold"), 0)
	assert_eq(inventory.call("GetStackAt", 0).get("Amount"), 6)

## 验证拖动字典形状、界面身份与进入次数，不接受其它界面或旧会话；返回无。
func test_payload_rejects_foreign_stale_and_malformed_data() -> void:
	var fixture: Dictionary = _fixture()
	var inventory: Node = fixture["inventory"]
	_set_stack(inventory, 0, _item(99), 5)
	var data: Dictionary = SOURCE.call("snapshot", inventory, 0)
	data.merge({"owner": 123, "session": 7, "side": &"warehouse"})
	assert_true(bool(SOURCE.call("valid_payload", inventory, data, 123, 7)))
	assert_false(bool(SOURCE.call("valid_payload", inventory, data, 124, 7)))
	assert_false(bool(SOURCE.call("valid_payload", inventory, data, 123, 8)))
	for field: String in ["index", "stack_id", "item", "amount", "rolled", "owner", "session", "side"]:
		var malformed: Dictionary = data.duplicate(true)
		malformed[field] = null
		assert_false(bool(SOURCE.call("valid_payload", inventory, malformed, 123, 7)))
	assert_false(bool(SOURCE.call("matches", inventory, {})))
	assert_eq(SOURCE.call("snapshot", inventory, -1), {})
	assert_eq(SOURCE.call("snapshot", inventory, 4), {})

## 验证多件购买继续使用原桥接规则，零数、资金不足、容量不足无副作用；返回无。
func test_quantity_purchase_uses_existing_bridge() -> void:
	var fixture: Dictionary = _fixture()
	var inventory: Node = fixture["inventory"]
	var wallet: Node = fixture["wallet"]
	var bridge: Node = fixture["bridge"]
	var item: Resource = _item(99)
	wallet.set("Gold", 300)
	assert_eq(int(bridge.call("TryBuyWithReason", wallet, inventory, item, 0)), 2)
	assert_eq(wallet.get("Gold"), 300)
	assert_eq(int(bridge.call("TryBuyWithReason", wallet, inventory, item, 2)), 0)
	assert_eq(wallet.get("Gold"), 180)
	assert_eq(inventory.call("ItemCnt", item), 2)
	assert_eq(int(bridge.call("TryBuyWithReason", wallet, inventory, item, 4)), 3)
	assert_eq(wallet.get("Gold"), 180)
	assert_eq(inventory.call("ItemCnt", item), 2)
	for index: int in 4:
		_set_stack(inventory, index, item, 99)
	assert_eq(int(bridge.call("TryBuyWithReason", wallet, inventory, item, 1)), 4)
	assert_eq(wallet.get("Gold"), 180)
	assert_eq(inventory.call("ItemCnt", item), 396)

## 验证新场景接线和明确的交易入口，生产节点输入仍必须用真实运行验证；返回无。
func test_scene_wiring_and_explicit_input_boundaries() -> void:
	var scene: String = FileAccess.get_file_as_string("res://scenes/Shop/ShopNew.tscn")
	assert_true(scene.contains("res://core/ui/shop/shop_new_controller.gd"))
	assert_true(scene.contains("res://core/ui/shop/shop_sell_icon.gd"))
	assert_true(scene.contains('parent="Shop/ScrollContainer"'))
	assert_true(scene.contains('name="ShopTradeBridge"'))
	var buy: String = FileAccess.get_file_as_string("res://core/ui/shop/shop_buy_controller.gd")
	var sell: String = FileAccess.get_file_as_string("res://core/ui/shop/shop_sell_controller.gd")
	assert_true(buy.contains("_button.pressed.connect(request_purchase)"))
	assert_true(buy.contains("_quantity.apply()"))
	assert_true(sell.contains("_quantity.apply()"))
	assert_false(buy.contains("value_changed.connect"))
	assert_false(sell.contains("value_changed.connect"))
	var icon: String = FileAccess.get_file_as_string("res://core/ui/shop/shop_sell_icon.gd")
	assert_true(icon.contains("NOTIFICATION_DRAG_BEGIN"))
	assert_true(icon.contains("NOTIFICATION_DRAG_END"))
	assert_true(icon.contains("_click_armed and not get_viewport().gui_is_dragging()"))

func _fixture() -> Dictionary:
	var inventory: Node = track(INVENTORY.new()) as Node
	inventory.set("Capacity", 4)
	var wallet: Node = track(WALLET.new()) as Node
	wallet.set("Gold", 0)
	var bridge: Node = track(BRIDGE.new()) as Node
	return {"inventory": inventory, "wallet": wallet, "bridge": bridge}

func _item(maximum: int) -> Resource:
	var item: Resource = ITEM.new()
	item.set("CardName", "测试物品")
	item.set("MaxStackSize", maximum)
	item.set("BuyPrice", 60)
	item.set("SellPrice", 24)
	return item

func _set_stack(inventory: Node, index: int, item: Resource, amount: int, rolled: Dictionary = {}) -> void:
	var stack: RefCounted = STACK.new()
	stack.call("SetItem", item, amount)
	stack.set("RolledAttributes", rolled.duplicate(true))
	inventory.call("TrySetStackAt", index, stack)

func _adapter(inventory: Node, index: int) -> RefCounted:
	var adapter: RefCounted = SOURCE.new()
	adapter.call("bind", inventory, SOURCE.call("snapshot", inventory, index))
	return adapter
