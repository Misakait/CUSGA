extends Node2D

## 新商店入口，只协调区域、既有交易桥接、全局权威及缓存生命周期。
const LIST: GDScript = preload("res://core/ui/shop/shop_list_controller.gd")
const BUY: GDScript = preload("res://core/ui/shop/shop_buy_controller.gd")
const SELL: GDScript = preload("res://core/ui/shop/shop_sell_controller.gd")
const SOURCE: GDScript = preload("res://core/ui/shop/shop_source_slot.gd")
const PRESENTER: GDScript = preload("res://core/ui/item_tooltip_presenter.gd")
const BUILD_STOCK: StringName = &"BuildStockList"
const BUY_PRICE: StringName = &"GetBuyPrice"
const SELL_PRICE: StringName = &"GetSellPrice"
const TRY_BUY: StringName = &"TryBuyWithReason"
const TRY_SELL: StringName = &"TrySellWithReason"
const SORT: StringName = &"SortByCardName"
const UPGRADE: StringName = &"TryUpgradeWarehouse"

var _warehouse: Node
var _wallet: Node
var _progression: Node
var _bridge: Node
var _warehouse_list: RefCounted = LIST.new()
var _goods_list: RefCounted = LIST.new()
var _buy: RefCounted = BUY.new()
var _sell: RefCounted = SELL.new()
var _catalog: Array[Resource] = []
var _active: bool = false
var _initialized: bool = false
var _trading: bool = false
var _session: int = 0
var _presenter: RefCounted
var _tooltip_slot: Button
var _tooltip_item: Resource

func _ready() -> void:
	_setup_view()
	init()

## 场景进入入口；返回无，允许早于 ready 和缓存重入，重复 init 不重置正在使用的界面。
func init() -> void:
	if not is_inside_tree():
		return
	if not is_node_ready():
		init.call_deferred()
		return
	if _active:
		refresh()
		return
	_setup_view()
	_warehouse = get_node_or_null(^"/root/GlobalWarehouse")
	_wallet = get_node_or_null(^"/root/PlayerWallet")
	_progression = get_node_or_null(^"/root/PlayerProgression")
	_bridge = get_node_or_null("ShopTradeBridge")
	if _warehouse == null or _wallet == null or _progression == null or _bridge == null:
		push_error("ShopNew：缺少仓库、钱包、升级组件或交易桥接。")
		return
	_active = true
	_session += 1
	_build_catalog()
	_subscribe(true)
	clear_selection()
	_sell.call("clear")
	refresh()

## 场景离开入口；返回无，清除短期选择并解除全部外部订阅。
func exit() -> void:
	_active = false
	_session += 1
	_subscribe(false)
	clear_selection()
	_sell.call("clear")

func _exit_tree() -> void:
	exit()

func _setup_view() -> void:
	if _initialized:
		return
	_initialized = true
	_warehouse_list.call("bind", get_node("ItemSection/ScrollContainer/SlotGrid"), self, &"warehouse")
	_goods_list.call("bind", get_node("Shop/ScrollContainer/SlotGrid"), self, &"goods")
	_buy.call("bind", get_node("Shop/BuyArea"))
	_sell.call("bind", get_node("Shop/SellArea"), self)
	var tooltip: Node = get_node_or_null("TooltipLayer/TooltipPanel")
	if tooltip != null:
		tooltip.remove_from_group("tooltip_panel")
	_presenter = PRESENTER.new(tooltip)
	_buy.connect("purchase_requested", _on_purchase_requested)
	_sell.connect("sale_requested", _on_sale_requested)
	(get_node("ItemSection/Clean/NinePatchRect") as Button).pressed.connect(sort_items)
	(get_node("ItemSection/Upgrade/NinePatchRect") as Button).pressed.connect(upgrade_warehouse)
	(get_node("Shop/TheButton/GoBack") as Button).pressed.connect(go_back)
	_ignore_decoration(self)

func _ignore_decoration(parent: Node) -> void:
	for child: Node in parent.get_children():
		if child is Label or child is RichTextLabel or child is NinePatchRect:
			(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ignore_decoration(child)

func _build_catalog() -> void:
	_catalog.clear()
	var items: Node = get_node_or_null(^"/root/ItemsControl")
	if items == null or not _bridge.has_method(BUILD_STOCK):
		return
	var raw: Variant = items.get("items")
	if not raw is Dictionary:
		return
	var all_items: Array[Resource] = []
	for value: Variant in (raw as Dictionary).values():
		if value is Resource:
			all_items.append(value as Resource)
	var stock: Variant = _bridge.call(BUILD_STOCK, all_items)
	if stock is Array:
		for value: Variant in stock:
			if value is Resource:
				_catalog.append(value as Resource)

## 从权威刷新内容与金额；返回无，交易中间信号延迟到整笔返回后处理。
func refresh() -> void:
	if not _active or _trading:
		return
	var entries: Array = []
	for index: int in int(_warehouse.get("Capacity")):
		entries.append(SOURCE.call("snapshot", _warehouse, index))
	_warehouse_list.call("refresh", entries)
	var goods: Array = []
	for item: Resource in _catalog:
		goods.append({"item": item, "price": int(_bridge.call(BUY_PRICE, item))})
	_goods_list.call("refresh", goods)
	# 详情框展示的是来源格当前物品，外部库存变化后不能继续显示已经消失的物品。
	if _tooltip_item != null and not is_instance_valid(_tooltip_slot):
		_hide_tooltip()
	elif is_instance_valid(_tooltip_slot) and _tooltip_slot.get("side") == &"warehouse":
		var selected_entry: Dictionary = SOURCE.call("snapshot", _warehouse, int(_tooltip_slot.get("slot_index")))
		if selected_entry.get("item") != _tooltip_item or int(selected_entry.get("amount", 0)) <= 0:
			_hide_tooltip()
	var pending: Dictionary = _sell.call("source")
	if not pending.is_empty() and not bool(SOURCE.call("matches", _warehouse, pending)):
		_sell.call("clear", "物品已变化，请重新拖入")
		_warehouse_list.call("select", -1)
	_refresh_money()

func _refresh_money() -> void:
	var gold: int = int(_wallet.get("Gold"))
	(get_node("Shop/CoinPanel/CoinCount") as Label).text = str(gold)
	var cost: int = int(_progression.call("GetWarehouseNextCost"))
	var maximum: bool = bool(_progression.call("IsWarehouseMaxLevel"))
	(get_node("ItemSection/Upgrade/Cost") as Label).text = "已满级" if maximum else "花费%d升级" % cost
	(get_node("ItemSection/Upgrade/NinePatchRect") as Button).disabled = maximum or cost <= 0 or gold < cost

## 清除格子单选与购买详情；返回无，拖动开始不会提交任何交易。
func clear_selection() -> void:
	_warehouse_list.call("select", -1)
	_goods_list.call("select", -1)
	_buy.call("clear")
	_hide_tooltip()

## 仅清除商品/仓库格子的选中状态，保留购买区当前详情；用于点击左侧仓库物品。
func _clear_slot_selection() -> void:
	_warehouse_list.call("select", -1)
	_goods_list.call("select", -1)

func _on_slot_clicked(slot: Button) -> void:
	if not _active or _trading:
		return
	var side: StringName = slot.get("side")
	var index: int = int(slot.get("slot_index"))
	if side == &"goods":
		clear_selection()
	else:
		_clear_slot_selection()
	if side == &"goods" and index >= 0 and index < _catalog.size():
		_goods_list.call("select", index)
		var item: Resource = _catalog[index]
		_buy.call("show_item", item, int(_bridge.call(BUY_PRICE, item)))
		_show_tooltip(item, slot)
	elif side == &"warehouse":
		_warehouse_list.call("select", index)
		var entry: Dictionary = SOURCE.call("snapshot", _warehouse, index)
		var warehouse_item: Resource = entry.get("item") as Resource
		if warehouse_item != null and int(entry.get("amount", 0)) > 0:
			_show_tooltip(warehouse_item, slot)
		else:
			_hide_tooltip()

func _show_tooltip(item: Resource, slot: Button) -> void:
	if _presenter == null or item == null:
		return
	_tooltip_slot = slot
	_tooltip_item = item
	_presenter.call("Show", item)
	var anchor: Vector2 = slot.get_global_transform_with_canvas() * Vector2(slot.size.x, 0.0)
	var tooltip: Node = get_node_or_null("TooltipLayer/TooltipPanel")
	if tooltip != null:
		tooltip.call("set_fixed_anchor", anchor)

func _hide_tooltip() -> void:
	_tooltip_slot = null
	_tooltip_item = null
	if _presenter != null:
		var tooltip: CanvasItem = get_node_or_null("TooltipLayer/TooltipPanel") as CanvasItem
		# 停止游戏时子节点可能先离树，此时直接隐藏，避免提示脚本在离树后创建 Tween。
		if tooltip != null and tooltip.is_inside_tree():
			_presenter.call("Hide")
		elif tooltip != null:
			tooltip.hide()

## 构造拖放载荷。参数 side 为 warehouse、index 为来源；返回带当前进入身份的快照，非法来源为空。
func create_drag_data(side: StringName, index: int) -> Dictionary:
	if not _active or _trading or side != &"warehouse":
		return {}
	var data: Dictionary = SOURCE.call("snapshot", _warehouse, index)
	if data.get("item") == null or int(data.get("amount", 0)) <= 0:
		return {}
	data.merge({"owner": get_instance_id(), "session": _session, "side": side})
	return data

## 校验出售区拖放。参数 data 为来源；返回本界面本次进入的有效可售物品是否仍在原槽。
func can_drop_item(data: Dictionary) -> bool:
	return _active and not _trading and bool(SOURCE.call("valid_payload", _warehouse, data, get_instance_id(), _session)) and get_sell_price(data.get("item") as Resource) > 0

## 更新待售图标。参数 data 为来源快照；返回接收成功与否，不执行交易。
func drop_item(data: Dictionary) -> bool:
	return bool(_sell.call("accept_drop", data))

## 读取桥接卖出单价。参数 item 为原物品；返回既有规则的价格。
func get_sell_price(item: Resource) -> int:
	return int(_bridge.call(SELL_PRICE, item)) if is_instance_valid(_bridge) and _bridge.has_method(SELL_PRICE) else 0

func _on_purchase_requested(item: Resource, quantity: int) -> void:
	if not _active or _trading:
		return
	if quantity <= 0:
		_sell.call("show_notice", "请选择数量", true)
		return
	if item == null or not _catalog.has(item):
		_sell.call("show_notice", "请先选择商品", true)
		return
	_trading = true
	var reason: int = int(_bridge.call(TRY_BUY, _wallet, _warehouse, item, quantity))
	_trading = false
	refresh()
	_show_result(reason, "购买", quantity, int(_bridge.call(BUY_PRICE, item)))

func _on_sale_requested(source: Dictionary, quantity: int) -> void:
	if not _active or _trading:
		return
	if quantity <= 0:
		_sell.call("show_notice", "请选择数量", true)
		return
	if not can_drop_item(source):
		_sell.call("clear", "请重新拖入可出售物品")
		return
	var item: Resource = source.get("item") as Resource
	var adapter: RefCounted = SOURCE.new()
	adapter.call("bind", _warehouse, source)
	_trading = true
	var reason: int = int(_bridge.call(TRY_SELL, _wallet, adapter, item, quantity))
	_trading = false
	# 交易中来源数量变化是预期结果，整笔完成后刷新快照，避免信号清掉正在提交的来源。
	if reason == 0:
		var updated: Dictionary = create_drag_data(&"warehouse", int(source["index"]))
		if updated.is_empty():
			_sell.call("clear")
		else:
			_sell.call("accept_drop", updated)
	refresh()
	_show_result(reason, "出售", quantity, get_sell_price(item))

func _show_result(reason: int, action: String, quantity: int, price: int) -> void:
	var message: String
	match reason:
		0: message = "%s%d件成功，共%d金币" % [action, quantity, price * quantity]
		1: message = "这个物品不能交易"
		2: message = "交易数量不合法"
		3: message = "金币不足"
		4: message = "仓库放不下更多了"
		5: message = "来源槽位的数量不够"
		_: message = "商店暂时不可用"
	_sell.call("show_notice", message, reason != 0)

## 按原规则整理仓库；返回无，整理前使所有旧拖放和待售状态失效。
func sort_items() -> void:
	if not _active or _trading:
		return
	_session += 1
	clear_selection()
	_sell.call("clear")
	_warehouse.call(SORT)
	refresh()

## 按原规则扣费扩容仓库；返回是否成功。
func upgrade_warehouse() -> bool:
	return _active and not _trading and bool(_progression.call(UPGRADE))

## 请求返回仓库；返回无，导航前清除临时状态。
func go_back() -> void:
	if not _active or _trading:
		return
	clear_selection()
	_sell.call("clear")
	var bus: Node = get_node_or_null(^"/root/GlobalEventBus")
	if bus != null and bus.has_signal(&"scene_requested"):
		bus.emit_signal(&"scene_requested", "warehouse")

func _subscribe(connecting: bool) -> void:
	for binding: Array in [[_warehouse, &"InventoryChanged", refresh], [_wallet, &"GoldChanged", _on_gold_changed], [_progression, &"UpgradeChanged", _on_upgrade_changed]]:
		var source: Node = binding[0] as Node
		var signal_name: StringName = binding[1]
		var callback: Callable = binding[2]
		if not is_instance_valid(source) or not source.has_signal(signal_name):
			continue
		if connecting and not source.is_connected(signal_name, callback):
			source.connect(signal_name, callback)
		elif not connecting and source.is_connected(signal_name, callback):
			source.disconnect(signal_name, callback)

func _on_gold_changed(_gold: int) -> void:
	if _active and not _trading:
		_refresh_money()

func _on_upgrade_changed(_kind: String, _level: int) -> void:
	refresh()
