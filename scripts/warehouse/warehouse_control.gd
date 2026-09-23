extends Node2D

## 局外仓库场景控制器。
##
## 交互模型：**点选 + 放入/取出按钮**，不使用拖拽。与商店保持一致，
## 也让「仓库 → 带入栏」这种跨列表移动有一个明确的提交点。
##
## 数据权威：仓库内容直接读写 `/root/GlobalWarehouse`，不再维护界面副本。
## 旧实现让界面持有一份副本、在 exit() 时写回，一旦某条路径忘了写回就会丢改动；
## 直接操作权威库存从根本上消除了这类问题。
##
## 带入栏数量与仓库容量都由 `PlayerProgression` 决定，并且可以用金币升级。

## 仓库每页的格子数。6 列 × 4 行。
const PAGE_SIZE := 24

## 带入栏的栏位上限。升级只能在这个上限内增加可用数量。
##
## 【镜像常量】取值必须与 `ItemsControl.CARRY_SLOT_CAPACITY` 相等：格子视图必须按硬上限
## 一次铺满（否则升级扩栏时要重建节点），而权威也按同一数量铺数组。
## 两者由契约测试断言同值，禁止只改一处。
const CARRY_MAX_POSITIONS := 10

## 通用物品格子场景。与商店共用同一个场景，保证两处观感一致。
const ITEM_SLOT_SCENE := preload("res://scenes/ui/item_slot.tscn")

## 选中项所属的一侧。
const SIDE_WAREHOUSE := &"warehouse"
const SIDE_CARRY := &"carry"

## 尚未解锁的带入栏位的染色。压暗到明显低于可用格子的程度，让「买到的栏位」一眼可见。
const LOCKED_SLOT_TINT := Color(0.5, 0.5, 0.56, 1.0)

# ── 场景节点引用 ───────────────────────────────────────────────────────────
# 刻意不用 @onready：SceneManager 会对初始场景在它尚未就绪时就调用 init()，
# 那一刻 @onready 变量仍是 null。子节点在 instantiate() 之后就存在，
# 因此统一在 init() 里用 get_node_or_null 解析（详见 state-management 规范）。
var _warehouse_grid: GridContainer = null
var _carry_grid: GridContainer = null
var _warehouse_page_label: Label = null
var _warehouse_prev: Button = null
var _warehouse_next: Button = null
var _info_label: Label = null
var _gold_label: Label = null
var _selected_label: Label = null
var _hint_label: Label = null
var _status_label: Label = null
var _put_in_button: Button = null
var _take_out_button: Button = null
var _upgrade_warehouse_button: Button = null
var _upgrade_carry_button: Button = null

# 跨语言动态节点，刻意不写类型标注：声明成 Node 会让静态分析拒绝调用
# PlayerProgression / GlobalWarehouse 上的自定义 C# 方法。
var _warehouse = null
var _wallet = null
var _progression = null

## 带入栏权威来源（`ItemsControl` Autoload）。刻意不写类型标注，理由同上。
## 界面不再自己长期持有带入栏内容，一切读写都经它的 Get/Set/ClearCarryEntry。
var _carry_authority = null

## 两侧的格子视图。
var _warehouse_slots: Array[ItemSlot] = []
var _carry_slots: Array[ItemSlot] = []

## 带入栏内容。索引即栏位序号，元素形如 {"item": Resource, "count": int}。
## Resource 同时承接 GDScript 普通物品和保留的 C# 派生物品。
##
## 语义说明：这里是**权威的视图**，不是权威本身。每次 `_refresh_all()` 都会由
## `_sync_carry_view()` 从 `ItemsControl` 重建；写入也必须先落权威再刷新视图。
## 之所以不再让界面长期持有内容：仓库场景实例会被 SceneManager 缓存复用，
## 内容留在实例上时，开局「带入即消耗」在 Main 侧无法清空它，同一批物品会被重复带入。
var _carry_items: Array = []

## 当前选中项：{"side": StringName, "index": int}。空字典表示未选中。
var _selected: Dictionary = {}

var _warehouse_page: int = 1

## 格子视图是否已创建。SceneManager 会缓存场景实例并反复调用 init()，必须幂等。
## 注意：升级容量**不需要**重建格子——每页固定 PAGE_SIZE 个格子，容量只影响总页数。
var _slots_built: bool = false


# ── 生命周期 ───────────────────────────────────────────────────────────────

## 进入仓库时由 SceneManager 调用。
## @remarks
## 判据必须是 is_node_ready() 而不是 is_inside_tree()：SceneManager 会对初始场景在它就绪之前
## 就调用 init()，实测那一刻场景其实**已经进树**（is_inside_tree() 为 true），但 _ready 还没传播，
## 子树里子节点的引用尚未建立，直接同步执行必然访问到 null。
func init():
	if not is_node_ready():
		_apply_init.call_deferred()
		return

	_apply_init()


## 场景挂进树时自行初始化一次，让直接运行本场景调试时也能看到完整界面。
## init() 幂等，多调用一次只是多刷新一遍。
func _ready() -> void:
	init()


## 执行真正的初始化。只有子树就绪后才会被调用。
func _apply_init() -> void:
	_selected = {}
	_warehouse_page = 1

	_resolve_nodes()
	_resolve_dependencies()
	_build_slot_views()
	_absorb_items_brought_back()
	_set_status("", false)
	_refresh_all()


## 离开仓库时由 SceneManager 调用。
## @remarks
## 只把带入栏的内容导出给 `ItemsControl`，仓库库存不需要任何回写——
## 本次操作全程直接作用于 GlobalWarehouse。
##
## 【修订说明】带入栏的权威已上移到 `ItemsControl`（见 `_carry_items` 的声明注释），
## 因此上面描述的「导出」动作被取消：界面的每次写入都已经直接落在权威上，
## 退出时再导出一份只会产生第二份必须同步维护的状态。仓库库存依旧不需要任何回写。
func exit() -> void:
	_selected = {}


# ── 初始化 ─────────────────────────────────────────────────────────────────

## 解析场景节点引用。
func _resolve_nodes() -> void:
	_warehouse_grid = get_node_or_null("UILayer/Root/WarehouseGrid")
	_carry_grid = get_node_or_null("UILayer/Root/CarryGrid")
	_warehouse_page_label = get_node_or_null("UILayer/Root/WarehousePage")
	_warehouse_prev = get_node_or_null("UILayer/Root/WarehousePrev")
	_warehouse_next = get_node_or_null("UILayer/Root/WarehouseNext")
	_info_label = get_node_or_null("UILayer/Root/InfoLabel")
	_gold_label = get_node_or_null("UILayer/Root/GoldLabel")
	_selected_label = get_node_or_null("UILayer/Root/SelectedLabel")
	_hint_label = get_node_or_null("UILayer/Root/HintLabel")
	_status_label = get_node_or_null("UILayer/Root/StatusLabel")
	_put_in_button = get_node_or_null("UILayer/Root/PutInButton")
	_take_out_button = get_node_or_null("UILayer/Root/TakeOutButton")
	_upgrade_warehouse_button = get_node_or_null("UILayer/Root/UpgradeWarehouseButton")
	_upgrade_carry_button = get_node_or_null("UILayer/Root/UpgradeCarryButton")

	if _warehouse_grid == null or _carry_grid == null or _status_label == null:
		push_error("Warehouse: 场景节点结构与脚本预期不符，请检查 UILayer/Root 下的子节点名称。")


## 解析跨语言依赖。缺任何一个都只降级为对应功能不可用，不让场景崩溃。
func _resolve_dependencies() -> void:
	_warehouse = get_node_or_null("/root/GlobalWarehouse")
	_wallet = get_node_or_null("/root/PlayerWallet")
	_progression = get_node_or_null("/root/PlayerProgression")
	_carry_authority = get_node_or_null("/root/ItemsControl")

	if _warehouse == null:
		push_error("Warehouse: 未找到 GlobalWarehouse autoload，仓库内容无法读写。")
	if _wallet == null:
		push_error("Warehouse: 未找到 PlayerWallet autoload，金币无法显示。")
	if _progression == null:
		push_error("Warehouse: 未找到 PlayerProgression autoload，容量升级不可用。")
	if _carry_authority == null:
		push_error("Warehouse: 未找到 ItemsControl autoload，带入栏内容无法读写。")


## 创建两侧的格子视图。只创建一次，之后靠重新绑定复用。
func _build_slot_views() -> void:
	if _slots_built:
		return

	if _warehouse_grid == null or _carry_grid == null:
		return

	_slots_built = true
	_warehouse_slots = _create_slots(_warehouse_grid, SIDE_WAREHOUSE, PAGE_SIZE)
	_carry_slots = _create_slots(_carry_grid, SIDE_CARRY, CARRY_MAX_POSITIONS)

	# 带入栏的内容与栏位一一对应，先铺满空位，之后按索引覆盖。
	# 【修订说明】内容的铺法改由 `_sync_carry_view()` 从权威重建：格子视图只建一次，
	# 而带入栏内容可能已被开局初始化取走，所以内容不能只在建格子时铺一次。
	_sync_carry_view()


## 在指定网格下创建格子视图。
## @param grid 承载格子的网格容器。
## @param side 这一侧的身份，会随点击事件一起回传。
## @param count 要创建的格子数量。
## @return Array[ItemSlot] 创建出的格子列表，索引即页内序号。
func _create_slots(grid: GridContainer, side: StringName, count: int) -> Array[ItemSlot]:
	var slots: Array[ItemSlot] = []
	for i in count:
		var slot: ItemSlot = ITEM_SLOT_SCENE.instantiate()
		grid.add_child(slot)
		slot.slot_clicked.connect(_on_slot_clicked.bind(side))
		slots.append(slot)

	return slots


## 把局内带回来的物品并入仓库。
## @remarks
## 这是 `ItemsControl.player_to_warehouse` 的唯一消费点，消费后立即清空，
## 避免下次进入仓库时重复发放。
func _absorb_items_brought_back() -> void:
	if _warehouse == null:
		return

	for i in ItemsControl.player_to_warehouse.size():
		var item: Resource = ItemsControl.player_to_warehouse[i]
		var count: int = ItemsControl.player_to_warehouse_cnt[i]
		if item == null or count <= 0:
			continue

		var leftover := int(_warehouse.AddItem(item, count))
		if leftover > 0:
			push_warning("仓库放不下 %s，溢出 %d 个" % [str(item.get("CardName")), leftover])

	ItemsControl.player_to_warehouse.clear()
	ItemsControl.player_to_warehouse_cnt.clear()


# ── 刷新 ───────────────────────────────────────────────────────────────────

## 全量刷新。每页只有 24 个格子，重绘成本极低，换来的是「不可能忘记刷新某一处」。
func _refresh_all() -> void:
	# 先同步权威再画：带入栏内容可能已被开局初始化在场景外取走（带入即消耗），
	# 视图若不重建就会继续显示已经不在权威里的物品。
	_sync_carry_view()
	_refresh_header()
	_fill_warehouse_page()
	_fill_carry_slots()

	# 物品可能已被放入带入栏或整理换位，选中项失效时必须清掉，
	# 否则动作区会停在一个看不见的物品上。
	if not _selected.is_empty() and _selected_item() == null:
		_selected = {}

	_refresh_selection_visuals()
	_refresh_action_area()


## 刷新标题区的容量与金币显示。
func _refresh_header() -> void:
	_info_label.text = (
		"仓库 %d/%d　带入 %d/%d"
		% [_used_slot_count(), _warehouse_capacity(), _active_carry_count(), CARRY_MAX_POSITIONS]
	)
	_gold_label.text = "金币：%d" % _current_gold()


## 用仓库当前内容填充仓库分页。
func _fill_warehouse_page() -> void:
	var total := _warehouse_capacity()
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

		# 价格传 0 让格子隐藏价格行：仓库是管理界面，价格由商店负责表达。
		slot.bind(stack.Item, int(stack.Amount), 0, &"sell")


## 用带入栏内容填充带入格位。
## @remarks
## 超出当前可用栏位数的格位一律禁用**并变暗**：只禁用的空框和可用空框长得完全一样，
## 玩家会分不清自己实际拥有几个栏位、也就看不出升级买到了什么。
func _fill_carry_slots() -> void:
	var active := _active_carry_count()
	for i in CARRY_MAX_POSITIONS:
		var slot := _carry_slots[i]
		if i >= active:
			slot.clear_slot()
			slot.modulate = LOCKED_SLOT_TINT
			continue

		slot.modulate = Color.WHITE

		var entry: Dictionary = _carry_items[i]
		var item: Resource = entry["item"] as Resource
		if item == null or int(entry["count"]) <= 0:
			# 可用但为空的栏位：保留一个可点的空框，选中它时动作区只会提供「放入」。
			slot.clear_slot()
			slot.disabled = false
			continue

		slot.bind(item, int(entry["count"]), 0, &"sell")


## 同步所有格子的选中外观。选中态只有本脚本这一处写入点，两侧因此天然互斥。
func _refresh_selection_visuals() -> void:
	var selected_side: StringName = _selected.get("side", &"")
	var selected_index: int = _selected.get("index", -1)
	var warehouse_first := (_warehouse_page - 1) * PAGE_SIZE

	for i in _warehouse_slots.size():
		_warehouse_slots[i].set_selected(
			selected_side == SIDE_WAREHOUSE and selected_index == warehouse_first + i
		)

	for i in _carry_slots.size():
		_carry_slots[i].set_selected(selected_side == SIDE_CARRY and selected_index == i)


## 刷新动作区的文案与按钮可用性。
func _refresh_action_area() -> void:
	_refresh_upgrade_buttons()

	var item := _selected_item()
	if _selected.is_empty():
		_selected_label.text = "先点选左侧仓库物品或右侧带入栏"
		_hint_label.text = ""
		_put_in_button.disabled = true
		_take_out_button.disabled = true
		return

	if item == null:
		# 选中的是空栏位：只能往里放，没有东西可取。
		_selected_label.text = "空栏位"
		_hint_label.text = "从左侧选一样东西放进来"
		_put_in_button.disabled = true
		_take_out_button.disabled = true
		return

	var display_name := String(item.get("CardName"))
	if display_name.is_empty():
		# 既有数据里存在 CardName 为空的物品，回退到 CardId 以免界面出现无法辨认的空白。
		display_name = String(item.get("CardId"))

	if _selected["side"] == SIDE_WAREHOUSE:
		var stack = _get_warehouse_stack(_selected["index"])
		var amount := int(stack.Amount) if stack != null else 0
		_selected_label.text = "%s × %d" % [display_name, amount]
		_hint_label.text = "放入带入栏后可带进游戏"
		_put_in_button.disabled = not _has_free_carry_slot()
		_take_out_button.disabled = true
		return

	_selected_label.text = (
		"%s × %d" % [display_name, int(_carry_items[_selected["index"]]["count"])]
	)
	_hint_label.text = "取出后退回仓库"
	_put_in_button.disabled = true
	_take_out_button.disabled = false


## 刷新两个升级按钮的文案与可用性。
func _refresh_upgrade_buttons() -> void:
	if _progression == null:
		_upgrade_warehouse_button.text = "扩容不可用"
		_upgrade_warehouse_button.disabled = true
		_upgrade_carry_button.text = "扩栏不可用"
		_upgrade_carry_button.disabled = true
		return

	if bool(_progression.IsWarehouseMaxLevel()):
		_upgrade_warehouse_button.text = "仓库已满级"
		_upgrade_warehouse_button.disabled = true
	else:
		var warehouse_cost := int(_progression.GetWarehouseNextCost())
		_upgrade_warehouse_button.text = "仓库扩容 %d" % warehouse_cost
		_upgrade_warehouse_button.disabled = not _can_afford(warehouse_cost)

	if bool(_progression.IsCarryMaxLevel()):
		_upgrade_carry_button.text = "带入栏已满级"
		_upgrade_carry_button.disabled = true
	else:
		var carry_cost := int(_progression.GetCarryNextCost())
		_upgrade_carry_button.text = "带入栏 +1　%d" % carry_cost
		_upgrade_carry_button.disabled = not _can_afford(carry_cost)


# ── 交互 ───────────────────────────────────────────────────────────────────

## 格子被点击。
## @param slot 被点击的格子。
## @param side 该格子所属的一侧。
func _on_slot_clicked(slot: ItemSlot, side: StringName) -> void:
	var page_slots: Array[ItemSlot] = _carry_slots if side == SIDE_CARRY else _warehouse_slots
	var position_in_page := page_slots.find(slot)
	if position_in_page < 0:
		return

	var index := position_in_page
	if side == SIDE_WAREHOUSE:
		index = (_warehouse_page - 1) * PAGE_SIZE + position_in_page
		# 超出实际容量的尾格不可选。
		if index >= _warehouse_capacity():
			return

	_selected = {"side": side, "index": index}
	_set_status("", false)
	_refresh_selection_visuals()
	_refresh_action_area()


## 点击「放入」：把选中的仓库堆叠整堆移入带入栏。
func _on_put_in_pressed() -> void:
	if _selected.is_empty() or _selected["side"] != SIDE_WAREHOUSE:
		return

	var target := _first_free_carry_slot()
	if target < 0:
		_set_status("带入栏已满，先取出一些或升级容量", true)
		return

	var stack = _get_warehouse_stack(_selected["index"])
	if stack == null or stack.IsEmpty:
		_set_status("这一格已经空了", true)
		_refresh_all()
		return

	var item: Resource = stack.Item as Resource
	var amount := int(stack.Amount)

	# 权威不可用时必须提前失败：下面的顺序是「先移出仓库、再写带入栏」，
	# 若写不进去，物品已经从仓库消失，等于凭空销毁。
	if _carry_authority == null:
		_set_status("带入栏不可用，物品未移出仓库", true)
		return

	# 先移出再写入带入栏：移出失败时带入栏保持原样，不会凭空多出物品。
	if not bool(_warehouse.TryRemoveItem(item, amount)):
		_set_status("从仓库取出失败", true)
		return

	# 写入的是**权威**，视图会在 _refresh_all() 里按权威重建。
	# 理论上不会失败（target 已按可用栏位选取、权威刚刚校验过存在）；
	# 真失败时把物品退回仓库，避免无声销毁。
	if not bool(_carry_authority.call("SetCarryEntry", target, item, amount)):
		_warehouse.AddItem(item, amount)
		_set_status("带入栏写入失败，物品已退回仓库", true)
		_refresh_all()
		return

	_selected = {}
	_set_status("已放入带入栏", false)
	_refresh_all()


## 点击「取出」：把选中的带入栏内容退回仓库。
func _on_take_out_pressed() -> void:
	if _selected.is_empty() or _selected["side"] != SIDE_CARRY:
		return

	var index: int = _selected["index"]
	var entry: Dictionary = _carry_items[index]
	var item: Resource = entry["item"] as Resource
	if item == null:
		return

	var count := int(entry["count"])

	# 权威不可用时提前失败：否则物品会从界面消失、却根本没写进任何权威。
	if _carry_authority == null:
		_set_status("带入栏不可用，无法取回", true)
		return

	# 仓库放不下就不要取出：否则物品会从带入栏消失却进不了仓库，等于凭空销毁。
	if not bool(_warehouse.CanAddItem(item, count)):
		_set_status("仓库放不下，先整理或扩容", true)
		return

	_warehouse.AddItem(item, count)
	_carry_authority.call("ClearCarryEntry", index)
	_selected = {}
	_set_status("已取回仓库", false)
	_refresh_all()


## 点击「仓库扩容」。
func _on_upgrade_warehouse_pressed() -> void:
	if _progression == null:
		return

	if not bool(_progression.TryUpgradeWarehouse()):
		_set_status("金币不足，无法扩容", true)
		_refresh_action_area()
		return

	# 容量只影响总页数，每页格子数固定，因此不需要重建格子视图。
	_set_status("仓库容量已提升", false)
	_refresh_all()


## 点击「带入栏扩容」。
func _on_upgrade_carry_pressed() -> void:
	if _progression == null:
		return

	if not bool(_progression.TryUpgradeCarrySlots()):
		_set_status("金币不足，无法扩栏", true)
		_refresh_action_area()
		return

	_set_status("带入栏已扩充", false)
	_refresh_all()


## 点击「整理背包」：按名称排序仓库内容。
func _on_sort_pressed() -> void:
	if _warehouse == null:
		return

	_warehouse.SortByCardName()
	_selected = {}
	_set_status("已按名称整理", false)
	_refresh_all()


## 点击「进入商店」。
func _on_shop_pressed() -> void:
	GlobalEventBus.scene_requested.emit("shop")


## 点击「返回主菜单」。
func _on_exit_pressed() -> void:
	GlobalEventBus.scene_requested.emit("main_menu")


func _on_warehouse_prev_pressed() -> void:
	_warehouse_page -= 1
	_fill_warehouse_page()
	_refresh_selection_visuals()


func _on_warehouse_next_pressed() -> void:
	_warehouse_page += 1
	_fill_warehouse_page()
	_refresh_selection_visuals()


## 更新状态提示。
## @param text 提示文案；空字符串表示清空。
## @param is_error true 用警示色显示。
func _set_status(text: String, is_error: bool) -> void:
	_status_label.text = text
	_status_label.modulate = Color(1.0, 0.45, 0.45) if is_error else Color(0.6, 1.0, 0.7)


# ── 数据访问 ───────────────────────────────────────────────────────────────

## 读取仓库的总槽位数。
## @return int 槽位数；仓库缺失时返回 0。
func _warehouse_capacity() -> int:
	if _warehouse == null:
		return 0

	# 经 Object.get 跨越 C# 自动加载边界读取属性，避免把动态节点误当作静态 GDScript 属性。
	var capacity: Variant = _warehouse.get("Capacity")
	return int(capacity) if capacity != null else 0


## 读取仓库当前已占用的槽位数。
## @return int 非空槽位数量。
func _used_slot_count() -> int:
	var used := 0
	for i in _warehouse_capacity():
		var stack = _get_warehouse_stack(i)
		if stack != null and not stack.IsEmpty:
			used += 1

	return used


## 读取仓库中指定槽位的堆叠。
## @param index 槽位绝对序号。
## @return Variant 该槽位的 ItemStack；越界或仓库缺失时返回 null。
func _get_warehouse_stack(index: int):
	if _warehouse == null:
		return null
	if index < 0 or index >= _warehouse_capacity():
		return null
	return _warehouse.GetStackAt(index)


## 从权威重建带入栏视图。
##
## 视图长度固定为 CARRY_MAX_POSITIONS（与权威的 CARRY_SLOT_CAPACITY 同值），
## 因此任何调用方都可以按下标安全访问 `_carry_items`。
## 权威缺失（autoload 未装配）时退化为全空，让界面保持可用而不是整屏报错。
## 返回值：无。
func _sync_carry_view() -> void:
	_carry_items.clear()
	for i in CARRY_MAX_POSITIONS:
		if _carry_authority == null:
			_carry_items.append({"item": null, "count": 0})
			continue

		_carry_items.append(_carry_authority.call("GetCarryEntry", i))


## 读取当前可用的带入栏数量。
## @return int 可用栏位数，已收窄到合法范围。
func _active_carry_count() -> int:
	if _progression == null:
		return 0

	return clampi(int(_progression.GetCarrySlotCount()), 0, CARRY_MAX_POSITIONS)


## 读取当前金币。
## @return int 金币余额；钱包缺失时返回 0。
func _current_gold() -> int:
	if _wallet == null:
		return 0

	var gold: Variant = _wallet.get("Gold")
	return int(gold) if gold != null else 0


## 判断金币是否够付某个价格。
## @param cost 价格。
## @return bool 余额足够时为 true。
func _can_afford(cost: int) -> bool:
	return cost > 0 and _current_gold() >= cost


## 找第一个空闲的带入栏位。
## @return int 栏位序号；没有空位时返回 -1。
func _first_free_carry_slot() -> int:
	for i in _active_carry_count():
		if i >= _carry_items.size():
			break
		if _carry_items[i]["item"] == null:
			return i

	return -1


## 判断带入栏是否还有空位。
## @return bool 还有空位时为 true。
func _has_free_carry_slot() -> bool:
	return _first_free_carry_slot() >= 0


## 取当前选中的物品。
## @return Resource 选中的物品；未选中或选中格已空时返回 null。
func _selected_item() -> Resource:
	if _selected.is_empty():
		return null

	var index: int = _selected["index"]
	if _selected["side"] == SIDE_CARRY:
		if index < 0 or index >= _carry_items.size():
			return null
		return _carry_items[index]["item"] as Resource

	var stack = _get_warehouse_stack(index)
	if stack == null or stack.IsEmpty:
		return null
	return stack.Item as Resource


## 计算总页数。
## @param total 条目总数。
## @return int 页数，至少为 1（空列表也占一页，避免显示「1 / 0」）。
func _page_count(total: int) -> int:
	return maxi(1, int(ceil(float(total) / float(PAGE_SIZE))))
