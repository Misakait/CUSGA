extends Node2D

## 局外商店场景控制器。
##
## 职责边界：本脚本只负责「显示什么」与「把玩家意图转交给规则层」。
## 一切「能不能买 / 能不能卖 / 会扣多少钱」的判断都在 `core/shop/ShopService.cs` 里，
## 经由 `ShopTradeBridge` 这个 C# 节点跨语言调用。GDScript 侧不复制任何价格或容量规则，
## 否则规则一旦改动就会出现「界面显示可买、点击却失败」的分裂。
##
## 库存的唯一权威是 `GlobalWarehouse` autoload：商店界面里的仓库格子每次都从它读取。
## 仓库场景 `warehouse_control.gd` 在 `exit()` 时会把界面副本写回 `GlobalWarehouse`，
## 因此从商店返回仓库时能看到买卖后的最新库存。

## 每页格子数。4 列 × 4 行。
const PAGE_SIZE := 16

## 单个格子场景。
const SHOP_SLOT_SCENE := preload("res://scenes/Shop/shop_slot.tscn")

# ── ShopFailureReason 的具名镜像 ────────────────────────────────────────────
# 数值必须与 core/shop/ShopFailureReason.cs 完全一致。C# 侧有一条测试
# （ShopFailureReasonValuesAreStable）锁住这些数值，改任何一侧都要同步另一侧。
const FAILURE_NONE := 0
const FAILURE_INVALID_ITEM := 1
const FAILURE_INVALID_QUANTITY := 2
const FAILURE_NOT_ENOUGH_GOLD := 3
const FAILURE_NOT_ENOUGH_SPACE := 4
const FAILURE_MISSING_ITEM := 5
const FAILURE_NOT_CONFIGURED := 6

## 选中项所属的一侧。
const SIDE_SHOP := &"shop"
const SIDE_WAREHOUSE := &"warehouse"

# ── 场景节点引用 ───────────────────────────────────────────────────────────
# 刻意不用 @onready：SceneManager 会在「初始场景还没进树」时就调用 init()
# （见 core/autoloads/SceneManager.gd 的 _ready），那一刻 @onready 变量仍全是 null。
# 用 --scene 直接跑本场景时走的正是这条路径，会导致整屏引用失效。
# 子节点在 instantiate() 之后就已经存在，因此统一在 init() 里用 get_node_or_null 解析。
var _warehouse_grid: GridContainer = null
var _shop_grid: GridContainer = null
var _warehouse_page_label: Label = null
var _shop_page_label: Label = null
var _warehouse_prev: Button = null
var _warehouse_next: Button = null
var _shop_prev: Button = null
var _shop_next: Button = null
var _gold_label: Label = null
var _selected_label: Label = null
var _hint_label: Label = null
var _status_label: Label = null
var _buy_button: Button = null
var _sell_button: Button = null

# 这三个是跨语言动态节点，刻意不写类型标注：
# 声明成 Node 会让 GDScript 静态分析拒绝调用 Bridge 上的自定义方法（C# 方法对分析器不可见），
# 项目里 map_button.gd 访问 TimeSystem 时也采用同样的写法。
var _bridge = null
var _wallet = null
var _warehouse = null

## 商品目录：从 ItemsControl 过滤出可购买物品，并已按 CardId 排序。
var _shop_catalog: Array[ItemData] = []

## 两侧的格子视图，索引即页内序号。
var _warehouse_slots: Array[ShopSlot] = []
var _shop_slots: Array[ShopSlot] = []

## 当前选中项。空字典表示未选中。
## 形状：{"side": StringName, "index": int}，index 是 catalog / 仓库槽位的绝对序号。
var _selected: Dictionary = {}

var _warehouse_page: int = 1
var _shop_page: int = 1

## 格子视图是否已创建。SceneManager 会缓存场景实例并反复调用 init()，必须幂等。
var _slots_built: bool = false


## 进入商店时由 SceneManager 调用。
func init() -> void:
	_selected = {}
	_warehouse_page = 1
	_shop_page = 1

	_resolve_nodes()
	_resolve_dependencies()
	_build_slot_views()
	_connect_wallet()
	_build_shop_catalog()
	_set_status("", false)
	_refresh_all()


## 场景挂进树时自行初始化一次。
## SceneManager 在 add_child 之后还会调用一次 init()，这里主动调一次是为了让
## 「直接用 --scene 运行 Shop.tscn」也能看到完整界面（开发调试与截图都依赖这一点）。
## init() 本身幂等，多调用一次只是多刷新一遍，不会产生重复节点或重复信号连接。
func _ready() -> void:
	init()


## 解析全部场景节点引用。
## 每次 init() 都重新解析：初始化既可能发生在进树之前（SceneManager 对初始场景的调用），
## 也可能发生在进树之后（场景切换），统一解析时机可以同时覆盖两条路径。
func _resolve_nodes() -> void:
	_warehouse_grid = get_node_or_null("UILayer/Root/WarehouseGrid")
	_shop_grid = get_node_or_null("UILayer/Root/ShopGrid")
	_warehouse_page_label = get_node_or_null("UILayer/Root/WarehousePage")
	_shop_page_label = get_node_or_null("UILayer/Root/ShopPage")
	_warehouse_prev = get_node_or_null("UILayer/Root/WarehousePrev")
	_warehouse_next = get_node_or_null("UILayer/Root/WarehouseNext")
	_shop_prev = get_node_or_null("UILayer/Root/ShopPrev")
	_shop_next = get_node_or_null("UILayer/Root/ShopNext")
	_gold_label = get_node_or_null("UILayer/Root/GoldLabel")
	_selected_label = get_node_or_null("UILayer/Root/SelectedLabel")
	_hint_label = get_node_or_null("UILayer/Root/HintLabel")
	_status_label = get_node_or_null("UILayer/Root/StatusLabel")
	_buy_button = get_node_or_null("UILayer/Root/BuyButton")
	_sell_button = get_node_or_null("UILayer/Root/SellButton")

	# 场景结构被改坏时给出明确指向，而不是让后续操作在 null 上逐条报错。
	if _warehouse_grid == null or _shop_grid == null or _status_label == null:
		push_error("Shop: 场景节点结构与脚本预期不符，请检查 UILayer/Root 下的子节点名称。")


## 离开商店时由 SceneManager 调用。
func exit() -> void:
	_disconnect_wallet()
	_selected = {}


# ── 初始化 ─────────────────────────────────────────────────────────────────

## 解析跨语言依赖。
## 缺任何一个都只降级为「商店不可用」，不让场景崩溃——金币或仓库缺失是装配问题，
## 玩家看到的应该是一句提示，而不是一次引擎报错。
func _resolve_dependencies() -> void:
	_bridge = get_node_or_null("ShopTradeBridge")
	_wallet = get_node_or_null("/root/PlayerWallet")
	_warehouse = get_node_or_null("/root/GlobalWarehouse")

	if _bridge == null:
		push_error("Shop: 场景里缺少 ShopTradeBridge 节点，无法进行任何交易。")
	if _wallet == null:
		push_error("Shop: 未找到 PlayerWallet autoload，无法读取或扣除金币。")
	if _warehouse == null:
		push_error("Shop: 未找到 GlobalWarehouse autoload，无法读写仓库。")


## 创建两侧的格子视图。
## 只创建一次：格子数量是固定的分页大小，翻页时复用同一批格子重新绑定，
## 反复释放重建会让每次翻页都产生一批新节点。
func _build_slot_views() -> void:
	if _slots_built:
		return

	# 解析不到网格时保持「未构建」状态，让下一次 init() 有机会重试，
	# 而不是因为一次失败就永久失去格子系统。
	if _warehouse_grid == null or _shop_grid == null:
		return

	_slots_built = true
	_warehouse_slots = _create_slots(_warehouse_grid, SIDE_WAREHOUSE)
	_shop_slots = _create_slots(_shop_grid, SIDE_SHOP)


## 在指定网格下创建一整页格子。
## @param grid 承载格子的网格容器。
## @param side 这一侧的身份，会随点击事件一起回传。
## @return Array[ShopSlot] 创建出的格子列表，索引即页内序号。
func _create_slots(grid: GridContainer, side: StringName) -> Array[ShopSlot]:
	var slots: Array[ShopSlot] = []
	for i in PAGE_SIZE:
		var slot: ShopSlot = SHOP_SLOT_SCENE.instantiate()
		grid.add_child(slot)
		slot.slot_clicked.connect(_on_slot_clicked.bind(side))
		slots.append(slot)
	return slots


## 订阅金币变化。
## 先判断再连接：SceneManager 会反复调用 init()，重复连接会让一次余额变化触发多次刷新。
func _connect_wallet() -> void:
	if _wallet == null or not _wallet.has_signal("GoldChanged"):
		return
	if _wallet.is_connected("GoldChanged", _on_gold_changed):
		return
	_wallet.connect("GoldChanged", _on_gold_changed)


## 断开金币订阅。连接是本脚本建立的，因此也必须由本脚本解除。
func _disconnect_wallet() -> void:
	if _wallet == null or not _wallet.has_signal("GoldChanged"):
		return
	if _wallet.is_connected("GoldChanged", _on_gold_changed):
		_wallet.disconnect("GoldChanged", _on_gold_changed)


## 构建商品目录。
## @remarks
## 上架清单与排序规则完全由 C# 侧的 ShopCatalog 决定，GDScript 只负责把「全部物品」递过去。
## 这样「哪些算商品」只有一处实现，不会出现界面与会话两侧规则漂移。
func _build_shop_catalog() -> void:
	_shop_catalog.clear()

	if _bridge == null:
		return

	var all_items: Array[ItemData] = []
	for value in ItemsControl.items.values():
		var item: ItemData = value
		if item != null:
			all_items.append(item)

	# 必须先声明成 Array[ItemData] 再 assign：把 C# 返回的数组直接赋给类型化变量会跨越
	# Godot 的元素类型校验边界，用 assign 转换是唯一稳妥的写法。
	var stock: Array[ItemData] = []
	stock.assign(_bridge.BuildStockList(all_items))
	_shop_catalog = stock


# ── 刷新 ───────────────────────────────────────────────────────────────────

## 全量刷新两侧与动作区。
## 交易后直接整体刷新，而不是做细粒度局部更新：每页只有 16 个格子，重绘成本极低，
## 换来的是「不可能忘记刷新某一侧」这一确定性。
func _refresh_all() -> void:
	_fill_warehouse_page()
	_fill_shop_page()
	_refresh_gold()

	# 交易可能把选中的仓库堆叠卖空，此时选中项已不存在，必须清掉；
	# 否则动作区会停在一个看不见的物品上，按钮状态也会失去依据。
	if not _selected.is_empty() and _selected_item() == null:
		_selected = {}

	_refresh_selection_visuals()
	_refresh_action_area()


## 用仓库当前内容填充左侧分页。
func _fill_warehouse_page() -> void:
	var total := _warehouse_slot_total()
	var page_count := _page_count(total)
	_warehouse_page = clampi(_warehouse_page, 1, page_count)

	_warehouse_page_label.text = "%d / %d" % [_warehouse_page, page_count]
	_warehouse_prev.disabled = _warehouse_page <= 1
	_warehouse_next.disabled = _warehouse_page >= page_count

	var first_index := (_warehouse_page - 1) * PAGE_SIZE
	for i in PAGE_SIZE:
		var slot := _warehouse_slots[i]
		var stack = _get_warehouse_stack(first_index + i)
		if stack == null or stack.IsEmpty:
			slot.clear_slot()
			continue

		var item: ItemData = stack.Item
		slot.bind(item, stack.Amount, _bridge.GetSellPrice(item), &"sell")


## 用商品目录填充右侧分页。
func _fill_shop_page() -> void:
	var page_count := _page_count(_shop_catalog.size())
	_shop_page = clampi(_shop_page, 1, page_count)

	_shop_page_label.text = "%d / %d" % [_shop_page, page_count]
	_shop_prev.disabled = _shop_page <= 1
	_shop_next.disabled = _shop_page >= page_count

	var first_index := (_shop_page - 1) * PAGE_SIZE
	for i in PAGE_SIZE:
		var slot := _shop_slots[i]
		var index := first_index + i
		if index >= _shop_catalog.size():
			slot.clear_slot()
			continue

		var item: ItemData = _shop_catalog[index]
		# 商品是无限库存，数量传 0 且右侧不显示数量。
		slot.bind(item, 0, _bridge.GetBuyPrice(item), &"buy")


## 刷新顶部金币显示。
func _refresh_gold() -> void:
	if _wallet == null:
		_gold_label.text = "金币：—"
		return

	_gold_label.text = "金币：%d" % _bridge.GetGold(_wallet)


## 同步所有格子的选中外观。
## 选中态只有本脚本这一处写入点，两侧因此天然互斥。
func _refresh_selection_visuals() -> void:
	var selected_side: StringName = _selected.get("side", &"")
	var selected_index: int = _selected.get("index", -1)
	var warehouse_first := (_warehouse_page - 1) * PAGE_SIZE
	var shop_first := (_shop_page - 1) * PAGE_SIZE

	for i in _shop_slots.size():
		_shop_slots[i].set_selected(selected_side == SIDE_SHOP and selected_index == shop_first + i)

	for i in _warehouse_slots.size():
		_warehouse_slots[i].set_selected(
			selected_side == SIDE_WAREHOUSE and selected_index == warehouse_first + i
		)


## 刷新中间动作区的文案与按钮可用性。
func _refresh_action_area() -> void:
	var item := _selected_item()
	if item == null:
		_selected_label.text = "先点选左侧的仓库物品或右侧的商品"
		_hint_label.text = ""
		_buy_button.disabled = true
		_sell_button.disabled = true
		return

	var display_name := String(item.get("CardName"))
	_selected_label.text = display_name if not display_name.is_empty() else "（未命名物品）"

	if _selected["side"] == SIDE_SHOP:
		_hint_label.text = (
			"买价 %d · 直接卖出可得 %d"
			% [_bridge.GetBuyPrice(item), _bridge.GetSellPrice(item)]
		)
		# 余额不足或仓库放不下时直接禁用按钮，让玩家在点击之前就知道买不了，
		# 而不是点完再看一句失败提示。
		_buy_button.disabled = not _bridge.CanBuy(_wallet, _warehouse, item, 1)
		_sell_button.disabled = true
		return

	# 桥接是动态节点，返回值对静态分析器而言是 Variant，因此显式标注类型而不是用 := 推断。
	var owned: int = _bridge.GetItemCount(_warehouse, item)
	_hint_label.text = "持有 %d · 单价 %d" % [owned, _bridge.GetSellPrice(item)]
	_sell_button.disabled = not _bridge.CanSell(_warehouse, item, 1)
	_buy_button.disabled = true


# ── 交互 ───────────────────────────────────────────────────────────────────

## 格子被点击。
## @param slot 被点击的格子。
## @param side 该格子所属的一侧。
func _on_slot_clicked(slot: ShopSlot, side: StringName) -> void:
	var page_slots: Array[ShopSlot] = _shop_slots if side == SIDE_SHOP else _warehouse_slots
	var page: int = _shop_page if side == SIDE_SHOP else _warehouse_page

	var position_in_page := page_slots.find(slot)
	if position_in_page < 0:
		return

	_selected = {"side": side, "index": (page - 1) * PAGE_SIZE + position_in_page}
	_set_status("", false)
	_refresh_selection_visuals()
	_refresh_action_area()


## 点击「购买」。
func _on_buy_button_pressed() -> void:
	var item := _selected_item()
	if item == null:
		return

	_handle_trade_result(_bridge.TryBuyWithReason(_wallet, _warehouse, item, 1), true)


## 点击「出售」。
func _on_sell_button_pressed() -> void:
	var item := _selected_item()
	if item == null:
		return

	_handle_trade_result(_bridge.TrySellWithReason(_wallet, _warehouse, item, 1), false)


## 统一处理交易结果。
## @param reason ShopFailureReason 的数值；0 表示成功。
## @param is_buy true 表示本次是购买。
func _handle_trade_result(reason: int, is_buy: bool) -> void:
	if reason != FAILURE_NONE:
		_set_status(_failure_text(reason), true)
		# 失败往往意味着余额或空间发生了变化，按钮可用性需要重新计算。
		_refresh_action_area()
		return

	_set_status("购买成功" if is_buy else "出售成功", false)
	_refresh_all()


## 把失败原因码翻译成玩家能看懂的中文。
## @param reason ShopFailureReason 的数值。
## @return String 提示文案。
func _failure_text(reason: int) -> String:
	match reason:
		FAILURE_INVALID_ITEM:
			return "这个物品不能交易"
		FAILURE_INVALID_QUANTITY:
			return "交易数量不合法"
		FAILURE_NOT_ENOUGH_GOLD:
			return "金币不足"
		FAILURE_NOT_ENOUGH_SPACE:
			return "仓库放不下更多了"
		FAILURE_MISSING_ITEM:
			return "仓库里的数量不够"
		FAILURE_NOT_CONFIGURED:
			return "商店暂时不可用"
		_:
			return "交易失败（原因码 %d）" % reason


## 更新状态提示。
## @param text 提示文案；空字符串表示清空。
## @param is_error true 用警示色显示。
func _set_status(text: String, is_error: bool) -> void:
	_status_label.text = text
	_status_label.modulate = Color(1.0, 0.45, 0.45) if is_error else Color(0.6, 1.0, 0.7)


func _on_warehouse_prev_pressed() -> void:
	_warehouse_page -= 1
	_fill_warehouse_page()
	_refresh_selection_visuals()


func _on_warehouse_next_pressed() -> void:
	_warehouse_page += 1
	_fill_warehouse_page()
	_refresh_selection_visuals()


func _on_shop_prev_pressed() -> void:
	_shop_page -= 1
	_fill_shop_page()
	_refresh_selection_visuals()


func _on_shop_next_pressed() -> void:
	_shop_page += 1
	_fill_shop_page()
	_refresh_selection_visuals()


## 点击「离开商店」。
func _on_exit_button_pressed() -> void:
	GlobalEventBus.scene_requested.emit("warehouse")


## 金币变化的回调。购买与出售都会让余额变化，兜住这条信号可以保证顶部显示永远是最新的。
## @param _new_gold 变化后的余额，这里不直接使用，统一经桥接读取以避免两处口径不一致。
func _on_gold_changed(_new_gold: int) -> void:
	_refresh_gold()


# ── 数据访问 ───────────────────────────────────────────────────────────────

## 读取仓库中指定槽位的堆叠。
## @param index 槽位绝对序号。
## @return Variant 该槽位的 ItemStack；越界或仓库缺失时返回 null。
func _get_warehouse_stack(index: int):
	if _warehouse == null:
		return null
	if index < 0 or index >= _warehouse_slot_total():
		return null
	return _warehouse.GetStackAt(index)


## 读取仓库的总槽位数。
## @return int 槽位数；仓库缺失时返回 0。
func _warehouse_slot_total() -> int:
	if _warehouse == null:
		return 0

	# 经 Object.get 跨越 C# 自动加载边界读取属性，避免把动态节点误当作静态 GDScript 属性。
	var capacity: Variant = _warehouse.get("Capacity")
	if capacity == null:
		return 0
	return int(capacity)


## 取当前选中的物品。
## @return ItemData 选中的物品；未选中、或选中的格子已经空了时返回 null。
func _selected_item() -> ItemData:
	if _selected.is_empty():
		return null

	var index: int = _selected["index"]
	if index < 0:
		return null

	if _selected["side"] == SIDE_SHOP:
		if index >= _shop_catalog.size():
			return null
		return _shop_catalog[index]

	var stack = _get_warehouse_stack(index)
	if stack == null or stack.IsEmpty:
		return null
	return stack.Item


## 计算总页数。
## @param total 条目总数。
## @return int 页数，至少为 1（空列表也占一页，避免显示「1 / 0」）。
func _page_count(total: int) -> int:
	return maxi(1, int(ceil(float(total) / float(PAGE_SIZE))))
