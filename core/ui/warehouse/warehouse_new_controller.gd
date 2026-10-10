extends Node2D

## 新局外仓库入口，协调双区、钱包、升级和导航；内容权威仍由原有全局组件拥有。
const SECTION: GDScript = preload("res://core/ui/warehouse/warehouse_section_controller.gd")
const TRANSFER: GDScript = preload("res://core/ui/warehouse/warehouse_transfer.gd")
const PRESENTER: GDScript = preload("res://core/ui/item_tooltip_presenter.gd")

var _warehouse: Node
var _carry: Node
var _wallet: Node
var _progression: Node
var _warehouse_section: RefCounted = SECTION.new()
var _carry_section: RefCounted = SECTION.new()
var _transfer: RefCounted = TRANSFER.new()
var _presenter: RefCounted
var _selected_side: StringName = &""
var _selected_index: int = -1
var _selected_item: Resource
var _initialized: bool = false
var _moving: bool = false
var _active: bool = false

func _ready() -> void:
	_setup_view()
	init()

## SceneManager 的进入入口，允许早于 _ready 调用；返回无。
func init() -> void:
	if not is_node_ready():
		init.call_deferred()
		return
	if not is_inside_tree():
		return
	_warehouse = get_node_or_null(^"/root/GlobalWarehouse")
	_carry = get_node_or_null(^"/root/ItemsControl")
	_wallet = get_node_or_null(^"/root/PlayerWallet")
	_progression = get_node_or_null(^"/root/PlayerProgression")
	if _warehouse == null or _carry == null or _wallet == null or _progression == null:
		push_error("WarehouseNew：缺少仓库、行囊、钱包或升级组件。")
		return
	_active = true
	_subscribe(true)
	clear_selection()
	_absorb_items_brought_back()
	refresh()

## SceneManager 的离开入口；返回无，解除所有权威订阅并清除提示。
func exit() -> void:
	_active = false
	_subscribe(false)
	clear_selection()

func _exit_tree() -> void:
	exit()

func _setup_view() -> void:
	if _initialized:
		return
	_initialized = true
	_warehouse_section.call("bind", get_node("ItemSection/ScrollContainer/SlotGrid"), self, &"warehouse")
	_carry_section.call("bind", get_node("PackbackSection/ScrollContainer/SlotGrid"), self, &"carry")
	var tooltip: Node = get_node("TooltipLayer/TooltipPanel")
	tooltip.remove_from_group("tooltip_panel")
	_presenter = PRESENTER.new(tooltip)
	(get_node("ItemSection/Clean/NinePatchRect") as Button).pressed.connect(sort_items)
	(get_node("ItemSection/Upgrade/NinePatchRect") as Button).pressed.connect(upgrade_warehouse)
	(get_node("PackbackSection/Upgrade/NinePatchRect") as Button).pressed.connect(upgrade_carry)
	(get_node("GoToShop/TheButton/GoToShopButton") as Button).pressed.connect(go_to_shop)
	(get_node("TurnBackButton") as Button).pressed.connect(go_to_main_menu)
	# 原美术标签和背景仅负责显示，避免按钮表面的标签拦截点击。
	_ignore_decoration(self)

func _ignore_decoration(parent: Node) -> void:
	for child: Node in parent.get_children():
		if child is Label or child is RichTextLabel or child is NinePatchRect:
			(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ignore_decoration(child)

## 读取权威并刷新两区与文案；返回无，容量不变时复用原格子。
func refresh() -> void:
	if not _active or _moving:
		return
	var capacity: int = int(_progression.call("GetCarrySlotCount"))
	_transfer.call("bind", _warehouse, _carry, capacity)
	var warehouse_entries: Array = []
	var carry_entries: Array = []
	for index: int in int(_warehouse.get("Capacity")):
		warehouse_entries.append(_transfer.call("snapshot", &"warehouse", index))
	var occupied: int = 0
	for index: int in capacity:
		var entry: Dictionary = _transfer.call("snapshot", &"carry", index)
		carry_entries.append(entry)
		if entry.get("item") != null and int(entry.get("amount", 0)) > 0:
			occupied += 1
	_warehouse_section.call("refresh", warehouse_entries)
	_carry_section.call("refresh", carry_entries)
	(get_node("PackbackSection/CapacityLabel") as Label).text = "（%d/%d）" % [occupied, capacity]
	_refresh_money()
	if _selected_index >= 0:
		var selected: Dictionary = _transfer.call("snapshot", _selected_side, _selected_index)
		if selected.get("item") != _selected_item or int(selected.get("amount", 0)) <= 0:
			clear_selection()

func _refresh_money() -> void:
	var gold: int = int(_wallet.get("Gold"))
	(get_node("GoToShop/CoinPanel/CoinCount") as Label).text = str(gold)
	_refresh_upgrade("ItemSection", "GetWarehouseNextCost", "IsWarehouseMaxLevel", gold)
	_refresh_upgrade("PackbackSection", "GetCarryNextCost", "IsCarryMaxLevel", gold)

func _refresh_upgrade(section: String, cost_method: StringName, max_method: StringName, gold: int) -> void:
	var cost: int = int(_progression.call(cost_method))
	var maximum: bool = bool(_progression.call(max_method))
	(get_node(section + "/Upgrade/Cost") as Label).text = "已满级" if maximum else "花费%d升级" % cost
	(get_node(section + "/Upgrade/NinePatchRect") as Button).disabled = maximum or cost <= 0 or gold < cost

## 清除双区单选和固定描述面板；返回无。
func clear_selection() -> void:
	_selected_side = &""
	_selected_index = -1
	_selected_item = null
	_warehouse_section.call("select", -1)
	_carry_section.call("select", -1)
	if _presenter != null:
		var tooltip: CanvasItem = get_node_or_null("TooltipLayer/TooltipPanel") as CanvasItem
		# 直接停止场景时子节点先离树，此时不能让提示脚本创建隐藏动画。
		if tooltip != null and tooltip.is_inside_tree():
			_presenter.call("Hide")
		elif tooltip != null:
			tooltip.hide()

func _on_slot_clicked(slot: Button) -> void:
	var side: StringName = slot.get("side")
	var index: int = int(slot.get("slot_index"))
	var cancel: bool = _selected_side == side and _selected_index == index
	clear_selection()
	if cancel:
		return
	var entry: Dictionary = _transfer.call("snapshot", side, index)
	var item: Resource = entry.get("item") as Resource
	if item == null or int(entry.get("amount", 0)) <= 0:
		return
	_selected_side = side
	_selected_index = index
	_selected_item = item
	var section: RefCounted = _warehouse_section if side == &"warehouse" else _carry_section
	section.call("select", index)
	_presenter.call("Show", item)
	var anchor: Vector2 = slot.get_global_transform_with_canvas() * Vector2(slot.size.x, 0)
	get_node("TooltipLayer/TooltipPanel").call("set_fixed_anchor", anchor)

## 构造拖动快照。参数 side/index 为来源位置；返回带本界面身份的物品快照。
func create_drag_data(side: StringName, index: int) -> Dictionary:
	if not _active:
		return {}
	var data: Dictionary = _transfer.call("snapshot", side, index)
	if data.get("item") == null or int(data.get("amount", 0)) <= 0:
		return {}
	data.merge({"owner": get_instance_id(), "side": side, "index": index})
	return data

## 预检拖放。参数 data 为快照、side/index 为目标；返回是否允许当前拖放。
func can_drop_item(data: Dictionary, side: StringName, index: int) -> bool:
	return _active and not _moving and data.get("owner") == get_instance_id() and bool(_transfer.call("can_move", data, side, index))

## 提交拖放。参数 data 为快照、side/index 为目标；返回成功与否。
func drop_item(data: Dictionary, side: StringName, index: int) -> bool:
	if not can_drop_item(data, side, index):
		return false
	_moving = true
	var moved: bool = bool(_transfer.call("move", data, side, index))
	_moving = false
	clear_selection()
	refresh()
	return moved

## 按原库存名称规则整理仓库；返回无。
func sort_items() -> void:
	clear_selection()
	if _active:
		_warehouse.call("SortByCardName")

## 尝试扣费升级仓库；返回是否成功，费用与容量规则由 PlayerProgression 执行。
func upgrade_warehouse() -> bool:
	return _active and bool(_progression.call("TryUpgradeWarehouse"))

## 尝试扣费升级行囊；返回是否成功，费用与容量规则由 PlayerProgression 执行。
func upgrade_carry() -> bool:
	return _active and bool(_progression.call("TryUpgradeCarrySlots"))

## 请求去商店；返回无。
func go_to_shop() -> void:
	_request_scene("shop")

## 请求返回主菜单；返回无。
func go_to_main_menu() -> void:
	_request_scene("main_menu")

func _request_scene(scene_id: String) -> void:
	clear_selection()
	var bus: Node = get_node_or_null(^"/root/GlobalEventBus")
	if bus != null and bus.has_signal("scene_requested"):
		bus.emit_signal("scene_requested", scene_id)

func _subscribe(connecting: bool) -> void:
	for binding: Array in [[_warehouse, &"InventoryChanged", refresh], [_carry, &"carry_items_changed", refresh], [_wallet, &"GoldChanged", _on_gold_changed], [_progression, &"UpgradeChanged", _on_upgrade_changed]]:
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
	_refresh_money()

func _on_upgrade_changed(_kind: String, _value: int) -> void:
	refresh()

func _absorb_items_brought_back() -> void:
	var items: Array = _carry.get("player_to_warehouse")
	var counts: Array = _carry.get("player_to_warehouse_cnt")
	for index: int in mini(items.size(), counts.size()):
		var item: Resource = items[index] as Resource
		var count: int = int(counts[index])
		if item != null and count > 0:
			var leftover: int = int(_warehouse.call("AddItem", item, count))
			if leftover > 0:
				push_warning("仓库放不下 %s，溢出 %d 个" % [str(item.get("CardName")), leftover])
	items.clear()
	counts.clear()
