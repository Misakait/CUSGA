@tool
extends McpTestSuite

## 仓库「数量拖拽」的纯逻辑契约：按数量搬运的数量守恒、洗炼属性保留、
## 无效目标无副作用，以及拖动会话的拆半向上取整、右键放置与加速曲线。
## 真实鼠标输入与原生拖动是否被中断属于运行验证，本套件不覆盖。
const TRANSFER: GDScript = preload("res://core/ui/warehouse/warehouse_transfer.gd")
const INVENTORY: GDScript = preload("res://entities/components/inventory_component.gd")
const CARRY: GDScript = preload("res://core/autoloads/ItemsControl.gd")
const ITEM: GDScript = preload("res://resources/item/item_data.gd")
const DRAG: GDScript = preload("res://core/ui/warehouse/warehouse_drag_controller.gd")

## 拖动会话的宿主桩：把会话提交转发到真实的 warehouse_transfer，并记录刷新与逐帧开关。
## 这样测试不需要真实 UI，也不会伪造搬运结果。
class StubHost extends Node:
	## 提交真正落到的传输层。
	var transfer: RefCounted
	## 每次 refresh_slot 的参数，用于断言「放置后刷新了来源与目标」。
	var refresh_calls: Array = []
	## set_drag_session_active 的调用序列，用于断言逐帧开关。
	var process_flags: Array = []

	func commit_placement(data: Dictionary, side: StringName, index: int, amount: int) -> int:
		return int(transfer.call("move_amount", data, side, index, amount))

	func commit_group_drop(data: Dictionary, side: StringName, index: int) -> bool:
		return bool(transfer.call("move", data, side, index))

	func refresh_slot(side: StringName, index: int) -> void:
		refresh_calls.append([side, index])

	func set_drag_session_active(active: bool) -> void:
		process_flags.append(active)

## 返回稳定测试套件名称；返回 warehouse_drag_quantity。
func suite_name() -> String:
	return "warehouse_drag_quantity"

## 验证仓库同区按数量搬运守恒：请求量、来源现有量与目标剩余空间三者取最小；
## 返回无。
func test_amount_move_between_warehouse_slots_conserves_items() -> void:
	var fixture: Dictionary = _fixture()
	var warehouse: Node = fixture["warehouse"]
	var transfer: RefCounted = fixture["transfer"]
	var item: Resource = _item("石块", 99)
	warehouse.call("AddItem", item, 10)
	assert_eq(int(transfer.call("move_amount", _drag(transfer, &"warehouse", 0), &"warehouse", 1, 4)), 4)
	assert_eq(int((warehouse.call("GetStackAt", 0) as Object).get("Amount")), 6)
	assert_eq(int((warehouse.call("GetStackAt", 1) as Object).get("Amount")), 4)
	# 请求量大于来源现有量时只搬走现有量，来源清空。
	assert_eq(int(transfer.call("move_amount", _drag(transfer, &"warehouse", 0), &"warehouse", 1, 9)), 6)
	assert_eq(int((warehouse.call("GetStackAt", 0) as Object).get("Amount")), 0)
	assert_eq(int((warehouse.call("GetStackAt", 1) as Object).get("Amount")), 10)

## 验证目标堆叠剩余空间不足时只搬走空间允许的数量，总量不丢不增；返回无。
func test_amount_move_into_partially_full_stack_keeps_total() -> void:
	var fixture: Dictionary = _fixture()
	var warehouse: Node = fixture["warehouse"]
	var transfer: RefCounted = fixture["transfer"]
	var item: Resource = _item("木材", 10)
	warehouse.call("AddItem", item, 15)
	assert_eq(int((warehouse.call("GetStackAt", 0) as Object).get("Amount")), 10)
	assert_eq(int((warehouse.call("GetStackAt", 1) as Object).get("Amount")), 5)
	assert_eq(int(transfer.call("move_amount", _drag(transfer, &"warehouse", 1), &"warehouse", 0, 4)), 0)
	# 目标已满：既不能搬运，也不允许发出变化信号掩盖失败。
	assert_eq(int((warehouse.call("GetStackAt", 0) as Object).get("Amount")), 10)
	assert_eq(int((warehouse.call("GetStackAt", 1) as Object).get("Amount")), 5)
	warehouse.call("AddItem", _item("木材", 10), 0)
	assert_eq(int(transfer.call("move_amount", _drag(transfer, &"warehouse", 1), &"warehouse", 2, 4)), 4)
	assert_eq(int((warehouse.call("GetStackAt", 1) as Object).get("Amount")), 1)
	assert_eq(int((warehouse.call("GetStackAt", 2) as Object).get("Amount")), 4)

## 验证扣减来源后洗炼属性仍在，洗炼属性随物品一起搬到目标；返回无。
func test_amount_move_keeps_rolled_attributes() -> void:
	var fixture: Dictionary = _fixture()
	var warehouse: Node = fixture["warehouse"]
	var transfer: RefCounted = fixture["transfer"]
	var item: Resource = _item("独立工具", 99)
	warehouse.call("AddItem", item, 9)
	(warehouse.call("GetStackAt", 0) as Object).set("RolledAttributes", {"power": 13})
	assert_eq(int(transfer.call("move_amount", _drag(transfer, &"warehouse", 0), &"warehouse", 1, 4)), 4)
	assert_eq((warehouse.call("GetStackAt", 0) as Object).get("RolledAttributes"), {"power": 13})
	assert_eq((warehouse.call("GetStackAt", 1) as Object).get("RolledAttributes"), {"power": 13})
	assert_eq(int((warehouse.call("GetStackAt", 0) as Object).get("Amount")), 5)
	# 来源被搬空时整格清空，洗炼属性不残留在空槽上。
	assert_eq(int(transfer.call("move_amount", _drag(transfer, &"warehouse", 0), &"warehouse", 1, 5)), 5)
	assert_eq((warehouse.call("GetStackAt", 0) as Object).get("RolledAttributes"), {})
	assert_eq((warehouse.call("GetStackAt", 0) as Object).get("Item"), null)
	assert_eq(int((warehouse.call("GetStackAt", 1) as Object).get("Amount")), 9)
	assert_eq((warehouse.call("GetStackAt", 1) as Object).get("RolledAttributes"), {"power": 13})

## 验证跨区按数量搬运双向守恒，并且行囊条目只保留 item/count；返回无。
func test_amount_move_across_sections_conserves_items() -> void:
	var fixture: Dictionary = _fixture()
	var warehouse: Node = fixture["warehouse"]
	var carry: Node = fixture["carry"]
	var transfer: RefCounted = fixture["transfer"]
	var item: Resource = _item("苹果", 99)
	warehouse.call("AddItem", item, 12)
	assert_eq(int(transfer.call("move_amount", _drag(transfer, &"warehouse", 0), &"carry", 0, 5)), 5)
	assert_eq(int(warehouse.call("ItemCnt", item)), 7)
	var entry: Dictionary = carry.call("GetCarryEntry", 0)
	assert_eq(entry.get("item"), item)
	assert_eq(entry.get("count"), 5)
	var back_snapshot: Dictionary = transfer.call("snapshot", &"carry", 0)
	assert_eq(back_snapshot.get("rolled"), {})
	assert_eq(int(transfer.call("move_amount", _drag(transfer, &"carry", 0), &"warehouse", 3, 5)), 5)
	assert_eq(int(warehouse.call("ItemCnt", item)), 12)
	entry = carry.call("GetCarryEntry", 0)
	assert_eq(entry.get("item"), null)
	assert_eq(entry.get("count"), 0)
	assert_false(bool(carry.call("HasCarryItems")))

## 验证行囊侧同类未满格按剩余空间接收，来源与目标都不越界丢物品；返回无。
func test_amount_move_merges_into_carry_stack_within_space() -> void:
	var fixture: Dictionary = _fixture()
	var warehouse: Node = fixture["warehouse"]
	var carry: Node = fixture["carry"]
	var transfer: RefCounted = fixture["transfer"]
	var item: Resource = _item("铁矿", 10)
	warehouse.call("AddItem", item, 12)
	carry.call("SetCarryEntry", 1, item, 8)
	assert_eq(int(transfer.call("move_amount", _drag(transfer, &"warehouse", 0), &"carry", 1, 6)), 2)
	assert_eq(int(warehouse.call("ItemCnt", item)), 10)
	assert_eq(int(carry.call("GetCarryEntry", 1).get("count")), 10)
	# 目标满堆叠后同一目标被拒绝，来源保持不变。
	assert_eq(int(transfer.call("move_amount", _drag(transfer, &"warehouse", 0), &"carry", 1, 1)), 0)
	assert_eq(int(warehouse.call("ItemCnt", item)), 10)
	assert_eq(int(carry.call("GetCarryEntry", 1).get("count")), 10)

## 验证不同物品、满堆叠、同一格、过期快照、越界与形状错误全部拒绝且无副作用；返回无。
func test_amount_move_rejections_have_no_side_effects() -> void:
	var fixture: Dictionary = _fixture()
	var warehouse: Node = fixture["warehouse"]
	var carry: Node = fixture["carry"]
	var transfer: RefCounted = fixture["transfer"]
	var left: Resource = _item("石块", 10)
	var right: Resource = _item("木头", 10)
	warehouse.call("AddItem", left, 10)
	warehouse.call("AddItem", right, 5)
	var stone_drag: Dictionary = _drag(transfer, &"warehouse", 1)
	# 不同物品的已占用格不接受按数量投放。
	assert_false(bool(transfer.call("can_receive_amount", stone_drag, &"warehouse", 0, 1)))
	assert_eq(int(transfer.call("move_amount", stone_drag, &"warehouse", 0, 1)), 0)
	# 同一格不能搬到自己身上。
	assert_false(bool(transfer.call("can_receive_amount", stone_drag, &"warehouse", 1, 1)))
	# 目标越界（仓库容量 6、行囊容量 5）与未知区域都拒绝。
	for target: Array in [[&"warehouse", 6], [&"carry", 5], [&"unknown", 0]]:
		assert_false(bool(transfer.call("can_receive_amount", stone_drag, target[0], target[1], 1)))
	# 过期快照：同一格数量被外部改动后拒绝。
	warehouse.call("AddItem", right, 1)
	assert_false(bool(transfer.call("can_receive_amount", stone_drag, &"warehouse", 2, 1)))
	assert_eq(int(transfer.call("move_amount", stone_drag, &"warehouse", 2, 1)), 0)
	var fresh: Dictionary = _drag(transfer, &"warehouse", 1)
	# 数量上限为 0 或负数的请求不算有效请求。
	assert_false(bool(transfer.call("can_receive_amount", fresh, &"warehouse", 2, 0)))
	assert_false(bool(transfer.call("can_receive_amount", fresh, &"warehouse", 2, -3)))
	assert_eq(int(transfer.call("move_amount", fresh, &"warehouse", 2, 0)), 0)
	# 形状错误的载荷（数量不是整数、洗炼属性不是字典）拒绝。
	assert_false(bool(transfer.call("can_receive_amount", {}, &"warehouse", 2, 1)))
	var broken: Dictionary = _drag(transfer, &"warehouse", 1)
	broken["amount"] = "six"
	assert_false(bool(transfer.call("can_receive_amount", broken, &"warehouse", 2, 1)))
	assert_false(bool(transfer.call("can_receive_amount", {"side": 12, "index": null}, &"warehouse", 2, 1)))
	# 全部失败路径之后权威不变。
	assert_eq(int((warehouse.call("GetStackAt", 0) as Object).get("Amount")), 10)
	assert_eq(int((warehouse.call("GetStackAt", 1) as Object).get("Amount")), 6)
	assert_eq(int((warehouse.call("GetStackAt", 2) as Object).get("Amount")), 0)
	assert_false(bool(carry.call("HasCarryItems")))

## 验证未选中拖全部、已选中拖一半并向上取整（数量 1 也照常拖走这 1 个）；返回无。
func test_drag_begin_amounts_follow_selection_state() -> void:
	var fixture: Dictionary = _drag_fixture()
	var warehouse: Node = fixture["warehouse"]
	var drag: RefCounted = fixture["drag"]
	var host: StubHost = fixture["host"]
	warehouse.call("AddItem", _item("矿石", 99), 9)
	warehouse.call("AddItem", _item("药草", 99), 2)
	warehouse.call("AddItem", _item("钥匙", 99), 1)
	# 已选中 9 → ceil(9 / 2) = 5，载荷仍记录来源的完整数量。
	var half: Dictionary = drag.call("begin", &"warehouse", 0, true)
	assert_eq(int(drag.call("remaining")), 5)
	assert_eq(int(half.get("amount")), 9)
	assert_eq(String(half.get("side")), "warehouse")
	assert_eq(int(half.get("index")), 0)
	assert_eq(int(half.get("owner")), host.get_instance_id())
	assert_true(half.has("token"))
	# 会话开始与结束都要切换逐帧处理。
	assert_eq(host.process_flags, [true])
	drag.call("cancel")
	assert_eq(host.process_flags, [true, false])
	# 已选中 2 → 1。
	drag.call("begin", &"warehouse", 1, true)
	assert_eq(int(drag.call("remaining")), 1)
	drag.call("cancel")
	# 已选中 1 → ceil(1 / 2) = 1：数量 1 也照常拖走这 1 个，不再有「数量 1 不启动」的特例。
	var single: Dictionary = drag.call("begin", &"warehouse", 2, true)
	assert_eq(int(drag.call("remaining")), 1)
	assert_eq(int(single.get("amount")), 1)
	drag.call("cancel")
	# 未选中 → 整组，载荷数量等于来源当前数量。
	var full: Dictionary = drag.call("begin", &"warehouse", 2, false)
	assert_eq(int(drag.call("remaining")), 1)
	assert_eq(int(full.get("amount")), 1)
	drag.call("cancel")
	# 空槽与越界位置不产生载荷。
	assert_true((drag.call("begin", &"warehouse", 5, false) as Dictionary).is_empty())
	assert_true((drag.call("begin", &"warehouse", 9, false) as Dictionary).is_empty())

## 验证右键按下放 1 个、松开立即停止连续放置，并且每次放置都刷新来源与目标；返回无。
func test_secondary_press_places_one_and_release_stops_repeat() -> void:
	var fixture: Dictionary = _drag_fixture()
	var warehouse: Node = fixture["warehouse"]
	var transfer: RefCounted = fixture["transfer"]
	var drag: RefCounted = fixture["drag"]
	var host: StubHost = fixture["host"]
	warehouse.call("AddItem", _item("矿石", 99), 20)
	drag.call("set_rates", 4.0, 0.0, 30.0)
	_bind_target(drag, host, transfer, [&"warehouse", 1])
	drag.call("begin", &"warehouse", 0, false)
	assert_eq(int(drag.call("remaining")), 20)
	assert_true(bool(drag.call("press_secondary")))
	assert_eq(_warehouse_amount(warehouse, 0), 19)
	assert_eq(_warehouse_amount(warehouse, 1), 1)
	assert_eq(int(drag.call("remaining")), 19)
	# 松开右键立即停止：继续按住左键也不再增加放置次数。
	drag.call("release_secondary")
	_advance(drag, 2.0)
	assert_eq(_warehouse_amount(warehouse, 0), 19)
	assert_eq(_warehouse_amount(warehouse, 1), 1)
	# 再次按下会重新计时：先放 1 个，再按初始速率 4 个/秒放 4 个
	# （PRD「按住 1 秒约放 4 个」即初始速率，加速度为 0 时正好是 4）。
	host.refresh_calls.clear()
	assert_true(bool(drag.call("press_secondary")))
	_advance(drag, 1.0)
	assert_eq(_warehouse_amount(warehouse, 0), 14)
	assert_eq(_warehouse_amount(warehouse, 1), 6)
	assert_eq(int(drag.call("remaining")), 14)
	# 每次放置都刷新来源与目标两个格子：1 + 4 次放置 × 2 个格子。
	assert_eq(host.refresh_calls.size(), 10)
	assert_eq(host.refresh_calls[0], [&"warehouse", 0])
	assert_eq(host.refresh_calls[1], [&"warehouse", 1])

## 验证按住右键逐渐加速，并在 r(t) 达到上限后稳定在约 30 个/秒；返回无。
func test_hold_accelerates_and_caps_at_max_rate() -> void:
	var fixture: Dictionary = _drag_fixture()
	var warehouse: Node = fixture["warehouse"]
	var transfer: RefCounted = fixture["transfer"]
	var drag: RefCounted = fixture["drag"]
	var host: StubHost = fixture["host"]
	warehouse.call("AddItem", _item("矿石", 9999), 400)
	drag.call("set_rates", 4.0, 8.0, 30.0)
	_bind_target(drag, host, transfer, [&"warehouse", 1])
	drag.call("begin", &"warehouse", 0, false)
	assert_true(bool(drag.call("press_secondary")))
	var counts: Array = []
	for _second: int in 6:
		var before: int = _warehouse_amount(warehouse, 1)
		_advance(drag, 1.0)
		counts.append(_warehouse_amount(warehouse, 1) - before)
	# r(t) = min(30, 4 + 8t)：逐秒变快，且第一秒明显多于初始速率的 4 个。
	assert_gt(int(counts[0]), 4)
	assert_gt(int(counts[1]), int(counts[0]))
	assert_gt(int(counts[2]), int(counts[1]))
	# 4 + 8 × 3.25 = 30，所以第 4 秒起进入上限区间，之后稳定在约 30 个/秒。
	assert_gt(int(counts[3]), 26)
	assert_true(int(counts[5]) >= 29 and int(counts[5]) <= 31)
	# 全程守恒：两格合计仍等于最初的 400。
	assert_eq(_warehouse_amount(warehouse, 0) + _warehouse_amount(warehouse, 1), 400)

## 验证逐个放置只接受空格或同类未满格，无效目标不消耗物品也不启动连续放置；返回无。
func test_secondary_rejects_invalid_targets_without_side_effects() -> void:
	var fixture: Dictionary = _drag_fixture()
	var warehouse: Node = fixture["warehouse"]
	var carry: Node = fixture["carry"]
	var transfer: RefCounted = fixture["transfer"]
	var drag: RefCounted = fixture["drag"]
	var host: StubHost = fixture["host"]
	var ore: Resource = _item("矿石", 10)
	warehouse.call("AddItem", ore, 9)
	warehouse.call("AddItem", _item("木材", 10), 5)
	(warehouse.call("GetStackAt", 2) as Object).call("SetItem", ore, 10)
	# 用「已选中」的拆半会话：拆半与逐个放置只接受空格或同类未满格。
	# 未选中的整组模式允许不同物品交换，那是 F10 的另一条规则，不在本用例范围。
	for target: Array in [[&"warehouse", 1], [&"warehouse", 0], [&"warehouse", 2], [&"carry", 5]]:
		_bind_target(drag, host, transfer, target)
		var data: Dictionary = drag.call("begin", &"warehouse", 0, true)
		assert_eq(int(drag.call("remaining")), 5)
		assert_false(bool(drag.call("can_drop", data, target[0], target[1])), "目标 %s 不应被拆半接受" % str(target))
		assert_false(bool(drag.call("press_secondary")), "目标 %s 不应被逐个放置接受" % str(target))
		# 无效目标不得启动连续放置：继续推进时间也不会放置。
		_advance(drag, 1.0)
		assert_eq(_warehouse_amount(warehouse, 0), 9)
		assert_eq(int(drag.call("remaining")), 5)
		drag.call("cancel")
	# 鼠标不在任何格子上时右键同样不消耗物品。
	_bind_target(drag, host, transfer, [])
	drag.call("begin", &"warehouse", 0, true)
	assert_false(bool(drag.call("press_secondary")), "没有悬停目标时不应放置")
	_advance(drag, 1.0)
	assert_eq(_warehouse_amount(warehouse, 0), 9)
	drag.call("cancel")
	# 有效目标仍然可以放置，排除「全都拒绝」的假通过。
	_bind_target(drag, host, transfer, [&"warehouse", 3])
	var good: Dictionary = drag.call("begin", &"warehouse", 0, true)
	assert_true(bool(drag.call("can_drop", good, &"warehouse", 3)))
	assert_true(bool(drag.call("press_secondary")))
	assert_eq(_warehouse_amount(warehouse, 0), 8)
	assert_eq(_warehouse_amount(warehouse, 3), 1)
	drag.call("cancel")
	assert_eq(_warehouse_amount(warehouse, 1), 5)
	assert_eq(_warehouse_amount(warehouse, 2), 10)
	assert_false(bool(carry.call("HasCarryItems")))

## 验证拆半投放把余量交给有效目标，取消与左键收尾把未放出的数量留在来源；返回无。
func test_half_drop_commits_remaining_and_cancel_keeps_the_rest() -> void:
	var fixture: Dictionary = _drag_fixture()
	var warehouse: Node = fixture["warehouse"]
	var transfer: RefCounted = fixture["transfer"]
	var drag: RefCounted = fixture["drag"]
	var host: StubHost = fixture["host"]
	warehouse.call("AddItem", _item("矿石", 99), 9)
	_bind_target(drag, host, transfer, [&"warehouse", 1])
	var data: Dictionary = drag.call("begin", &"warehouse", 0, true)
	assert_eq(int(drag.call("remaining")), 5)
	assert_true(bool(drag.call("press_secondary")))
	assert_eq(_warehouse_amount(warehouse, 0), 8)
	assert_eq(_warehouse_amount(warehouse, 1), 1)
	assert_eq(int(drag.call("remaining")), 4)
	host.refresh_calls.clear()
	# 松开左键投放到有效目标：余量 4 全部进入目标并结束会话。
	assert_true(bool(drag.call("drop", data, &"warehouse", 1)))
	assert_eq(_warehouse_amount(warehouse, 0), 4)
	assert_eq(_warehouse_amount(warehouse, 1), 5)
	assert_false(bool(drag.call("is_active")))
	assert_eq(int(drag.call("remaining")), 0)
	assert_eq(host.refresh_calls, [[&"warehouse", 0], [&"warehouse", 1]])
	# 投放到无效目标不成交，左键收尾丢弃会话，未放出的数量留在来源。
	warehouse.call("AddItem", _item("药草", 99), 9)
	_bind_target(drag, host, transfer, [&"warehouse", 3])
	var second: Dictionary = drag.call("begin", &"warehouse", 2, true)
	assert_eq(int(drag.call("remaining")), 5)
	assert_true(bool(drag.call("press_secondary")))
	assert_eq(_warehouse_amount(warehouse, 2), 8)
	assert_eq(_warehouse_amount(warehouse, 3), 1)
	assert_eq(int(drag.call("remaining")), 4)
	assert_false(bool(drag.call("drop", second, &"warehouse", 0)))
	assert_true(bool(drag.call("is_active")))
	drag.call("finish_after_release")
	assert_false(bool(drag.call("is_active")))
	assert_eq(_warehouse_amount(warehouse, 2), 8)
	assert_eq(_warehouse_amount(warehouse, 3), 1)
	assert_eq(_warehouse_amount(warehouse, 0), 4)
	# 药草的 9 个全部还在：8 个留在来源、1 个已放到目标格。
	assert_eq(_warehouse_amount(warehouse, 2) + _warehouse_amount(warehouse, 3), 9)

## 验证未选中的整组投放保留「不同物品交换」，外来或过期载荷不能提交；返回无。
func test_group_drop_swaps_different_items_and_rejects_foreign_payloads() -> void:
	var fixture: Dictionary = _drag_fixture()
	var warehouse: Node = fixture["warehouse"]
	var transfer: RefCounted = fixture["transfer"]
	var drag: RefCounted = fixture["drag"]
	var host: StubHost = fixture["host"]
	var ore: Resource = _item("矿石", 99)
	var wood: Resource = _item("木材", 99)
	warehouse.call("AddItem", ore, 5)
	warehouse.call("AddItem", wood, 7)
	_bind_target(drag, host, transfer, [&"warehouse", 1])
	var data: Dictionary = drag.call("begin", &"warehouse", 0, false)
	# 外来载荷：owner 不是当前宿主。
	var foreign: Dictionary = data.duplicate()
	foreign["owner"] = 1234
	assert_false(bool(drag.call("can_drop", foreign, &"warehouse", 1)))
	assert_false(bool(drag.call("drop", foreign, &"warehouse", 1)))
	# 过期载荷：令牌与当前会话不符。
	var stale: Dictionary = data.duplicate()
	stale["token"] = int(data["token"]) + 100
	assert_false(bool(drag.call("can_drop", stale, &"warehouse", 1)))
	# 缺少令牌键的裸快照（其它控件提供的拖动字典）也不能提交。
	assert_false(bool(drag.call("can_drop", _drag(transfer, &"warehouse", 0), &"warehouse", 1)))
	assert_eq(_warehouse_amount(warehouse, 0), 5)
	assert_eq(_warehouse_amount(warehouse, 1), 7)
	# 整组投放：不同物品交换。
	host.refresh_calls.clear()
	assert_true(bool(drag.call("drop", data, &"warehouse", 1)))
	assert_eq((warehouse.call("GetStackAt", 0) as Object).get("Item"), wood)
	assert_eq(_warehouse_amount(warehouse, 0), 7)
	assert_eq((warehouse.call("GetStackAt", 1) as Object).get("Item"), ore)
	assert_eq(_warehouse_amount(warehouse, 1), 5)
	assert_false(bool(drag.call("is_active")))
	assert_eq(host.refresh_calls, [[&"warehouse", 0], [&"warehouse", 1]])
	# 会话结束后同一份载荷不能再提交。
	assert_false(bool(drag.call("can_drop", data, &"warehouse", 2)))

## 验证行囊侧按数量搬运与跨区投放同样守恒，包括行囊内部与行囊到仓库；返回无。
func test_cross_section_amount_drag_conserves_items() -> void:
	var fixture: Dictionary = _drag_fixture()
	var warehouse: Node = fixture["warehouse"]
	var carry: Node = fixture["carry"]
	var transfer: RefCounted = fixture["transfer"]
	var drag: RefCounted = fixture["drag"]
	var host: StubHost = fixture["host"]
	var ore: Resource = _item("矿石", 99)
	carry.call("SetCarryEntry", 0, ore, 9)
	_bind_target(drag, host, transfer, [&"warehouse", 2])
	var data: Dictionary = drag.call("begin", &"carry", 0, true)
	assert_eq(int(drag.call("remaining")), 5)
	assert_eq(int(data.get("amount")), 9)
	assert_true(bool(drag.call("press_secondary")))
	assert_eq(int(carry.call("GetCarryEntry", 0).get("count")), 8)
	assert_eq(_warehouse_amount(warehouse, 2), 1)
	# 松开左键把余量 4 投放到仓库空格。
	assert_true(bool(drag.call("drop", data, &"warehouse", 2)))
	assert_eq(int(carry.call("GetCarryEntry", 0).get("count")), 4)
	assert_eq(_warehouse_amount(warehouse, 2), 5)
	assert_eq(int(warehouse.call("ItemCnt", ore)), 5)
	# 行囊内部按数量搬运：来源 4 全部搬到相邻栏位，行囊侧合计仍是 4（加上仓库的 5 共 9）。
	_bind_target(drag, host, transfer, [&"carry", 1])
	var inner: Dictionary = drag.call("begin", &"carry", 0, false)
	assert_eq(int(drag.call("remaining")), 4)
	assert_true(bool(drag.call("press_secondary")))
	assert_true(bool(drag.call("drop", inner, &"carry", 1)))
	assert_eq(int(carry.call("GetCarryEntry", 0).get("count")), 0)
	assert_eq(int(carry.call("GetCarryEntry", 1).get("count")), 4)
	assert_eq(carry.call("GetCarryEntry", 0).get("item"), null)
	assert_eq(int(carry.call("GetCarryEntry", 0).get("count")) + int(carry.call("GetCarryEntry", 1).get("count")), 4)

## 验证拖动预览的尺寸、图标与剩余数量文案，并随放置刷新；返回无。
func test_preview_shows_remaining_and_refreshes_after_placement() -> void:
	var fixture: Dictionary = _drag_fixture()
	var warehouse: Node = fixture["warehouse"]
	var transfer: RefCounted = fixture["transfer"]
	var drag: RefCounted = fixture["drag"]
	var host: StubHost = fixture["host"]
	var ore: Resource = _item("矿石", 99)
	warehouse.call("AddItem", ore, 9)
	drag.call("set_rates", 4.0, 0.0, 30.0)
	_bind_target(drag, host, transfer, [&"warehouse", 3])
	drag.call("begin", &"warehouse", 0, false)
	var preview: Control = track(drag.call("create_preview", ore)) as Control
	assert_true(preview != null)
	assert_eq(preview.custom_minimum_size, Vector2(56, 56))
	assert_eq(preview.get_child_count(), 2)
	var icon: TextureRect = preview.get_child(0) as TextureRect
	var label: Label = preview.get_child(1) as Label
	assert_eq(icon.texture, null)
	assert_eq(icon.stretch_mode, TextureRect.STRETCH_KEEP_ASPECT_CENTERED)
	assert_eq(label.text, "x9")
	assert_eq(label.horizontal_alignment, HORIZONTAL_ALIGNMENT_RIGHT)
	assert_eq(label.vertical_alignment, VERTICAL_ALIGNMENT_BOTTOM)
	# 每次放置后剩余数量文案同步减少：先放 1 个，再按 4 个/秒放 4 个。
	assert_true(bool(drag.call("press_secondary")))
	assert_eq(label.text, "x8")
	_advance(drag, 1.0)
	assert_eq(label.text, "x4")

func _drag_fixture() -> Dictionary:
	var fixture: Dictionary = _fixture()
	var host: StubHost = track(StubHost.new()) as StubHost
	host.transfer = fixture["transfer"]
	var drag: RefCounted = DRAG.new()
	# 先绑定一个空解析函数，用例再用 _bind_target 换成固定的悬停目标。
	drag.call("bind", host, fixture["transfer"], Callable())
	fixture["host"] = host
	fixture["drag"] = drag
	return fixture

## 绑定一个固定返回同一目标的解析函数。参数 drag 为会话、host 为桩宿主、
## transfer 为传输层、target 为目标数组；返回无。
func _bind_target(drag: RefCounted, host: Node, transfer: RefCounted, target: Array) -> void:
	drag.call("bind", host, transfer, func() -> Array: return target)

## 按固定步长推进若干秒。步长取 1/16 秒（二进制可精确表示），避免浮点误差累积。
func _advance(drag: RefCounted, seconds: float) -> void:
	var step: float = 0.0625
	for _index: int in int(round(seconds / step)):
		drag.call("tick", step)

## 读取仓库某个格子的数量。参数 warehouse 为仓库、index 为位置；返回数量。
func _warehouse_amount(warehouse: Node, index: int) -> int:
	return int((warehouse.call("GetStackAt", index) as Object).get("Amount"))

func _fixture() -> Dictionary:
	var warehouse: Node = track(INVENTORY.new()) as Node
	warehouse.set("Capacity", 6)
	var carry: Node = track(CARRY.new()) as Node
	var transfer: RefCounted = TRANSFER.new()
	transfer.call("bind", warehouse, carry, 5)
	return {"warehouse": warehouse, "carry": carry, "transfer": transfer}

func _item(display_name: String, maximum: int) -> Resource:
	var item: Resource = ITEM.new()
	item.set("CardName", display_name)
	item.set("MaxStackSize", maximum)
	return item

func _drag(transfer: RefCounted, side: StringName, index: int) -> Dictionary:
	var data: Dictionary = transfer.call("snapshot", side, index)
	data.merge({"side": side, "index": index})
	return data
