@tool
extends McpTestSuite

## 开局角色与背包初始化契约套件（源需求 SR-1）。
##
## 套件锁定四件事：
## 1）带入栏权威的面：`ItemsControl` 的栏位容量常量、五个权威入口的行为（读取 / 写入 /
##    清空 / 是否有内容 / 取出即消耗），以及它是否已取代旧的紧凑导出数组；
## 2）常量镜像：`ItemsControl.CARRY_SLOT_CAPACITY` 与 `warehouse_control.CARRY_MAX_POSITIONS`
##    必须同值——界面按硬上限铺格子，权威按同一数量铺数组，只改一处会让界面与权威错位；
## 3）开局初始化的行为：按带入栏逐条装入、空带入栏留空背包、幂等、完成信号只广播一次、
##    溢出时按消耗语义不退回带入栏；
## 4）生产接线形状：Main 场景挂了初始化节点且排在 Player 之后、调试开局配置默认停用、
##    地图控制器与仓库界面已完成职责迁移。
##
## 编辑器侧只验证纯行为与源码形状：夹具刻意不加入场景树，因此不会触发 `_ready`、
## 也不会解析任何 autoload——`test_run` 环境没有 autoload，测试必须能用桩节点覆盖。
## 「带入栏清空后真实游戏里背包是否为空」属于运行链路，由主场景启动后的 `game_eval` 覆盖。

## 带入栏权威的生产脚本。
const ITEMS_CONTROL_SCRIPT: GDScript = preload("res://core/autoloads/ItemsControl.gd")
## 带入栏权威的生产脚本路径。
const ITEMS_CONTROL_GD: String = "res://core/autoloads/ItemsControl.gd"
## 仓库界面的生产脚本，用于读取其栏位上限镜像常量与验证迁移。
const WAREHOUSE_CONTROL_SCRIPT: GDScript = preload("res://scripts/warehouse/warehouse_control.gd")
## 仓库界面的生产脚本路径。
const WAREHOUSE_CONTROL_GD: String = "res://scripts/warehouse/warehouse_control.gd"
## 开局初始化入口的生产脚本。
const INITIALIZER_SCRIPT: GDScript = preload("res://core/gameflow/run_start_initializer.gd")
## 开局初始化入口的生产脚本路径。
const INITIALIZER_GD: String = "res://core/gameflow/run_start_initializer.gd"
## 玩家背包组件生产脚本，夹具使用真实实现而不是桩，避免测试自证。
const INVENTORY_SCRIPT: GDScript = preload("res://entities/components/inventory_component.gd")
## 堆叠上限为 1 的物品夹具脚本：物品协议要求真实 ItemData 派生资源，
## 技能卡是最稳定的「单张占一槽」生产类型（见 skill_card_data.gd 的 _resolve_actual_max_stack_size）。
const SKILL_CARD_SCRIPT: GDScript = preload("res://resources/item/card/skill_card_data.gd")
## 物品跨语言字段协议，用于自校验夹具的堆叠上限。
const ITEM_DATA_COMPAT: GDScript = preload("res://resources/item/item_data_compat.gd")
## 地图控制器脚本路径，用于验证旧带入实现已被移除。
const MAP_CONTROL_GD: String = "res://scripts/map_scripts/map_control.gd"
## 主场景路径。
const MAIN_SCENE_PATH: String = "res://scenes/Main.tscn"

## 带入栏权威桩：只实现开局初始化依赖的 `TakeCarryItems` 协议。
##
## 刻意**不**在取出后清空：如果初始化被错误地执行两次，桩会第二次交出同样内容，
## 于是背包数量翻倍——这比「桩自己也清空」更容易暴露幂等缺陷。
class CarryAuthorityStub extends Node:
	## 每次 TakeCarryItems() 返回的条目。
	var payload: Array = []
	## TakeCarryItems() 的调用次数，用于验证初始化只取一次。
	var take_call_count: int = 0

	func TakeCarryItems() -> Array:
		take_call_count += 1
		return payload


## RunStartInitialized 信号的广播次数。
var _initialized_signal_count: int = 0

## 携带桩节点的固定名字；夹具与 `CarrySourcePath` 都依赖它。
const CARRY_STUB_NAME: String = "CarryAuthorityStub"


## 返回 GodotAI 使用的稳定套件名称。
## 返回值：开局初始化契约套件名。
func suite_name() -> String:
	return "run_start_loadout_contract"


## 每个用例前复位信号计数，避免跨用例串味。
## 返回值：无。
func setup() -> void:
	_initialized_signal_count = 0


## 统计开局初始化完成信号的广播次数。
## 返回值：无。
func _on_run_start_initialized() -> void:
	_initialized_signal_count += 1


# ----- 夹具 -----

## 生成一个堆叠上限为 1 的物品夹具。
## 参数 suffix：附加到 CardId 的后缀，便于在同一用例里区分多个物品。
## 返回值：生产技能卡 Resource 实例。
func _make_stack_one_item(suffix: String) -> Resource:
	var card: Resource = SKILL_CARD_SCRIPT.new()
	card.set("CardId", StringName("test_run_start_%s" % suffix))
	card.set("CardName", "开局带入夹具-%s" % suffix)
	return card


## 搭建最小装配：host 下同时挂玩家（内含真实背包组件）与带入栏桩，
## 并把初始化节点也挂在 host 下，使 `../Player` 这类相对导出路径可解析。
##
## 夹具刻意**不**加入场景树：这样 `_ready` 不会触发，测试可以显式调用 `Initialize()`
## 观察行为，同时避开 `test_run` 没有 autoload 的限制。
## 参数 payload：带入栏桩要返回的条目列表。
## 参数 capacity：玩家背包容量；<= 0 时保留组件默认值。
## 返回值：{"initializer": Node, "inventory": Node, "carry": Node} 装配结果。
func _build_fixture(payload: Array, capacity: int = 0) -> Dictionary:
	var host: Node = track(Node.new()) as Node
	host.name = "InitializerHostFixture"

	var player: Node = track(Node.new()) as Node
	player.name = "Player"
	host.add_child(player)

	var components: Node = track(Node.new()) as Node
	components.name = "Components"
	player.add_child(components)

	var inventory: Node = track(INVENTORY_SCRIPT.new()) as Node
	inventory.name = "InventoryComponent"
	# 容量必须在任何 AddItem 之前写入：背包懒初始化会按当时的 Capacity 建槽位。
	if capacity > 0:
		inventory.set("Capacity", capacity)
	components.add_child(inventory)

	var carry: Node = track(CarryAuthorityStub.new()) as Node
	carry.name = CARRY_STUB_NAME
	carry.set("payload", payload)
	host.add_child(carry)

	var initializer: Node = track(INITIALIZER_SCRIPT.new()) as Node
	initializer.name = "RunStartInitializer"
	initializer.set("PlayerPath", NodePath("../Player"))
	initializer.set("CarrySourcePath", NodePath("../%s" % CARRY_STUB_NAME))
	initializer.set("InventoryComponentPath", NodePath("Components/InventoryComponent"))
	host.add_child(initializer)

	return {"initializer": initializer, "inventory": inventory, "carry": carry}


# ----- 带入栏权威 -----

## 验证权威容量常量与界面镜像常量同值，且等于带入栏硬上限 10。
## 返回值：无。
func test_carry_capacity_constant_matches_warehouse_mirror() -> void:
	var authority_constants: Dictionary = ITEMS_CONTROL_SCRIPT.get_script_constant_map()
	var warehouse_constants: Dictionary = WAREHOUSE_CONTROL_SCRIPT.get_script_constant_map()

	assert_has_key(authority_constants, "CARRY_SLOT_CAPACITY", "权威必须声明带入栏容量常量。")
	assert_has_key(warehouse_constants, "CARRY_MAX_POSITIONS", "界面必须保留栏位上限常量。")
	assert_eq(
		int(authority_constants.get("CARRY_SLOT_CAPACITY", -1)),
		10,
		"带入栏硬上限必须为 10（基础 5 + 5 级 × 1）。"
	)
	assert_eq(
		int(warehouse_constants.get("CARRY_MAX_POSITIONS", -1)),
		int(authority_constants.get("CARRY_SLOT_CAPACITY", -2)),
		"界面栏位上限必须与权威容量常量同值，否则界面与权威会错位。"
	)


## 验证权威五个入口的读写与边界行为。
## 返回值：无。
func test_carry_authority_api_round_trip() -> void:
	var authority: Node = track(ITEMS_CONTROL_SCRIPT.new()) as Node
	var capacity: int = int(ITEMS_CONTROL_SCRIPT.get_script_constant_map().get("CARRY_SLOT_CAPACITY", 0))
	var item: Resource = _make_stack_one_item("round_trip")

	# 未进树时 _ready 不执行，权威必须在**首次公开调用**时就补出固定长度的数组
	# （懒初始化契约）；因此这里先触碰一次公开入口，再检查底层数组长度。
	assert_false(bool(authority.call("HasCarryItems")), "初始带入栏必须为空。")
	assert_eq(
		(authority.get("carry_items") as Array).size(),
		capacity,
		"未进树的权威实例也必须铺满固定长度的栏位。"
	)

	assert_true(bool(authority.call("SetCarryEntry", 0, item, 3)), "写入合法栏位必须成功。")
	assert_true(bool(authority.call("HasCarryItems")), "写入后带入栏必须非空。")

	var entry: Dictionary = authority.call("GetCarryEntry", 0)
	assert_eq(entry.get("item"), item, "读取必须返回写入时的同一物品引用。")
	assert_eq(int(entry.get("count", 0)), 3, "读取必须返回写入时的堆叠数量。")

	# 返回值必须是副本：调用方就地改数量不得污染权威。
	entry["count"] = 99
	var reread: Dictionary = authority.call("GetCarryEntry", 0)
	assert_eq(int(reread.get("count", 0)), 3, "GetCarryEntry 必须返回副本而不是权威条目本身。")

	# 越界读取按「空栏位」降级，且不产生脚本错误。
	assert_eq(
		(authority.call("GetCarryEntry", -1) as Dictionary).get("item"),
		null,
		"越界读取必须降级为空条目。"
	)
	assert_eq(
		(authority.call("GetCarryEntry", capacity + 5) as Dictionary).get("item"),
		null,
		"越界读取必须降级为空条目。"
	)

	assert_true(bool(authority.call("ClearCarryEntry", 0)), "清空合法栏位必须成功。")
	assert_false(bool(authority.call("HasCarryItems")), "清空后带入栏必须回到空。")

	# 空物品 / 非正数量按「清空该栏位」处理，不需要调用方先判断。
	assert_true(bool(authority.call("SetCarryEntry", 0, item, 0)), "数量为 0 必须按清空处理。")
	assert_false(bool(authority.call("HasCarryItems")), "数量为 0 不得留下待带入内容。")


## 验证「取出即消耗」：取出后权威清空，第二次取出为空，且栏位长度保持不变。
## 返回值：无。
func test_take_carry_items_consumes_authority() -> void:
	var authority: Node = track(ITEMS_CONTROL_SCRIPT.new()) as Node
	var capacity: int = int(ITEMS_CONTROL_SCRIPT.get_script_constant_map().get("CARRY_SLOT_CAPACITY", 0))
	var first: Resource = _make_stack_one_item("consume_a")
	var second: Resource = _make_stack_one_item("consume_b")

	authority.call("SetCarryEntry", 1, first, 2)
	authority.call("SetCarryEntry", 3, second, 5)

	var taken: Array = authority.call("TakeCarryItems")
	assert_eq(taken.size(), 2, "取出必须只包含实际占用的栏位。")
	assert_eq((taken[0] as Dictionary).get("item"), first, "取出顺序必须按栏位序号。")
	assert_eq(int((taken[0] as Dictionary).get("count", 0)), 2, "取出必须保留堆叠数量。")
	assert_eq((taken[1] as Dictionary).get("item"), second, "取出顺序必须按栏位序号。")

	assert_false(bool(authority.call("HasCarryItems")), "取出后带入栏必须立即清空（带入即消耗）。")
	assert_eq(
		(authority.get("carry_items") as Array).size(),
		capacity,
		"取出后栏位数组长度必须保持不变。"
	)

	var second_take: Array = authority.call("TakeCarryItems")
	assert_eq(second_take.size(), 0, "第二次取出必须为空，同一批物品不得重复带入。")


# ----- 开局初始化 -----

## 验证按带入栏逐条装入：物品引用、堆叠数量与先后顺序都保持一致。
## 返回值：无。
func test_initializer_installs_carry_into_inventory() -> void:
	var first: Resource = _make_stack_one_item("install_a")
	var second: Resource = _make_stack_one_item("install_b")
	var fixture: Dictionary = _build_fixture(
		[
			{"item": first, "count": 2},
			{"item": second, "count": 7},
		]
	)
	var initializer: Node = fixture["initializer"]
	var inventory: Node = fixture["inventory"]

	assert_true(bool(initializer.call("Initialize")), "装配完整时初始化必须成功。")
	assert_eq(int(inventory.call("ItemCnt", first)), 2, "第一种带入物品的数量必须一致。")
	assert_eq(int(inventory.call("ItemCnt", second)), 7, "第二种带入物品的数量必须一致。")

	# 夹具物品的堆叠上限为 1，所以第一种物品会占满 ItemCnt(first) 个槽位，
	# 第二种物品必须紧接其后开始落槽——这一步验证的是带入栏的栏位先后顺序被保留。
	var first_stack = inventory.call("GetStackAt", 0)
	assert_eq(first_stack.get("Item"), first, "带入顺序必须按带入栏栏位顺序落槽。")

	var second_start: int = int(inventory.call("ItemCnt", first))
	var second_stack = inventory.call("GetStackAt", second_start)
	assert_eq(second_stack.get("Item"), second, "带入顺序必须按带入栏栏位顺序落槽。")


## 验证空带入栏开局：背包保持为空，不出现任何未经选择的物品，且仍广播完成信号。
## 返回值：无。
func test_empty_carry_leaves_inventory_empty() -> void:
	var fixture: Dictionary = _build_fixture([])
	var initializer: Node = fixture["initializer"]
	var inventory: Node = fixture["inventory"]
	initializer.connect(&"RunStartInitialized", Callable(self, "_on_run_start_initialized"))

	assert_true(bool(initializer.call("Initialize")), "空带入栏也必须视为初始化成功。")
	assert_eq(int(inventory.get("Capacity")), 27, "夹具应保留背包默认容量，便于断言空背包。")
	for index: int in int(inventory.get("Capacity")):
		var stack = inventory.call("GetStackAt", index)
		assert_true(bool(stack.get("IsEmpty")), "空带入栏开局后背包第 %d 槽必须为空。" % index)

	assert_eq(_initialized_signal_count, 1, "空带入栏开局也必须广播一次完成信号。")


## 验证幂等：重复调用不重复取内容、不重复装入、不重复广播。
## 返回值：无。
func test_initializer_is_idempotent_and_signals_once() -> void:
	var item: Resource = _make_stack_one_item("idempotent")
	var fixture: Dictionary = _build_fixture([{"item": item, "count": 2}])
	var initializer: Node = fixture["initializer"]
	var inventory: Node = fixture["inventory"]
	var carry: Node = fixture["carry"]
	initializer.connect(&"RunStartInitialized", Callable(self, "_on_run_start_initialized"))

	assert_true(bool(initializer.call("Initialize")), "首次初始化必须成功。")
	assert_true(bool(initializer.call("Initialize")), "重复调用必须仍然返回成功。")

	assert_eq(int(carry.get("take_call_count")), 1, "带入栏只能被取一次。")
	assert_eq(int(inventory.call("ItemCnt", item)), 2, "重复调用不得把带入物品装第二遍。")
	assert_eq(_initialized_signal_count, 1, "完成信号只能广播一次，否则后续开局环节会被触发两次。")


## 验证容量不足：放不下的部分留在背包之外，但**不**退回带入栏（带入即消耗）。
## 返回值：无。
func test_overflow_leftover_is_not_returned_to_carry() -> void:
	var item: Resource = _make_stack_one_item("overflow")
	# 先自校验夹具：堆叠上限必须为 1，否则「容量 2 + 5 个」不会真的溢出。
	assert_eq(
		int(ITEM_DATA_COMPAT.call("get_max_stack_size", item, 99)),
		1,
		"溢出用例依赖堆叠上限为 1 的物品夹具。"
	)

	var fixture: Dictionary = _build_fixture([{"item": item, "count": 5}], 2)
	var initializer: Node = fixture["initializer"]
	var inventory: Node = fixture["inventory"]
	var carry: Node = fixture["carry"]

	assert_true(bool(initializer.call("Initialize")), "容量不足不属于装配失败，初始化仍须返回成功。")
	assert_eq(int(inventory.call("ItemCnt", item)), 2, "背包只能装入容量允许的 2 个。")
	assert_eq(int(carry.get("take_call_count")), 1, "溢出时也必须只取一次带入栏。")
	assert_eq(
		int((carry.get("payload") as Array).size()),
		1,
		"桩不会再被回调：放不下的部分不得退回带入栏。"
	)


## 验证装配缺失时不广播完成信号，避免后续环节在背包未就绪时启动。
## 返回值：无。
func test_missing_player_reports_error_without_signal() -> void:
	expect_script_error_containing("未找到玩家节点")

	var host: Node = track(Node.new()) as Node
	var initializer: Node = track(INITIALIZER_SCRIPT.new()) as Node
	initializer.set("PlayerPath", NodePath("../MissingPlayer"))
	host.add_child(initializer)
	initializer.connect(&"RunStartInitialized", Callable(self, "_on_run_start_initialized"))

	assert_false(bool(initializer.call("Initialize")), "缺少玩家节点时初始化必须报告失败。")
	assert_eq(_initialized_signal_count, 0, "初始化失败时不得广播完成信号。")


# ----- 生产接线形状 -----

## 验证 Main 场景接线、调试配置让位，以及地图 / 仓库两侧的职责迁移。
## 返回值：无。
func test_production_wiring_shape() -> void:
	var main_text: String = FileAccess.get_file_as_string(MAIN_SCENE_PATH)
	assert_contains(main_text, 'name="RunStartInitializer"', "Main 场景必须挂载开局初始化节点。")
	assert_contains(main_text, INITIALIZER_GD, "开局初始化节点必须引用生产脚本。")

	var player_index: int = main_text.find('name="Player"')
	var initializer_index: int = main_text.find('name="RunStartInitializer"')
	assert_gt(player_index, -1, "Main 场景必须存在 Player 节点。")
	assert_gt(
		initializer_index,
		player_index,
		"初始化节点必须排在 Player 之后：同级 _ready 按树顺序触发，否则背包组件尚未就绪。"
	)

	var seeder_index: int = main_text.find('name="DebugLoadoutSeeder"')
	assert_gt(seeder_index, -1, "调试开局配置节点必须保留为手动工具。")
	assert_contains(
		main_text.substr(seeder_index, 240),
		"Enabled = false",
		"调试开局配置必须默认停用，否则会清空并覆盖按带入栏初始化的结果。"
	)

	var items_control_text: String = FileAccess.get_file_as_string(ITEMS_CONTROL_GD)
	assert_false(
		items_control_text.contains("warehouse_to_player"),
		"紧凑导出数组已被位置化的带入栏权威取代，不得回退。"
	)

	var map_control_text: String = FileAccess.get_file_as_string(MAP_CONTROL_GD)
	assert_false(
		map_control_text.contains("warehouse_to_player"),
		"地图控制器不得再消费旧导出数组。"
	)
	assert_false(
		map_control_text.contains("player._inventory"),
		"地图控制器不得再直接访问玩家私有背包字段。"
	)

	var warehouse_text: String = FileAccess.get_file_as_string(WAREHOUSE_CONTROL_GD)
	assert_contains(warehouse_text, "SetCarryEntry", "仓库界面写入必须落在带入栏权威上。")
	assert_contains(warehouse_text, "GetCarryEntry", "仓库界面必须从权威重建带入栏视图。")
	assert_contains(warehouse_text, "ClearCarryEntry", "仓库界面取出必须清空权威栏位。")
	assert_false(
		warehouse_text.contains("warehouse_to_player"),
		"仓库界面不得再维护旧导出数组。"
	)
