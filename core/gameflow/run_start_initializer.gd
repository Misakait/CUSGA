extends Node

## 开局初始化入口：把「带入栏」里的内容装进玩家背包，并广播初始化完成信号。
##
## 设计要点（完整论证见 .trellis/tasks/09-23-run-start-loadout-init/design.md）：
##
## 1）**唯一的开局初始化执行者**。原先的带入实现写在地图控制器
##    （`scripts/map_scripts/map_control.gd`）的 `_ready()` 里，与本节点的职责边界不符，
##    且直接读写玩家私有字段；本节点接管后，地图控制器不再触碰玩家背包。
##
## 2）**带入即消耗**。物品来自带入栏权威 `ItemsControl.TakeCarryItems()`，
##    取出后带入栏立即清空，因此同一批物品不会在下一局被重复带入。
##
## 3）**同步执行**。本节点挂在 `scenes/Main.tscn` 且排在玩家节点之后：
##    Godot 的同级 `_ready` 按树顺序触发，所以玩家的背包组件必定已完成初始化
##    （`InventoryComponent._ready()` 会建好空槽位）。同步执行同时天然早于
##    `DebugLoadoutSeeder` 的 `call_deferred`，顺序不依赖帧内延迟链。
##
## 4）**新一局要重置常驻时间**。`TimeSystem` 是 autoload，状态跨场景常驻；若不在新一局
##    开始时把它拨回第一天白天，玩家在黑夜退回主菜单再开一局就会直接进入黑夜。
##    重置点落在「非接续存档」分支，且必须早于昼夜滤镜 `_ready()` 的吸附
##    （本节点在 `Main.tscn` 中排在 `DayNightFilterLayer` 之前，这条顺序依赖由契约测试锁定）。
##
## 5）**可测**。所有依赖都通过「导出路径 + 稳定方法协议」访问，脚本里不出现
##    `ItemsControl` 标识符；测试（`test_run` 环境没有 autoload）可以用桩节点
##    改写 `CarrySourcePath` 来验证行为。

## 开局初始化完成信号。
##
## 后续开局环节（例如开局技能卡抽取）必须挂接本信号，而不要各自监听场景加载——
## 否则「初始化」与「抽卡」的先后顺序会随节点顺序、延迟调用而变化，不可复现。
signal RunStartInitialized

## 玩家节点相对本节点的路径。默认取同级 `Player`，与 `Main.tscn` 的布局一致。
@export var PlayerPath: NodePath = NodePath("../Player")

## 带入栏权威来源。默认指向 `ItemsControl` autoload；测试可改指桩节点。
@export var CarrySourcePath: NodePath = NodePath("/root/ItemsControl")

## 时间系统权威来源。默认指向 `TimeSystem` autoload；测试可改指桩节点。
@export var TimeSystemPath: NodePath = NodePath("/root/TimeSystem")

## 玩家背包组件相对玩家节点的路径，与 `player.tscn` 的 `Components` 布局一致。
@export var InventoryComponentPath: NodePath = NodePath("Components/InventoryComponent")

## 是否输出初始化细节日志。
## 默认关闭：正式开局不需要刷屏。需要排查「到底带进来了什么」时可在检查器里临时打开，
## 该开关只影响日志，不参与任何判定，因此运行时动态修改是安全的。
@export var VerboseLog: bool = false

## 本次开局是否已经执行过初始化。
##
## 存在的理由：`Initialize()` 必须幂等。当前 `Main` 不会被重复装配，但一旦出现
## 重复调用（场景重载、外部手工触发、将来新增的开局流程钩子），没有这个标志
## 就会把同一份带入内容装第二遍，而带入栏已经清空、第二次只会拿到空数组——
## 表面上「没出错」，实际上掩盖了流程被重复触发的事实。
var _has_initialized: bool = false
var _restored_run: bool = false


## 节点就绪时执行一次开局初始化。
## 返回值：无。
func _ready() -> void:
	Initialize()


## 执行开局初始化：取出带入栏内容 → 清空带入栏 → 清空背包 → 逐条装入 → 广播信号。
##
## 返回值：true 表示本次调用后玩家背包已按带入栏就绪（含幂等重入）；
##         false 表示存在无法忽略的装配问题（缺玩家或缺背包组件），此时不广播信号。
func Initialize() -> bool:
	# 幂等：重复调用不再碰背包，也不再重复广播，避免后续环节被触发两次。
	if _has_initialized:
		return true

	var player: Node = get_node_or_null(PlayerPath)
	if player == null:
		push_error("RunStartInitializer: 未找到玩家节点 %s，开局带入未执行。" % str(PlayerPath))
		return false

	var inventory: Node = player.get_node_or_null(InventoryComponentPath)
	if inventory == null:
		push_error(
			"RunStartInitializer: 玩家缺少背包组件 %s，开局带入未执行。" % str(InventoryComponentPath)
		)
		return false

	_has_initialized = true
	var run_snapshot: Node = get_node_or_null("../RuntimeState/RunSnapshot")
	if run_snapshot != null and bool(run_snapshot.call("HasPendingRun")):
		_restored_run = bool(run_snapshot.call("RestorePlayer", player, inventory, get_node_or_null("../PlayerChar")))
		if _restored_run:
			RunStartInitialized.emit()
			return true

	# 新一局：把常驻的时间系统拨回开局状态。
	# 必须早于昼夜滤镜的 _ready() 吸附，否则滤镜会先按上局的夜色着色再慢慢过渡过来。
	_reset_time()

	# 先清空背包再装入：新一局的玩家是全新实例（默认背包为空，见 player.tscn），
	# 清空让「初始化」的语义与调用次数无关——任何重复触发都不会累积内容。
	# 出战卡组与装备不需要额外清空，理由同上：它们在 player.tscn 里同样没有预置内容，
	# 唯一会填它们的 DebugLoadoutSeeder 已默认停用（启用它即表示有意覆盖开局带入）。
	var cleared_count: int = _clear_inventory(inventory)

	var entries: Array = _take_carry_entries()
	var installed_count: int = _fill_inventory(inventory, entries)

	if VerboseLog:
		print(
			"[RunStartInitializer] 开局带入完成：清空 %d 个槽位，完整装入 %d 类物品。"
			% [cleared_count, installed_count]
		)

	RunStartInitialized.emit()
	return true


## 查询本次开局是否已经完成初始化。
##
## 存在的理由：开局环节（例如开局技能卡抽取）若挂在 `Main.tscn` 的 UI 之下，它的 `_ready()`
## 必然晚于本节点——Godot 的同级 `_ready` 按树顺序触发，而本节点会**同步**广播信号，
## 于是挂在后面的监听者永远收不到那一次广播。让「是否已初始化」可查询之后，后续环节就能
## 「先订阅、再补偿检查」，从而不把正确性押在不可见的节点顺序上。
## 返回值：true 表示本次开局已经执行过初始化（含幂等重入后的状态）。
func HasInitialized() -> bool:
	return _has_initialized


## 查询本次启动是否接续磁盘上的局内快照。
## @return 接续成功时为 true。
func IsContinuingRun() -> bool:
	return _restored_run


## 把时间系统拨回新一局的初始状态：第一天、白天、累计时间为零。
##
## 为什么必须做：`TimeSystem` 是 autoload，状态在整个进程内常驻。玩家在黑夜退回主菜单、
## 再开新一局时 `Main` 会重新加载，但时间仍停在上局的黑夜，而昼夜滤镜在 `_ready()` 里
## 按当前时间吸附颜色，于是新一局开局就是黑夜。这条重置只走「新一局」路径；
## 接续存档不经过这里 —— 那条路径由 `RunSnapshot.RestorePlayer` 还原时间。
##
## 为什么用 `RestoreSnapshot` 而不是新增接口：它只广播 `TimeChanged`、不广播
## `DayNightToggled`，因此不会误触发「昼夜切换」的跨阶段副作用，语义上正是
## 「把时间直接放到指定状态」，也就无需改动 TimeSystem 本身。
## 参数：无。返回值：无。
func _reset_time() -> void:
	var time_system: Node = get_node_or_null(TimeSystemPath)
	if time_system == null:
		# 可降级依赖：没有时间系统时开局流程照常，只是天数不会回到第一天。
		push_warning(
			"RunStartInitializer: 未找到时间系统 %s，新一局的时间未重置。" % str(TimeSystemPath)
		)
		return

	if not time_system.has_method("RestoreSnapshot"):
		push_warning(
			"RunStartInitializer: %s 未提供 RestoreSnapshot 协议，新一局的时间未重置。"
			% str(TimeSystemPath)
		)
		return

	time_system.call("RestoreSnapshot", 0, 1, false)


## 取出带入栏权威里的全部待带入条目，并让其清空。
##
## 降级约定：权威缺失或协议不符时返回空数组并报错，而不是用任何物品兜底——
## 需求要求背包内容严格等于玩家在带入栏选定的物品，背包为空是合法结果。
## 返回值：[{"item": Resource, "count": int}, ...]；没有待带入内容时为空数组。
func _take_carry_entries() -> Array:
	var authority: Node = get_node_or_null(CarrySourcePath)
	if authority == null:
		push_error(
			"RunStartInitializer: 未找到带入栏权威 %s，本局不带入任何物品。" % str(CarrySourcePath)
		)
		return []

	if not authority.has_method("TakeCarryItems"):
		push_error(
			"RunStartInitializer: %s 未提供 TakeCarryItems 协议，本局不带入任何物品。"
			% str(CarrySourcePath)
		)
		return []

	var taken: Array = authority.call("TakeCarryItems")
	return taken


## 清空背包的全部槽位。
##
## 参数 inventory：实现 `Capacity` 与 `TryClearStackAt` 协议的组件。
## 返回值：实际清空的非空槽位数量，仅用于日志与测试断言。
func _clear_inventory(inventory: Node) -> int:
	# 容量经 Object.get 读取，保持对 C# 与 GDScript 组件的一致访问方式。
	var capacity_value: Variant = inventory.get("Capacity")
	var capacity: int = int(capacity_value) if capacity_value != null else 0

	var cleared_count: int = 0
	for index: int in capacity:
		if bool(inventory.call("TryClearStackAt", index)):
			cleared_count += 1

	return cleared_count


## 把带入条目逐条装入背包。
##
## 参数 inventory：实现 `AddItem(item, amount) -> int` 协议的组件。
## 参数 entries：`_take_carry_entries()` 的返回值。
## 返回值：被完整装入的物品种类数（放不下的种类不计入）。
func _fill_inventory(inventory: Node, entries: Array) -> int:
	var installed_count: int = 0
	for entry_value: Variant in entries:
		if not (entry_value is Dictionary):
			continue

		var entry: Dictionary = entry_value
		var item: Resource = entry.get("item") as Resource
		var count: int = int(entry.get("count", 0))
		if item == null or count <= 0:
			continue

		var leftover: int = int(inventory.call("AddItem", item, count))
		if leftover > 0:
			# 放不下的部分**不退回带入栏**：权威已在 TakeCarryItems() 里清空，
			# 这是「带入即消耗」的必然结果。因此必须留下可诊断的警告，
			# 让「背包容量小于所选带入量」这个问题能被发现，而不是无声销毁物品。
			push_warning(
				"RunStartInitializer: 背包放不下 %s，溢出 %d 个（按消耗语义不退回带入栏）。"
				% [_item_display_name(item), leftover]
			)
		else:
			installed_count += 1

	return installed_count


## 读取物品用于日志的显示名。
##
## 参数 item：物品 Resource。
## 返回值：优先 CardName；为空时回退 CardId；都取不到时返回 `<unknown>`。
func _item_display_name(item: Resource) -> String:
	var card_name: Variant = item.get("CardName")
	if card_name != null and not str(card_name).strip_edges().is_empty():
		return str(card_name)

	var card_id: Variant = item.get("CardId")
	return str(card_id) if card_id != null else "<unknown>"
