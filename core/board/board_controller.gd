extends Node2D

## 棋盘卡牌控制器的 GDScript 生产实现，等价迁移自 core/board/BoardController.cs。
##
## 控制器只负责卡牌视图生命周期：创建地形/掉落卡状态、挂到房间内容根、连接并转发视图信号，
## 以及按局部网格维护地形卡索引。卡状态由 board_card_state.gd 承载，地形与掉落分别由独立视图场景承载，
## 两者都可能来自任一语言，因此统一走方法协议访问。
## 不声明 class_name，避免与仍在使用的 C# 全局类型重名。

## 生成一张卡牌后发出，参数为该卡牌视图。
signal CardSpawned(card: Node2D)
## 卡牌被移除后发出，参数为该卡牌视图。
signal CardRemoved(card: Node2D)
## 卡牌单击时发出。
signal CardClicked(card: Node2D)
## 卡牌按下时发出。
signal CardPressed(card: Node2D)
## 卡牌松开时发出。
signal CardReleased(card: Node2D)
## 悬停开始时发出。
signal CardHoverStarted(card: Node2D)
## 悬停结束时发出。
signal CardHoverEnded(card: Node2D)

## 棋盘卡状态脚本；旧 C# 垫片通过 GD.Load 加载同一路径，两侧共用同一份状态实现。
const BOARD_CARD_STATE_SCRIPT: GDScript = preload("res://core/board/board_card_state.gd")

## 本控制器对外广播的生成/移除信号名，与旧 C# 字面量一致。
const CARD_SPAWNED_SIGNAL: StringName = &"CardSpawned"
const CARD_REMOVED_SIGNAL: StringName = &"CardRemoved"
const CARD_CLICKED_SIGNAL: StringName = &"CardClicked"
const CARD_PRESSED_SIGNAL: StringName = &"CardPressed"
const CARD_RELEASED_SIGNAL: StringName = &"CardReleased"
const CARD_HOVER_STARTED_SIGNAL: StringName = &"CardHoverStarted"
const CARD_HOVER_ENDED_SIGNAL: StringName = &"CardHoverEnded"
## 卡牌视图自身提供的交互信号名，与 BoardCardView 的信号声明一致。
const VIEW_CLICKED_SIGNAL: StringName = &"Clicked"
const VIEW_PRESSED_SIGNAL: StringName = &"Pressed"
const VIEW_RELEASED_SIGNAL: StringName = &"Released"
const VIEW_HOVER_STARTED_SIGNAL: StringName = &"HoverStarted"
const VIEW_HOVER_ENDED_SIGNAL: StringName = &"HoverEnded"
## 掉落堆叠脚本；仅在没有 Duplicate 协议的遗留堆叠上用于重建单件堆叠。
const LOOT_STACK_SCRIPT: GDScript = preload("res://resources/item/item_stack.gd")
## 单个落点的最大随机重试次数；用尽后接受当前候选，而不是丢掉这次掉落。
const SCATTER_PLACEMENT_ATTEMPTS: int = 16
## 掉落卡允许出现的房间局部坐标下界，四边都留出可点击的安全带。
const LOOT_AREA_MIN: Vector2 = Vector2(90.0, 90.0)
## 掉落卡允许出现的房间局部坐标上界。
const LOOT_AREA_MAX: Vector2 = Vector2(1190.0, 630.0)
## 六边形最密排布下每个圆心占用的面积系数，单位是「最小间距的平方」。
const CIRCLE_PACKING_AREA_FACTOR: float = 0.866

## 地形卡视图预制体；主场景绑定 Item.tscn。
@export var TerrainViewScene: PackedScene = null
## 掉落物视图预制体；掉落物不再复用地形卡场景。
@export var LootViewScene: PackedScene = null
## 旧的统一卡牌预制体入口，仅用于未迁移的独立场景回退。
@export var CardViewScene: PackedScene = null
## 卡牌父节点路径；留空时直接挂到控制器自身。
@export var CardsRootPath: NodePath = NodePath("")
## 地图视图路径；用于旧掉落入口确定当前房间。
@export var MapViewPath: NodePath = NodePath("")
## 本局掉落仓库路径；留空时保持独立测试的旧生成行为。
@export var LootStorePath: NodePath = NodePath("")
## 掉落散射的最小半径。
@export var ScatterRadiusMin: float = 40.0
## 掉落散射的最大半径。
@export var ScatterRadiusMax: float = 90.0
## 同一批掉落中两张卡牌落点的最小圆心距。
##
## 默认 56 来自掉落卡的实际可视尺寸：`Loot.tscn` 的 `PlayerView` 为 100×140，
## 运行时按 `LootVisualScale`(0.4) 缩放后约为 40×56，取较长边保证两张卡不会叠成一张。
@export var LootMinSeparation: float = 56.0

## 卡牌视图父节点。
var _cards_root: Node2D = null
## 掉落散射使用的随机源，语义等价旧 C# RandomNumberGenerator。
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
## 当前仍在棋盘上的卡牌；用数组保存以保持稳定顺序，集合语义等价旧 C# HashSet。
var _active_cards: Array[Node2D] = []
## 局部网格坐标到地形卡的索引。
var _terrain_cards_by_local_grid: Dictionary = {}
## 房间坐标到局部格子索引，避免九房的同名格子互相覆盖。
var _terrain_cards_by_room: Dictionary = {}
var _room_by_card: Dictionary = {}
var _loot_cards_by_id: Dictionary = {}
var _map_view: Node = null
var _loot_store: Node = null


## 进入场景树时校验视图预制体并解析卡牌根节点。
##
## @return 无返回值。
func _ready() -> void:
	# 保留旧入口是为了让旧测试场景继续可运行，但生产 Main 必须分别绑定两类视图。
	if TerrainViewScene == null:
		TerrainViewScene = CardViewScene
	if LootViewScene == null:
		LootViewScene = CardViewScene
	if TerrainViewScene == null or LootViewScene == null:
		push_error("BoardController 需要同时设置 TerrainViewScene 与 LootViewScene。")
		return

	_cards_root = self if CardsRootPath.is_empty() else get_node(CardsRootPath) as Node2D
	_map_view = get_node_or_null(MapViewPath) if not MapViewPath.is_empty() else null
	_loot_store = get_node_or_null(LootStorePath) if not LootStorePath.is_empty() else null


## 退出场景树时断开全部卡牌信号并清空索引，避免跨场景残留回调。
##
## @return 无返回值。
func _exit_tree() -> void:
	for card: Node2D in _active_cards:
		if is_instance_valid(card):
			_disconnect_card_signals(card)

	_active_cards.clear()
	_terrain_cards_by_local_grid.clear()
	_terrain_cards_by_room.clear()
	_room_by_card.clear()
	_loot_cards_by_id.clear()


## 在指定全局坐标生成一张地形卡，并按局部网格登记索引。
##
## @param terrain_instance 旧 C# 或 GDScript 地形实例，必须带有 TerrainData。
## @param global_position 地形卡的目标全局坐标。
## @return 新生成的地形卡视图；参数无效或网格重复时返回 null。
func SpawnTerrainCard(terrain_instance: RefCounted, global_position: Vector2) -> Node2D:
	if terrain_instance == null:
		push_error("BoardController.SpawnTerrainCard 需要非空的地形实例。")
		return null

	# 地形实例已迁移到 GDScript，局部网格坐标统一经跨语言字段协议读取。
	var local_grid_pos: Vector2i = _read_local_grid_pos(terrain_instance)
	if _terrain_cards_by_local_grid.has(local_grid_pos):
		push_error("Grid %s 已经存在地形卡。" % str(local_grid_pos))
		return null
	print("[BoardController] Spawn terrain card at %s, localGrid=%s" % [str(global_position), str(local_grid_pos)])

	var state: RefCounted = _create_terrain_state(terrain_instance)
	if state == null:
		return null

	var card: Node2D = _spawn_card(state, global_position)
	if card == null:
		return null

	_terrain_cards_by_local_grid[local_grid_pos] = card
	return card


## 在指定房间的内容根节点上生成地形；局部坐标由房间仓库提供。
## @param room 房间坐标。
## @param terrain_instance 地形实例。
## @param local_position 房间局部坐标。
## @param root 房间内容根节点。
## @return 地形卡视图；重复格子返回 null。
func SpawnTerrainCardForRoom(room: Vector2i, terrain_instance: RefCounted, local_position: Vector2, root: Node2D) -> Node2D:
	if terrain_instance == null or root == null:
		return null
	var grid: Vector2i = _read_local_grid_pos(terrain_instance)
	var room_cards: Dictionary = _terrain_cards_by_room.get(room, {})
	if room_cards.has(grid):
		return null
	var state: RefCounted = _create_terrain_state(terrain_instance)
	if state == null:
		return null
	var card: Node2D = _spawn_card(state, root.to_global(local_position), root)
	if card == null:
		return null
	card.call("SetRoomIdentity", room)
	room_cards[grid] = card
	_terrain_cards_by_room[room] = room_cards
	_room_by_card[card] = room
	return card


## 根据仓库记录重建一张掉落卡，直接显示在记录位置。
##
## 本方法**不**播放掉落飞出动画：调用方是房间流式恢复，这些掉落物不是「刚被破坏产出」，
## 直接出现在记录位置才是正确表现。破坏产出需要飞出动画时改用 SpawnLootRecordWithScatter。
##
## 注意：不要在签名末尾再加「可选散射起点」这类参数。早期版本把「落在哪里」和「是否播
## 飞出动画」两种语义挤在同一个可选参数里，读代码的人无从判断调用方该走哪条路径；拆成
## 两个方法之后语义才明确，也才看得清房间恢复路径本就不该有动画。
##
## @param room 房间坐标。
## @param record 含 id、stack、position 的仓库记录。
## @param root 房间内容根节点。
## @return 掉落卡视图或 null。
func SpawnLootRecord(room: Vector2i, record: Dictionary, root: Node2D) -> Node2D:
	if root == null:
		return null
	var id: int = int(record.get("id", -1))
	if _loot_cards_by_id.has(id):
		return _loot_cards_by_id[id] as Node2D
	var stack: RefCounted = record.get("stack") as RefCounted
	var state: RefCounted = _create_loot_state(stack)
	if state == null:
		return null
	var target: Vector2 = root.to_global(record.get("position", Vector2.ZERO))
	var card: Node2D = _spawn_card(state, target, root)
	if card == null:
		return null
	card.call("SetRoomIdentity", room, id)
	_room_by_card[card] = room
	_loot_cards_by_id[id] = card
	return card


## 根据仓库记录生成一张掉落卡，并播放「从破坏点飞到最终落点」的掉落动画。
##
## 与 SpawnLootRecord 的唯一区别是是否播放飞出动画：本方法用于破坏物品（采集、拆除）
## 产出掉落物的场合，掉落物必须可见地从原物品位置飞出，而不是凭空出现在落点。
##
## 起点声明为**必填的强类型 Vector2 形参**：破坏产出必然有起点，不留默认值可以让漏传
## 在编译期就暴露，而不是静默退化成「直接出现在最终落点」这种难以察觉的表现。
##
## @param room 房间坐标。
## @param record 含 id、stack、position 的仓库记录。
## @param root 房间内容根节点。
## @param scatter_origin 散射起点（原物品所在位置）的全局坐标。
## @return 掉落卡视图；记录无效时返回 null。
func SpawnLootRecordWithScatter(room: Vector2i, record: Dictionary, root: Node2D, scatter_origin: Vector2) -> Node2D:
	# SpawnLootRecord 对同一 id 会返回已在场的卡，而不是新建：RoomLootStore.AddLoot 会
	# 同步发出 LootAdded，UIRoomBoardPresenter 监听后已经抢先生成过一次卡。两次生成发生在
	# 同一个调用栈内、中间不渲染任何一帧，所以这里拿到的那张卡对玩家而言仍是「刚出现」的，
	# 必须照常播放飞出动画。早期实现判断「卡已存在就跳过散射」，结果散射被这次早退整个吞掉，
	# 掉落物就直接停在了最终落点。
	var card: Node2D = SpawnLootRecord(room, record, root)
	if card == null:
		return null
	# 项目里存在遗留的 BoardCardView 视图，动态调用必须先确认目标实现了该方法。
	if card.has_method("PlayScatterFrom"):
		# card.global_position 就是记录换算后的最终落点，无需在这里重做 to_global。
		card.call("PlayScatterFrom", scatter_origin, card.global_position)
	return card


## 在指定位置生成一张掉落卡，并保留原物品堆叠引用。
##
## @param stack 旧 C# 或 GDScript ItemStack。
## @param global_position 掉落卡的目标全局坐标。
## @return 新生成的掉落卡视图；堆叠无效时返回 null。
func SpawnLootCard(stack: RefCounted, global_position: Vector2) -> Node2D:
	if stack == null:
		push_error("BoardController.SpawnLootCard 需要非空的物品堆叠。")
		return null

	var state: RefCounted = _create_loot_state(stack)
	if state == null:
		return null

	return _spawn_card(state, global_position)


## 从同一原点散射生成一组掉落卡，一张卡只承载一件物品。
##
## 掉落表仍按玩法需要返回带数量的堆叠；本入口在登记仓库记录与建卡之前先展开成
## 逐单位堆叠，因此「卡牌张数 = 实际掉落数量」，不再用卡面数字表达数量。
##
## @param stacks 旧 C# 与 GDScript ItemStack 可混合组成的数组。
## @param spawn_origin 散射动画的全局起点，同一批卡牌共用，看起来像从原物一起炸开。
## @return 无返回值。
func SpawnLootCards(stacks: Array, spawn_origin: Vector2) -> void:
	var units: Array[RefCounted] = _expand_loot_units(stacks)
	if units.is_empty():
		return
	if _loot_store != null and _map_view != null:
		var room: Vector2i = _map_view.get("current_position")
		var scene: Node2D = (_map_view.get("active_instances") as Dictionary).get(room) as Node2D
		if scene != null:
			var root: Node2D = scene.get_node_or_null("RoomContentRoot") as Node2D
			if root != null:
				# 仓库记录保存的是房间局部坐标，因此落点也在局部空间里分配。
				var local_origin: Vector2 = root.to_local(spawn_origin)
				var local_targets: Array[Vector2] = _plan_loot_positions(local_origin, units.size(), true)
				for index: int in range(units.size()):
					var record: Dictionary = _loot_store.call("AddLoot", room, units[index], local_targets[index])
					if not record.is_empty():
						SpawnLootRecordWithScatter(room, record, root, spawn_origin)
				return
	# Godot 的 Array 是值类型，跨语言传入 null 会被封送成空数组，因此这里只需遍历。
	# 无仓库时保持独立测试场景的旧生成行为：直接在控制器下建卡。
	var world_targets: Array[Vector2] = _plan_loot_positions(spawn_origin, units.size(), false)
	for index: int in range(units.size()):
		var card: Node2D = SpawnLootCard(units[index], world_targets[index])
		if card != null:
			card.call("PlayScatterFrom", spawn_origin, world_targets[index])


## 移除指定卡牌并撤销其索引、信号与视图。
##
## @param card 目标卡牌视图；为空或已失效时只打印日志。
## @return 无返回值。
func RemoveCard(card: Node2D) -> void:
	print("Removing card: %s" % _card_display_name(card))
	if card == null or not is_instance_valid(card):
		return

	var terrain: RefCounted = card.call("GetTerrainInstanceOrNull") as RefCounted
	if terrain != null:
		_terrain_cards_by_local_grid.erase(_read_local_grid_pos(terrain))
		var room: Vector2i = _room_by_card.get(card, Vector2i.ZERO)
		var room_cards: Dictionary = _terrain_cards_by_room.get(room, {})
		room_cards.erase(_read_local_grid_pos(terrain))
	if card.has_method("GetLootStackOrNull"):
		var id: int = int(card.get("LootId")) if _room_by_card.has(card) else -1
		_loot_cards_by_id.erase(id)
	_room_by_card.erase(card)

	_disconnect_card_signals(card)
	_active_cards.erase(card)

	emit_signal(CARD_REMOVED_SIGNAL, card)
	card.queue_free()
	print("Removed card: %s" % _card_display_name(card))


## 清空棋盘上的全部卡牌与地形索引。
##
## @return 无返回值。
func ClearAllCards() -> void:
	# 先取快照再逐个移除，避免移除过程中修改被遍历的集合。
	var snapshot: Array[Node2D] = []
	for card: Node2D in _active_cards:
		snapshot.append(card)

	for card: Node2D in snapshot:
		RemoveCard(card)
	_terrain_cards_by_local_grid.clear()
	_terrain_cards_by_room.clear()
	_room_by_card.clear()
	_loot_cards_by_id.clear()


## 仅释放退出九宫格的房间卡牌，仓库状态保持不变。
## @param room 要卸载的房间坐标。
## @return 无返回值。
func ReleaseRoomCards(room: Vector2i) -> void:
	for card: Node2D in _active_cards.duplicate():
		if _room_by_card.get(card, null) == room:
			RemoveCard(card)
	_terrain_cards_by_room.erase(room)


## 让已领取物的飞行动画脱离即将卸载的房间。
## @param card 已完成业务结算的掉落卡。
## @return 无返回值。
func DetachForFlight(card: Node2D) -> void:
	if card == null or not is_instance_valid(card):
		return
	_room_by_card.erase(card)
	_loot_cards_by_id.erase(int(card.get("LootId")))
	card.reparent(_cards_root, true)


## 按房间与稳定 ID 获取活动掉落视图。
## @param id 本局掉落 ID。
## @return 对应视图或 null。
func GetLootCardById(id: int) -> Node2D:
	return _loot_cards_by_id.get(id) as Node2D


## 按局部网格坐标查询地形卡。
##
## @param grid_pos 地形卡的局部网格坐标。
## @return 对应地形卡；不存在时返回 null。
func TryGetTerrainCardByLocalGrid(grid_pos: Vector2i) -> Node2D:
	return GetTerrainCardByLocalGridOrNull(grid_pos)


## 按局部网格坐标查询地形卡。
##
## @param grid_pos 地形卡的局部网格坐标。
## @return 对应地形卡；不存在时返回 null。
func GetTerrainCardByLocalGridOrNull(grid_pos: Vector2i) -> Node2D:
	if _map_view != null:
		var room: Vector2i = _map_view.get("current_position")
		return GetTerrainCardInRoom(room, grid_pos)
	return _terrain_cards_by_local_grid.get(grid_pos, null) as Node2D


## 查询指定房间格子的活动地形视图。
## @param room 房间坐标。
## @param grid_pos 局部格子坐标。
## @return 对应视图或 null。
func GetTerrainCardInRoom(room: Vector2i, grid_pos: Vector2i) -> Node2D:
	var room_cards: Dictionary = _terrain_cards_by_room.get(room, {})
	return room_cards.get(grid_pos) as Node2D


## 判断指定局部网格上是否已有地形卡。
##
## @param grid_pos 地形卡的局部网格坐标。
## @return 已存在地形卡时返回 true。
func HasTerrainCardAtLocalGrid(grid_pos: Vector2i) -> bool:
	if _map_view != null:
		return GetTerrainCardByLocalGridOrNull(grid_pos) != null
	return _terrain_cards_by_local_grid.has(grid_pos)


## 获取当前棋盘卡牌快照。
##
## @return 当前仍由棋盘控制器持有的卡牌列表。
func GetActiveCardsSnapshot() -> Array[Node2D]:
	var snapshot: Array[Node2D] = []
	for card: Node2D in _active_cards:
		snapshot.append(card)

	return snapshot


## 把一批掉落堆叠展开成「一张卡牌一件物品」的单位堆叠数组。
##
## 世界掉落卡恒为单件是本系统的硬约束：掉落表按玩法需要返回带数量的堆叠，
## 由这里在登记仓库记录与建卡之前展开，因此一条记录、一张卡天然对应一件物品。
##
## @param stacks 旧 C# 与 GDScript ItemStack 可混合组成的数组。
## @return 数量均为 1 的堆叠数组；不满足堆叠协议的条目被跳过。
func _expand_loot_units(stacks: Array) -> Array[RefCounted]:
	var units: Array[RefCounted] = []
	for value: Variant in stacks:
		# 非泛型数组是跨语言封送边界；这里只接纳两种实现共同继承的 RefCounted。
		var stack: RefCounted = value as RefCounted
		if stack == null or not _is_readable_item_stack(stack):
			continue
		var amount: int = int(stack.get("Amount"))
		if amount <= 1:
			# 掉落表已对装备逐件生成；数量为 1 时原样复用引用，避免无谓的对象拷贝。
			units.append(stack)
			continue
		for _unit_index: int in range(amount):
			units.append(_create_unit_stack(stack))
	return units


## 由带数量的堆叠创建一个只含一件物品的等价堆叠。
##
## 不修改来源堆叠：调用方（例如建筑拆除服务）仍持有原始掉落数组，
## 就地改写 Amount 会让上层看到被掏空的掉落。
##
## @param stack 数量大于 1 的有效来源堆叠。
## @return 数量为 1 的新堆叠；来源缺少复制协议时回退为新建同物品堆叠。
func _create_unit_stack(stack: RefCounted) -> RefCounted:
	# Duplicate 会保留 RolledAttributes，并把「首次属性生成」标记为已完成，
	# 因此后续 RollRandomStats 不会重随机，掉落实例属性与逐件掉落保持一致。
	if stack.has_method("Duplicate"):
		var duplicated: Variant = stack.call("Duplicate")
		if duplicated is RefCounted:
			(duplicated as RefCounted).set("Amount", 1)
			return duplicated as RefCounted
	var fallback: RefCounted = LOOT_STACK_SCRIPT.new() as RefCounted
	if fallback == null:
		return stack
	fallback.call("SetItem", stack.get("Item"), 1)
	var rolled: Variant = stack.get("RolledAttributes")
	if rolled is Dictionary:
		fallback.set("RolledAttributes", (rolled as Dictionary).duplicate(true))
	return fallback


## 为一批掉落卡分配互不重叠的随机落点。
##
## @param origin 散射原点，与返回值使用同一坐标空间。
## @param count 需要分配的落点数量。
## @param use_room_bounds 为 true 时把候选点夹取到房间安全区域内。
## @return 长度为 count 的落点数组；count 小于等于 0 时返回空数组。
func _plan_loot_positions(origin: Vector2, count: int, use_room_bounds: bool) -> Array[Vector2]:
	var positions: Array[Vector2] = []
	if count <= 0:
		return positions
	var minimum_separation: float = maxf(LootMinSeparation, 0.0)
	var outer_radius: float = _resolve_scatter_outer_radius(count, minimum_separation)
	for _index: int in range(count):
		var candidate: Vector2 = origin
		for _attempt: int in range(SCATTER_PLACEMENT_ATTEMPTS):
			candidate = origin + _random_direction() * _rng.randf_range(ScatterRadiusMin, outer_radius)
			if use_room_bounds:
				candidate = Vector2(
					clampf(candidate.x, LOOT_AREA_MIN.x, LOOT_AREA_MAX.x),
					clampf(candidate.y, LOOT_AREA_MIN.y, LOOT_AREA_MAX.y)
				)
			# 必须夹取之后再判间距：贴边候选会被压到同一条边界线上，
			# 只有夹完才能看出两张卡是否真的落在了同一个点。
			if _far_enough_from_all(candidate, positions, minimum_separation):
				break
		# 重试用尽就接受当前候选。原点贴近房间角落时环带彼此重叠，硬性间距无法满足，
		# 这里保底让每件掉落都拿到落点，而不是把它们全堆在原点或直接丢弃。
		positions.append(candidate)
	return positions


## 按张数推算散射外半径，保证环带面积容得下全部落点。
##
## 环带面积 π(Rmax² − Rmin²) 至少要容纳 count 个直径 d 的圆盘；六边形最密排布下
## 每个圆心占 0.866·d²。代入默认最小间距 56 后，1~7 张仍等于 ScatterRadiusMax(90)，
## 只有 8 张起才放大（8 张 92.3、12 张 109.4），因此普通掉落散射手感与改动前一致。
##
## @param count 落点数量。
## @param minimum_separation 最小圆心距，也就是圆盘直径 d。
## @return 本次实际使用的散射外半径。
func _resolve_scatter_outer_radius(count: int, minimum_separation: float) -> float:
	if count <= 1 or minimum_separation <= 0.0:
		return ScatterRadiusMax
	var required_area: float = float(count) * CIRCLE_PACKING_AREA_FACTOR * minimum_separation * minimum_separation
	var required_outer: float = sqrt(ScatterRadiusMin * ScatterRadiusMin + required_area / PI)
	return maxf(ScatterRadiusMax, required_outer)


## 判断候选落点与已接受落点的距离是否都不小于最小间距。
##
## @param candidate 待判定的落点。
## @param accepted 已经接受的落点数组。
## @param minimum_separation 最小圆心距。
## @return 与全部已接受落点都足够远时返回 true。
func _far_enough_from_all(candidate: Vector2, accepted: Array[Vector2], minimum_separation: float) -> bool:
	if minimum_separation <= 0.0:
		return true
	for accepted_position: Vector2 in accepted:
		# 用平方距离比较，避免每个候选点都做一次开方。
		if candidate.distance_squared_to(accepted_position) < minimum_separation * minimum_separation:
			return false
	return true


## 实例化视图并按状态初始化，随后连接信号并广播生成事件。
##
## @param state 旧 C# 或 GDScript 棋盘卡状态。
## @param global_position 卡牌的目标全局坐标。
## @return 新生成的卡牌视图；状态未知时返回 null。
func _spawn_card(state: RefCounted, global_position: Vector2, parent_root: Node2D = null) -> Node2D:
	if state == null:
		return null

	var is_terrain: bool = bool(state.call("IsTerrain"))
	var is_loot: bool = bool(state.call("IsLoot"))
	var view_scene: PackedScene = TerrainViewScene if is_terrain else LootViewScene if is_loot else null
	if view_scene == null:
		push_error("未知棋盘卡状态，无法选择视图预制体。")
		return null

	var card: Node2D = view_scene.instantiate() as Node2D
	if card == null:
		push_error("BoardController 选择的卡牌视图预制体不是 Node2D。")
		return null

	var cards_root: Node2D = parent_root if parent_root != null else (_cards_root if _cards_root != null else self)
	cards_root.add_child(card)

	card.global_position = global_position
	if is_terrain:
		card.call("InitializeTerrain", state.call("GetTerrainInstanceOrNull"))
	elif is_loot:
		card.call("InitializeLoot", state.call("GetLootStackOrNull"))

	_connect_card_signals(card)
	_active_cards.append(card)

	emit_signal(CARD_SPAWNED_SIGNAL, card)
	return card


## 创建并初始化地形卡状态。
##
## @param terrain_instance 地形运行时实例。
## @return 初始化成功的状态；TerrainData 为空时返回 null。
func _create_terrain_state(terrain_instance: RefCounted) -> RefCounted:
	var state: RefCounted = _create_state()
	if state == null:
		return null
	if not bool(state.call("InitializeTerrain", terrain_instance)):
		push_error("TerrainInstance.TerrainData 不能为空。")
		return null

	return state


## 创建并初始化掉落卡状态。
##
## @param stack 旧 C# 或 GDScript ItemStack。
## @return 初始化成功的状态；堆叠协议不完整时返回 null。
func _create_loot_state(stack: RefCounted) -> RefCounted:
	var state: RefCounted = _create_state()
	if state == null:
		return null
	if not bool(state.call("InitializeLoot", stack)):
		push_error("LootStack 必须提供非空 Item、正 Amount 与 IsEmpty 属性。")
		return null

	return state


## 实例化棋盘卡状态对象。
##
## @return 新的状态实例；脚本缺失时返回 null。
func _create_state() -> RefCounted:
	if BOARD_CARD_STATE_SCRIPT == null:
		push_error("无法加载棋盘卡状态脚本：res://core/board/board_card_state.gd")
		return null

	return BOARD_CARD_STATE_SCRIPT.new() as RefCounted


## 连接卡牌视图的交互信号，回调统一转发为本控制器的信号。
##
## @param card 卡牌视图。
## @return 无返回值。
func _connect_card_signals(card: Node2D) -> void:
	card.connect(VIEW_CLICKED_SIGNAL, _on_card_clicked)
	card.connect(VIEW_PRESSED_SIGNAL, _on_card_pressed)
	card.connect(VIEW_RELEASED_SIGNAL, _on_card_released)
	card.connect(VIEW_HOVER_STARTED_SIGNAL, _on_card_hover_started)
	card.connect(VIEW_HOVER_ENDED_SIGNAL, _on_card_hover_ended)


## 断开卡牌视图的交互信号，避免卡牌释放后残留回调。
##
## @param card 卡牌视图。
## @return 无返回值。
func _disconnect_card_signals(card: Node2D) -> void:
	_disconnect_card_signal(card, VIEW_CLICKED_SIGNAL, _on_card_clicked)
	_disconnect_card_signal(card, VIEW_PRESSED_SIGNAL, _on_card_pressed)
	_disconnect_card_signal(card, VIEW_RELEASED_SIGNAL, _on_card_released)
	_disconnect_card_signal(card, VIEW_HOVER_STARTED_SIGNAL, _on_card_hover_started)
	_disconnect_card_signal(card, VIEW_HOVER_ENDED_SIGNAL, _on_card_hover_ended)


## 单击回调：打印卡名并转发 CardClicked 信号。
##
## @param card 触发单击的卡牌视图。
## @return 无返回值。
func _on_card_clicked(card: Node2D) -> void:
	print("Card clicked: %s" % _card_display_name(card))
	emit_signal(CARD_CLICKED_SIGNAL, card)


## 按下回调：转发 CardPressed 信号。
##
## @param card 触发按下的卡牌视图。
## @return 无返回值。
func _on_card_pressed(card: Node2D) -> void:
	emit_signal(CARD_PRESSED_SIGNAL, card)


## 松开回调：转发 CardReleased 信号。
##
## @param card 触发松开的卡牌视图。
## @return 无返回值。
func _on_card_released(card: Node2D) -> void:
	emit_signal(CARD_RELEASED_SIGNAL, card)


## 悬停开始回调：转发 CardHoverStarted 信号。
##
## @param card 触发悬停开始的卡牌视图。
## @return 无返回值。
func _on_card_hover_started(card: Node2D) -> void:
	emit_signal(CARD_HOVER_STARTED_SIGNAL, card)


## 悬停结束回调：转发 CardHoverEnded 信号。
##
## @param card 触发悬停结束的卡牌视图。
## @return 无返回值。
func _on_card_hover_ended(card: Node2D) -> void:
	emit_signal(CARD_HOVER_ENDED_SIGNAL, card)


## 生成一个单位长度的随机方向向量。
##
## @return 随机方向单位向量。
func _random_direction() -> Vector2:
	var angle: float = _rng.randf_range(0.0, TAU)
	return Vector2(cos(angle), sin(angle))


## 精确断开卡牌视图上的指定信号连接。
##
## @param card 卡牌视图。
## @param signal_name 视图信号名。
## @param callback 连接时使用的回调。
## @return 无返回值。
func _disconnect_card_signal(card: Node2D, signal_name: StringName, callback: Callable) -> void:
	if card.is_connected(signal_name, callback):
		card.disconnect(signal_name, callback)


## 读取卡牌显示名。
##
## @param card 卡牌视图；允许为空或已释放。
## @return 卡牌显示名；不可读取时返回空字符串。
func _card_display_name(card: Node2D) -> String:
	if card == null or not is_instance_valid(card):
		return ""
	return String(card.call("GetCardDisplayName"))


## 读取地形实例的局部网格坐标，等价旧 C# TerrainInstanceProtocol.TryReadLocalGridPos。
##
## @param terrain 旧 C# 或 GDScript 地形实例；允许为空。
## @return 局部网格坐标；字段缺失或类型不符时返回 Vector2i.ZERO。
func _read_local_grid_pos(terrain: RefCounted) -> Vector2i:
	if terrain == null:
		return Vector2i.ZERO

	var value: Variant = terrain.get("LocalGridPos")
	if typeof(value) != TYPE_VECTOR2I:
		return Vector2i.ZERO

	return Vector2i(value)


## 判断物品堆叠是否满足跨语言协议，等价旧 C# ItemStackProtocol.TryRead。
##
## @param stack 旧 C# 或 GDScript 物品堆叠。
## @return 声明完整协议、物品非空且数量为正时返回 true。
func _is_readable_item_stack(stack: RefCounted) -> bool:
	if stack == null or not is_instance_valid(stack):
		return false
	if not stack.has_method("SetItem") or not stack.has_method("Clear"):
		return false

	var item: Variant = stack.get("Item")
	var amount: int = int(stack.get("Amount"))
	var is_empty: bool = bool(stack.get("IsEmpty"))
	return not is_empty and item != null and amount > 0
