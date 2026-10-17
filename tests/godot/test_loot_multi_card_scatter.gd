@tool
extends McpTestSuite

## 掉落物多张卡牌化契约套件。
##
## 锁定三件事：多件掉落堆叠在棋盘入口被展开成「一件一张卡」、同批卡牌落点两两不小于
## 最小间距且留在房间安全区内、展开过程不修改调用方持有的原始堆叠。
##
## 本套件只测棋盘控制器的纯逻辑（展开与落点分配）。真正实例化视图、登记 RoomLootStore
## 记录需要完整场景与仓库节点，由运行期 game_eval 冒烟验证。

## 生产棋盘控制器脚本；测试直接实例化以调用其展开与落点逻辑。
const CONTROLLER_SCRIPT: GDScript = preload("res://core/board/board_controller.gd")
## 生产物品堆叠脚本。
const STACK_SCRIPT: GDScript = preload("res://resources/item/item_stack.gd")
## 固定随机种子，保证落点断言可复现，避免用例因随机性偶发失败。
const FIXED_SEED: int = 20260117
## 房间安全区边界，与控制器常量一致，用于断言落点没有越界。
const AREA_MIN: Vector2 = Vector2(90.0, 90.0)
const AREA_MAX: Vector2 = Vector2(1190.0, 630.0)
## 生产房间掉落仓库脚本；用于验证「一条记录 = 一件」在快照与移除路径上的自洽。
const LOOT_STORE_SCRIPT: GDScript = preload("res://core/map/room_loot_store.gd")
## 真实物品资源；快照编码只记资源路径与 CardId，恢复必须靠它找回物品。
const ITEM_RESOURCE_PATH: String = "res://items/item1.tres"
## 快照与移除用例使用的房间坐标，与其它用例互不共用仓库实例。
const TEST_ROOM: Vector2i = Vector2i(7, 7)


## 提供 GodotAI 使用的稳定套件名称。
func suite_name() -> String:
	return "loot_multi_card_scatter"


## 创建一个固定随机源的棋盘控制器实例；退出时由测试运行器释放。
func _make_controller() -> Node2D:
	var controller: Node2D = CONTROLLER_SCRIPT.new() as Node2D
	track(controller)
	var seeded: RandomNumberGenerator = RandomNumberGenerator.new()
	seeded.seed = FIXED_SEED
	controller.set("_rng", seeded)
	return controller


## 构造一个指定数量的物品堆叠；物品身份用普通 Resource 占位。
func _make_stack(amount: int) -> RefCounted:
	var stack: RefCounted = STACK_SCRIPT.new() as RefCounted
	stack.call("SetItem", Resource.new(), amount)
	return stack


## 计算落点数组中最小的两两距离，用于验证最小间距约束。
func _minimum_pairwise_distance(positions: Array) -> float:
	var smallest: float = INF
	for outer: int in range(positions.size()):
		for inner: int in range(outer + 1, positions.size()):
			var first: Vector2 = positions[outer]
			var second: Vector2 = positions[inner]
			smallest = minf(smallest, first.distance_to(second))
	return smallest


## 多件堆叠必须展开成同等数量的单件堆叠，物品身份保持一致。
func test_multi_amount_stack_expands_into_single_unit_stacks() -> void:
	var controller: Node2D = _make_controller()
	var item: Resource = Resource.new()
	var stack: RefCounted = STACK_SCRIPT.new() as RefCounted
	stack.call("SetItem", item, 3)

	var units: Array = controller.call("_expand_loot_units", [stack])

	assert_eq(units.size(), 3, "3 件掉落必须展开成 3 张卡所对应的 3 个单件堆叠。")
	for index: int in range(units.size()):
		var unit: RefCounted = units[index]
		assert_eq(int(unit.get("Amount")), 1, "第 %d 个单件堆叠的数量必须为 1。" % index)
		assert_true(unit.get("Item") == item, "展开后必须保留原物品资源身份。")
		assert_false(unit == stack, "展开必须产生独立堆叠对象，不能复用来源堆叠。")
	for outer: int in range(units.size()):
		for inner: int in range(outer + 1, units.size()):
			assert_false(units[outer] == units[inner], "不同卡牌不能共用同一个堆叠对象。")


## 数量已是 1 的堆叠（掉落表逐件生成的装备）必须原样复用，不产生无谓拷贝。
func test_single_amount_stack_is_reused_without_copying() -> void:
	var controller: Node2D = _make_controller()
	var stack: RefCounted = _make_stack(1)

	var units: Array = controller.call("_expand_loot_units", [stack])

	assert_eq(units.size(), 1, "单件掉落只能对应一张卡。")
	assert_true(units[0] == stack, "数量为 1 时必须复用原堆叠引用，避免破坏装备实例属性。")


## 展开不能就地改写来源堆叠，否则调用方会看到被掏空的掉落数组。
func test_expand_does_not_mutate_source_stack() -> void:
	var controller: Node2D = _make_controller()
	var stack: RefCounted = _make_stack(4)

	controller.call("_expand_loot_units", [stack])

	assert_eq(int(stack.get("Amount")), 4, "展开过程不得修改来源堆叠的数量。")


## 空值与无效堆叠必须被跳过，不能生成空卡牌。
func test_expand_skips_unreadable_stacks() -> void:
	var controller: Node2D = _make_controller()
	var empty_stack: RefCounted = _make_stack(0)

	var units: Array = controller.call("_expand_loot_units", [null, empty_stack])

	assert_eq(units.size(), 0, "空值与空堆叠不得产生任何单件堆叠。")


## 同批多张卡牌的落点两两距离必须不小于最小间距。
func test_plan_positions_keeps_minimum_separation() -> void:
	var controller: Node2D = _make_controller()
	var minimum_separation: float = float(controller.get("LootMinSeparation"))

	var positions: Array = controller.call("_plan_loot_positions", Vector2(640.0, 360.0), 3, true)

	assert_eq(positions.size(), 3, "3 张卡必须拿到 3 个落点。")
	assert_true(
		_minimum_pairwise_distance(positions) >= minimum_separation - 0.001,
		"落点两两距离必须不小于最小间距 %f。" % minimum_separation
	)


## 落点必须留在房间安全区内，避免生成到不可点击的边界外。
func test_plan_positions_stays_inside_room_bounds() -> void:
	var controller: Node2D = _make_controller()
	# 原点贴近左上角时夹取会把候选点压向边界，这里专门验证夹取结果仍然合法。
	var positions: Array = controller.call("_plan_loot_positions", Vector2(95.0, 95.0), 5, true)

	assert_eq(positions.size(), 5, "5 张卡必须拿到 5 个落点。")
	for index: int in range(positions.size()):
		var position: Vector2 = positions[index]
		assert_true(
			position.x >= AREA_MIN.x and position.x <= AREA_MAX.x
			and position.y >= AREA_MIN.y and position.y <= AREA_MAX.y,
			"第 %d 个落点 %s 越出房间安全区。" % [index, str(position)]
		)


## 张数较多时散射外半径必须自动放大，否则环带装不下全部落点。
func test_scatter_outer_radius_expands_for_many_cards() -> void:
	var controller: Node2D = _make_controller()
	var base_radius: float = float(controller.get("ScatterRadiusMax"))
	var minimum_separation: float = float(controller.get("LootMinSeparation"))

	var single_radius: float = float(controller.call("_resolve_scatter_outer_radius", 1, minimum_separation))
	var crowded_radius: float = float(controller.call("_resolve_scatter_outer_radius", 12, minimum_separation))

	assert_eq(single_radius, base_radius, "单件掉落必须沿用原散射最大半径，保持旧手感。")
	assert_true(
		crowded_radius > base_radius,
		"12 张卡的散射外半径 %f 必须大于默认 %f。" % [crowded_radius, base_radius]
	)


## 快照往返必须保持「一条记录 = 一件」：记录条数与各自落点都不能变。
##
## 拆分让记录条数从 1 条变成 N 条，编码格式本身没改；本用例锁定这条语义在存档往返后仍成立，
## 否则读档会把 N 张卡合成一张带数量的卡。
func test_snapshot_round_trip_preserves_unit_records() -> void:
	var item: Resource = load(ITEM_RESOURCE_PATH) as Resource
	assert_true(item != null, "快照往返用例需要 %s 可加载。" % ITEM_RESOURCE_PATH)
	if item == null:
		return

	var store: Node = LOOT_STORE_SCRIPT.new()
	track(store)
	var positions: Array[Vector2] = [
		Vector2(100.0, 110.0), Vector2(200.0, 220.0), Vector2(300.0, 330.0),
	]
	for index: int in range(positions.size()):
		var stack: RefCounted = STACK_SCRIPT.new() as RefCounted
		stack.call("SetItem", item, 1)
		store.call("AddLoot", TEST_ROOM, stack, positions[index])

	var encoded: Dictionary = store.call("SnapshotEncoded")
	var restored: Node = LOOT_STORE_SCRIPT.new()
	track(restored)
	restored.call("RestoreEncoded", encoded)
	var records: Array = restored.call("GetLoot", TEST_ROOM)

	assert_eq(records.size(), 3, "3 件掉落必须编码成 3 条记录，并在恢复后仍是 3 条。")
	for index: int in range(records.size()):
		var record: Dictionary = records[index]
		var restored_stack: RefCounted = record.get("stack") as RefCounted
		assert_eq(int(restored_stack.get("Amount")), 1, "第 %d 条恢复记录仍必须只承载 1 件。" % index)
		var restored_position: Vector2 = record.get("position")
		assert_true(
			restored_position.is_equal_approx(positions[index]),
			"第 %d 条恢复记录必须保持原落点 %s，实际 %s。" % [index, str(positions[index]), str(restored_position)]
		)


## 拾取其中一张卡只能移除那一条记录，其余卡牌的记录与堆叠不受影响。
func test_removing_one_record_keeps_other_cards() -> void:
	var item: Resource = load(ITEM_RESOURCE_PATH) as Resource
	var store: Node = LOOT_STORE_SCRIPT.new()
	track(store)
	var ids: Array[int] = []
	for index: int in range(3):
		var stack: RefCounted = STACK_SCRIPT.new() as RefCounted
		stack.call("SetItem", item, 1)
		var record: Dictionary = store.call("AddLoot", TEST_ROOM, stack, Vector2(150.0 + index * 70.0, 200.0))
		ids.append(int(record.get("id")))

	assert_true(store.call("RemoveLoot", TEST_ROOM, ids[1]), "拾取中间那张卡必须能按 id 移除记录。")
	var remaining: Array = store.call("GetLoot", TEST_ROOM)

	assert_eq(remaining.size(), 2, "拾取一张卡后必须只剩 2 条记录。")
	assert_false(store.call("RemoveLoot", TEST_ROOM, ids[1]), "同一条记录不得被重复移除结算。")
	var remaining_ids: Array[int] = []
	for record: Dictionary in remaining:
		remaining_ids.append(int(record.get("id")))
	assert_true(remaining_ids.has(ids[0]) and remaining_ids.has(ids[2]), "其余两张卡的记录必须原样保留。")
