extends Node2D

## 新局外仓库入口，协调双区、钱包、升级和导航；内容权威仍由原有全局组件拥有。
const SECTION: GDScript = preload("res://core/ui/warehouse/warehouse_section_controller.gd")
const TRANSFER: GDScript = preload("res://core/ui/warehouse/warehouse_transfer.gd")
const DRAG: GDScript = preload("res://core/ui/warehouse/warehouse_drag_controller.gd")
const PRESENTER: GDScript = preload("res://core/ui/item_tooltip_presenter.gd")

## 拖动期间右键连续放置的初始速率（个/秒）。
@export var drag_place_initial_rate: float = 4.0
## 连续放置速率的加速度（个/秒²）。
@export var drag_place_acceleration: float = 8.0
## 连续放置速率的最高上限（个/秒）。
@export var drag_place_max_rate: float = 30.0

var _warehouse: Node
var _carry: Node
var _wallet: Node
var _progression: Node
var _warehouse_section: RefCounted = SECTION.new()
var _carry_section: RefCounted = SECTION.new()
var _transfer: RefCounted = TRANSFER.new()
var _drag: RefCounted = DRAG.new()
var _presenter: RefCounted
var _scroll_warehouse: ScrollContainer
var _scroll_carry: ScrollContainer
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
	# 拖动会话与两区共用同一套权威；悬停目标由本类的 _resolve_hovered_slot 解析。
	_drag.call("bind", self, _transfer, Callable(self, "_resolve_hovered_slot"))
	_drag.call("set_rates", drag_place_initial_rate, drag_place_acceleration, drag_place_max_rate)
	# 拖动期间才需要每帧推进连续放置，其余时间关闭逐帧处理。
	set_process(false)
	_subscribe(true)
	clear_selection()
	_absorb_items_brought_back()
	refresh()

## SceneManager 的离开入口；返回无，解除所有权威订阅、结束拖动会话并清除提示。
func exit() -> void:
	_active = false
	_subscribe(false)
	clear_selection()
	# 会话未成交时物品本就在来源，直接丢弃会话即可，不需要归还。
	_drag.call("cancel")

func _exit_tree() -> void:
	exit()

func _setup_view() -> void:
	if _initialized:
		return
	_initialized = true
	_warehouse_section.call("bind", get_node("ItemSection/ScrollContainer/SlotGrid"), self, &"warehouse")
	_carry_section.call("bind", get_node("PackbackSection/ScrollContainer/SlotGrid"), self, &"carry")
	# 滚动容器用于裁掉滚出可见区的格子：命中判定必须同时满足容器矩形与格子矩形。
	_scroll_warehouse = get_node("ItemSection/ScrollContainer") as ScrollContainer
	_scroll_carry = get_node("PackbackSection/ScrollContainer") as ScrollContainer
	# 拖动期间的右键必须在输入阶段收到（早于 GUI 阶段），不能依赖被拖控件之外的格子回调。
	set_process_input(true)
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
	for index: int in capacity:
		var entry: Dictionary = _transfer.call("snapshot", &"carry", index)
		carry_entries.append(entry)
	_warehouse_section.call("refresh", warehouse_entries)
	_carry_section.call("refresh", carry_entries)
	_refresh_capacity_label()
	_refresh_money()
	if _selected_index >= 0:
		var selected: Dictionary = _transfer.call("snapshot", _selected_side, _selected_index)
		if selected.get("item") != _selected_item or int(selected.get("amount", 0)) <= 0:
			clear_selection()

## 读取权威并刷新行囊占用文案；返回无，供 refresh 与 refresh_slot 复用。
func _refresh_capacity_label() -> void:
	var capacity: int = int(_progression.call("GetCarrySlotCount"))
	var occupied: int = 0
	for index: int in capacity:
		var entry: Dictionary = _transfer.call("snapshot", &"carry", index)
		if entry.get("item") != null and int(entry.get("amount", 0)) > 0:
			occupied += 1
	(get_node("PackbackSection/CapacityLabel") as Label).text = "（%d/%d）" % [occupied, capacity]

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

## 构造拖动载荷。参数 side/index 为来源位置、selected 为按下前的持续选中态；
## 返回带本界面身份与令牌的会话载荷，不能拖动（空槽或拆半结果为 0）时返回空字典。
func create_drag_data(side: StringName, index: int, selected: bool) -> Dictionary:
	if not _active:
		return {}
	var data: Dictionary = _drag.call("begin", side, index, selected)
	return data

## 构建拖动预览（含剩余数量）。参数 item 为来源物品；返回供 set_drag_preview 使用的控件。
func create_drag_preview(item: Resource) -> Control:
	return _drag.call("create_preview", item) as Control

## 预检拖放。参数 data 为载荷、side/index 为目标；返回是否允许当前拖放。
func can_drop_item(data: Dictionary, side: StringName, index: int) -> bool:
	return _active and not _moving and bool(_drag.call("can_drop", data, side, index))

## 提交拖放。参数 data 为载荷、side/index 为目标；返回是否发生移动。
func drop_item(data: Dictionary, side: StringName, index: int) -> bool:
	if not can_drop_item(data, side, index):
		return false
	# _moving 由 commit_placement / commit_group_drop 拥有，这里不再重复设置。
	var moved: bool = bool(_drag.call("drop", data, side, index))
	clear_selection()
	refresh()
	return moved

## 提交一次按数量搬运。参数 data 为来源快照、side/index 为目标、amount 为希望搬运的数量；
## 返回实际移动数量，0 表示目标未接收。
func commit_placement(data: Dictionary, side: StringName, index: int, amount: int) -> int:
	_moving = true
	var moved: int = int(_transfer.call("move_amount", data, side, index, amount))
	_moving = false
	return moved

## 提交整组投放，保留原有「不同物品交换」语义。参数 data 为来源快照、side/index 为目标；
## 返回是否发生移动。
func commit_group_drop(data: Dictionary, side: StringName, index: int) -> bool:
	_moving = true
	var moved: bool = bool(_transfer.call("move", data, side, index))
	_moving = false
	return moved

## 只重绑一个格子的内容。参数 side/index 为格子位置；返回无。
## 不重建格子节点，避免打断正在进行的原生拖动；行囊占用文案同步刷新。
func refresh_slot(side: StringName, index: int) -> void:
	if not _active or index < 0:
		return
	var slots: Array = _section_slots(side)
	if index >= slots.size():
		return
	var slot: Variant = slots[index]
	if not is_instance_valid(slot):
		return
	var entry: Dictionary = _transfer.call("snapshot", side, index)
	slot.call("bind_content", entry.get("item"), int(entry.get("amount", 0)))
	_refresh_capacity_label()

## 切换拖动会话的逐帧处理。参数 active 为会话是否进行中；返回无。
func set_drag_session_active(active: bool) -> void:
	set_process(active)

func _process(delta: float) -> void:
	_drag.call("tick", delta)

## 原生拖动被 Godot 自己结束时的收尾入口（由格子脚本的 NOTIFICATION_DRAG_END 转发）。返回无。
func on_drag_finished() -> void:
	# 正常投放时 _drop_data（提交）与拖动结束发生在同一帧的输入处理内，同步取消会抢在 _drop_data
	# 之前结束会话，让合法投放失效，因此这里必须延后到本帧输入处理结束再收尾。
	_drag.call_deferred("finish_after_release")

func _notification(what: int) -> void:
	# 这里用 NOTIFICATION_APPLICATION_FOCUS_OUT，而不是 NOTIFICATION_WM_WINDOW_FOCUS_OUT：
	# 后者是 Window / MainLoop 的通知，普通 Node（本控制器是 Node2D）收不到，写了也不会触发。
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		# 会话不预扣物品，未放出的数量仍在来源权威里，所以取消必然无损；反过来不结束会话的话，
		# 玩家切回来后会用旧来源继续放置，产生非预期的数量变化。
		_drag.call("cancel")

func _input(event: InputEvent) -> void:
	if not _active or not bool(_drag.call("is_active")):
		return
	if not (event is InputEventMouseButton):
		return
	var button: InputEventMouseButton = event
	if button.button_index == MOUSE_BUTTON_RIGHT:
		if button.pressed:
			_drag.call("press_secondary")
		else:
			_drag.call("release_secondary")
		# 拖动期间的右键只服务数量分配，不再泄漏给其它界面或场景逻辑。
		get_viewport().set_input_as_handled()
	elif button.button_index == MOUSE_BUTTON_LEFT and not button.pressed:
		# 原生投放发生在 GUI 阶段；必须等本帧输入处理结束后再收尾，否则会抢在 _drop_data 前取消会话。
		_drag.call_deferred("finish_after_release")

## 解析鼠标当前悬停在哪个格子上。返回 [side, index]；没有命中时返回空数组。
func _resolve_hovered_slot() -> Array:
	# 原生拖动期间，被拖控件之外的格子收不到 gui_input，所以这里用矩形自行判定目标：
	# 先要求落在该区 ScrollContainer 的可见矩形内（滚动裁切），再命中具体格子。
	for side: StringName in [&"warehouse", &"carry"]:
		var scroll: ScrollContainer = _scroll_warehouse if side == &"warehouse" else _scroll_carry
		if not is_instance_valid(scroll):
			continue
		if not scroll.get_global_rect().has_point(scroll.get_global_mouse_position()):
			continue
		for slot: Variant in _section_slots(side):
			if not is_instance_valid(slot):
				continue
			if (slot as Control).get_global_rect().has_point((slot as Control).get_global_mouse_position()):
				return [side, int(slot.get("slot_index"))]
	return []

## 读取一个区域当前的格子数组。参数 side 为区域；返回格子数组，区域未知时返回空数组。
func _section_slots(side: StringName) -> Array:
	var section: RefCounted = _warehouse_section if side == &"warehouse" else _carry_section
	var slots: Variant = section.get("slots")
	return (slots as Array) if slots is Array else []

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
