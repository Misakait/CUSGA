extends Node2D

## 棋盘卡牌控制器的 GDScript 生产实现，等价迁移自 core/board/BoardController.cs。
##
## 控制器只负责卡牌视图生命周期：创建地形/掉落卡状态、挂到 CardsRoot、连接并转发视图信号，
## 以及按局部网格维护地形卡索引。卡状态由 board_card_state.gd 承载、视图由 BoardCardView.tscn 承载，
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

## 卡牌视图预制体。
@export var CardViewScene: PackedScene = null
## 卡牌父节点路径；留空时直接挂到控制器自身。
@export var CardsRootPath: NodePath = NodePath("")
## 掉落散射的最小半径。
@export var ScatterRadiusMin: float = 40.0
## 掉落散射的最大半径。
@export var ScatterRadiusMax: float = 90.0

## 卡牌视图父节点。
var _cards_root: Node2D = null
## 掉落散射使用的随机源，语义等价旧 C# RandomNumberGenerator。
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
## 当前仍在棋盘上的卡牌；用数组保存以保持稳定顺序，集合语义等价旧 C# HashSet。
var _active_cards: Array[Node2D] = []
## 局部网格坐标到地形卡的索引。
var _terrain_cards_by_local_grid: Dictionary = {}


## 进入场景树时校验视图预制体并解析卡牌根节点。
##
## @return 无返回值。
func _ready() -> void:
	if CardViewScene == null:
		# 旧 C# 在缺预制体时抛异常；GDScript 侧以同文本的硬错误表达同一契约。
		push_error("BoardController.CardViewScene 未设置。")
		return

	_cards_root = self if CardsRootPath.is_empty() else get_node(CardsRootPath) as Node2D


## 退出场景树时断开全部卡牌信号并清空索引，避免跨场景残留回调。
##
## @return 无返回值。
func _exit_tree() -> void:
	for card: Node2D in _active_cards:
		if is_instance_valid(card):
			_disconnect_card_signals(card)

	_active_cards.clear()
	_terrain_cards_by_local_grid.clear()


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


## 从同一原点散射生成一组跨语言物品堆叠对应的掉落卡。
##
## @param stacks 旧 C# 与 GDScript ItemStack 可混合组成的数组。
## @param spawn_origin 散射动画的全局起点。
## @return 无返回值。
func SpawnLootCards(stacks: Array, spawn_origin: Vector2) -> void:
	# Godot 的 Array 是值类型，跨语言传入 null 会被封送成空数组，因此这里只需遍历。
	for value: Variant in stacks:
		# 非泛型数组是跨语言封送边界；这里只接纳两种实现共同继承的 RefCounted。
		var stack: RefCounted = value as RefCounted
		if stack != null and _is_readable_item_stack(stack):
			_spawn_single_loot_with_scatter(stack, spawn_origin)


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
	return _terrain_cards_by_local_grid.get(grid_pos, null) as Node2D


## 判断指定局部网格上是否已有地形卡。
##
## @param grid_pos 地形卡的局部网格坐标。
## @return 已存在地形卡时返回 true。
func HasTerrainCardAtLocalGrid(grid_pos: Vector2i) -> bool:
	return _terrain_cards_by_local_grid.has(grid_pos)


## 获取当前棋盘卡牌快照。
##
## @return 当前仍由棋盘控制器持有的卡牌列表。
func GetActiveCardsSnapshot() -> Array[Node2D]:
	var snapshot: Array[Node2D] = []
	for card: Node2D in _active_cards:
		snapshot.append(card)

	return snapshot


## 生成一张掉落卡并播放从原点到落点的散射动画。
##
## @param stack 掉落卡持有的物品堆叠。
## @param spawn_origin 散射动画的全局起点。
## @return 无返回值。
func _spawn_single_loot_with_scatter(stack: RefCounted, spawn_origin: Vector2) -> void:
	var target: Vector2 = (
		spawn_origin + _random_direction() * _rng.randf_range(ScatterRadiusMin, ScatterRadiusMax)
	)

	var card: Node2D = SpawnLootCard(stack, target)
	if card == null:
		return
	card.call("PlayScatterFrom", spawn_origin, target)


## 实例化视图并按状态初始化，随后连接信号并广播生成事件。
##
## @param state 旧 C# 或 GDScript 棋盘卡状态。
## @param global_position 卡牌的目标全局坐标。
## @return 新生成的卡牌视图；状态未知时返回 null。
func _spawn_card(state: RefCounted, global_position: Vector2) -> Node2D:
	if state == null or CardViewScene == null:
		return null

	var card: Node2D = CardViewScene.instantiate() as Node2D
	if card == null:
		push_error("BoardController.CardViewScene 不是 Node2D。")
		return null

	var cards_root: Node2D = _cards_root if _cards_root != null else self
	cards_root.add_child(card)

	card.global_position = global_position
	if bool(state.call("IsTerrain")):
		card.call("InitializeTerrain", state.call("GetTerrainInstanceOrNull"))
	elif bool(state.call("IsLoot")):
		card.call("InitializeLoot", state.call("GetLootStackOrNull"))
	else:
		push_error("未知棋盘卡状态，无法初始化视图。")
		card.queue_free()
		return null

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
