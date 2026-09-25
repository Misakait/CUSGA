extends Node

## 房间棋盘表现层 GDScript 生产实现，等价迁移自 core/map/RoomBoardPresenter.cs。
##
## 职责：监听地图系统的进入房间信号 → 清空上一房间的棋盘卡牌 → 首次进入的房间按场景地形布局
## Profile 生成初始布局 → 逐个地形刷新可重复采集状态 → 按跨语言字段协议读取显示位置并生成棋盘卡。
## 不声明 class_name，避免与仍在使用的 C# 全局类型重名。

## 地图系统进入房间信号名，与 map_control.gd / map_instantiator.gd 的声明一致。
const ON_ENTERED_ROOM_SIGNAL: StringName = &"on_entered_room"
## 已迁移的 GDScript 房间地形布局生成器脚本路径。
const LAYOUT_GENERATOR_SCRIPT_PATH: String = "res://core/map/room_terrain_layout_generator.gd"
## 时间 Autoload 的固定挂载路径。
const TIME_SYSTEM_PATH: NodePath = ^"/root/TimeSystem"

## 地图系统节点路径。
@export var MapSystemPath: NodePath = NodePath("")
## 棋盘控制器节点路径。
@export var BoardControllerPath: NodePath = NodePath("")
## 地形仓库节点路径。
@export var TerrainStorePath: NodePath = NodePath("")
## 九宫格地图视图，按完整房间的激活与退出管理内容。
@export var MapViewPath: NodePath = NodePath("")
## 掉落状态仓库；未配置时保持旧测试场景的地形功能。
@export var LootStorePath: NodePath = NodePath("")
## 是否隐藏已采集完成的地形。
@export var HideHarvestedTerrain: bool = true

## 地图系统节点。
var _map_system: Node = null
## 时间 Autoload；通过属性协议读取，兼容 C# 与 GDScript 实现。
var _time_system: Node = null
## 棋盘控制器；只保留 Node 与方法协议，兼容 C# 垫片与生产实现。
var _board_controller: Node = null
## 地形仓库；只保留 Node 与方法协议。
var _terrain_store: Node = null
## 房间地形布局生成器；旧 C# 只持有 RefCounted 引用并按 Generate 协议取值。
var _layout_generator: RefCounted = null
var _map_view: Node = null
var _loot_store: Node = null


## 进入场景树时校验导出路径、解析节点并连接进入房间信号。
##
## @return 无返回值。
func _ready() -> void:
	if MapSystemPath.is_empty():
		# 旧 C# 在缺少导出路径时抛异常；GDScript 侧以同文本的硬错误表达同一契约。
		push_error("RoomBoardPresenter.MapSystemPath 未设置。")
		return

	if BoardControllerPath.is_empty():
		push_error("RoomBoardPresenter.BoardControllerPath 未设置。")
		return

	if TerrainStorePath.is_empty():
		push_error("RoomBoardPresenter.TerrainStorePath 未设置。")
		return

	_map_system = get_node(MapSystemPath)
	_time_system = get_node_or_null(TIME_SYSTEM_PATH)
	_board_controller = get_node(BoardControllerPath)
	_terrain_store = get_node(TerrainStorePath)
	_map_view = get_node_or_null(MapViewPath) if not MapViewPath.is_empty() else null
	_loot_store = get_node_or_null(LootStorePath) if not LootStorePath.is_empty() else null
	_layout_generator = _create_layout_generator()
	if _layout_generator == null:
		return

	if not _map_system.has_signal(ON_ENTERED_ROOM_SIGNAL):
		push_error(
			"MapSystem 缺少信号 '%s'。请在 MapSystem 根节点脚本中声明并转发该信号。"
			% str(ON_ENTERED_ROOM_SIGNAL)
		)
		return

	if not _map_system.is_connected(ON_ENTERED_ROOM_SIGNAL, _on_room_entered):
		_map_system.connect(ON_ENTERED_ROOM_SIGNAL, _on_room_entered)
	if _map_view != null:
		_map_view.connect("room_activated", _on_room_activated)
		_map_view.connect("room_deactivating", _on_room_deactivating)
		# 视图可能已经完成初始窗口；补偿读取使场景顺序不影响内容。
		for room_value: Variant in (_map_view.get("active_instances") as Dictionary).keys():
			var room: Vector2i = room_value
			_on_room_activated(room, (_map_view.get("active_instances") as Dictionary)[room] as Node2D)
	if _loot_store != null:
		_loot_store.connect("LootAdded", _on_loot_added)
		_loot_store.connect("LootRemoved", _on_loot_removed)


## 退出场景树时断开进入房间信号，避免跨场景残留回调。
##
## @return 无返回值。
func _exit_tree() -> void:
	if _map_system == null or not is_instance_valid(_map_system):
		return
	if _map_system.is_connected(ON_ENTERED_ROOM_SIGNAL, _on_room_entered):
		_map_system.disconnect(ON_ENTERED_ROOM_SIGNAL, _on_room_entered)
	if _map_view != null and is_instance_valid(_map_view):
		if _map_view.is_connected("room_activated", _on_room_activated):
			_map_view.disconnect("room_activated", _on_room_activated)
		if _map_view.is_connected("room_deactivating", _on_room_deactivating):
			_map_view.disconnect("room_deactivating", _on_room_deactivating)
	if _loot_store != null and is_instance_valid(_loot_store):
		if _loot_store.is_connected("LootAdded", _on_loot_added):
			_loot_store.disconnect("LootAdded", _on_loot_added)
		if _loot_store.is_connected("LootRemoved", _on_loot_removed):
			_loot_store.disconnect("LootRemoved", _on_loot_removed)


## 进入房间：清空旧卡牌、必要时创建初始布局，再逐块地形刷新并生成棋盘卡。
##
## @param room_pos 房间在地图上的坐标。
## @param room_scene 房间场景根节点；可能携带 terrain_profile。
## @return 无返回值。
func _on_room_entered(room_pos: Vector2i, room_scene: Node2D) -> void:
	if room_scene == null or not is_instance_valid(room_scene):
		return
	if _map_view != null:
		# 当前房间变化不重建邻房；首次激活信号已经在此之前完成内容装配。
		return
	_board_controller.call("ClearAllCards")
	_on_room_activated(room_pos, room_scene)


## 首次进入活动窗口时建立房间内容根节点，再从仓库恢复地形与掉落。
## @param room_pos 房间坐标。
## @param room_scene 完整房间场景。
## @return 无返回值。
func _on_room_activated(room_pos: Vector2i, room_scene: Node2D) -> void:
	if room_scene == null or not is_instance_valid(room_scene):
		return
	var root: Node2D = room_scene.get_node_or_null("RoomContentRoot") as Node2D
	if root != null:
		return
	root = Node2D.new()
	root.name = "RoomContentRoot"
	room_scene.add_child(root)
	print("[RoomBoardPresenter] Enter room %s, scene=%s" % [str(room_pos), str(room_scene.name)])

	if not bool(_terrain_store.call("HasRoom", room_pos)):
		_create_initial_room_layout(room_pos, room_scene)

	var room_terrains_value: Variant = _terrain_store.call("GetRoomTerrainsOrEmpty", room_pos)
	if typeof(room_terrains_value) != TYPE_DICTIONARY:
		return

	# GDScript 仓库返回的字典保持插入顺序，与旧 C# Dictionary 的遍历顺序一致，
	# 因此地形卡的生成顺序不会因为迁移而改变。
	var room_terrains: Dictionary = room_terrains_value
	for terrain_value: Variant in room_terrains.values():
		# 非泛型容器是跨语言封送边界；这里只接纳两种实现共同继承的 RefCounted。
		var terrain: RefCounted = terrain_value as RefCounted
		if terrain == null:
			continue

		# 地形实例已迁移到 GDScript，配置与采集状态统一经跨语言字段协议读取。
		var terrain_data: Resource = _read_terrain_data(terrain)
		if terrain_data == null:
			continue

		var interaction: Resource = _read_interaction(terrain_data)
		var total_time_passed: int = _read_total_time()
		if interaction != null and interaction.has_method("RefreshIfReady"):
			# 旧 C# 可重复采集交互仍按原方法名接收刷新请求。
			interaction.call("RefreshIfReady", terrain, total_time_passed)
		elif interaction != null and interaction.has_method("refresh_if_ready"):
			interaction.call("refresh_if_ready", terrain, total_time_passed)

		if HideHarvestedTerrain and _read_harvested(terrain):
			continue

		# 棋盘显示位置直接决定卡牌落点；缺失时退回原点，保持旧实现的零值语义。
		if _map_view != null:
			_board_controller.call("SpawnTerrainCardForRoom", room_pos, terrain, _read_board_position(terrain), root)
		else:
			_board_controller.call("SpawnTerrainCard", terrain, _read_board_position(terrain))
	if _loot_store != null:
		for record: Dictionary in _loot_store.call("GetLoot", room_pos):
			_board_controller.call("SpawnLootRecord", room_pos, record, root)


## 房间退出活动窗口时清理输入和视图，仓库状态不变。
## @param room_pos 房间坐标。
## @param _room_scene 即将释放的房间场景。
## @return 无返回值。
func _on_room_deactivating(room_pos: Vector2i, _room_scene: Node2D) -> void:
	_board_controller.call("ReleaseRoomCards", room_pos)


## 新掉落已由仓库登记后，在活动房间补出视图。
## @param room_pos 所属房间。
## @param record 仓库记录。
## @return 无返回值。
func _on_loot_added(room_pos: Vector2i, record: Dictionary) -> void:
	if _map_view == null:
		return
	var scene: Node2D = (_map_view.get("active_instances") as Dictionary).get(room_pos) as Node2D
	if scene == null:
		return
	var root: Node2D = scene.get_node_or_null("RoomContentRoot") as Node2D
	if root != null:
		_board_controller.call("SpawnLootRecord", room_pos, record, root)


## 掉落领取后，视图的关闭与飞行动画由交互协调器处理。
## @param _room_pos 所属房间。
## @param _id 本局掉落 ID。
## @return 无返回值。
func _on_loot_removed(_room_pos: Vector2i, _id: int) -> void:
	pass


## 读取时间系统累计时间；缺失或类型不符时返回 0。
##
## @return 累计时间或 0。
func _read_total_time() -> int:
	if _time_system == null or not is_instance_valid(_time_system):
		return 0

	var value: Variant = _time_system.get("TotalTimePassed")
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		return int(value)

	return 0


## 为首次进入的房间创建初始地形布局。
##
## @param room_pos 房间坐标。
## @param room_scene 房间场景根节点。
## @return 无返回值。
func _create_initial_room_layout(room_pos: Vector2i, room_scene: Node2D) -> void:
	var profile_value: Variant = room_scene.get("terrain_profile")
	if not (profile_value is Resource):
		_terrain_store.call("CreateRoomLayout", room_pos, [])
		return

	var profile: Resource = profile_value
	_terrain_store.call("CreateRoomLayout", room_pos, _layout_generator.call("Generate", profile))


## 加载并实例化 GDScript 房间地形布局生成器。
##
## @return 已实例化的布局生成器；脚本缺失时返回 null。
func _create_layout_generator() -> RefCounted:
	var script: GDScript = load(LAYOUT_GENERATOR_SCRIPT_PATH) as GDScript
	if script == null:
		push_error("缺少地形布局生成器脚本：%s" % LAYOUT_GENERATOR_SCRIPT_PATH)
		return null

	return script.new() as RefCounted


## 读取地形配置资源，等价旧 C# TerrainInstanceProtocol.ReadTerrainData。
##
## @param terrain 地形实例；允许为空。
## @return 地形配置资源；缺失或类型不符时返回 null。
func _read_terrain_data(terrain: RefCounted) -> Resource:
	if terrain == null:
		return null

	var value: Variant = terrain.get("TerrainData")
	if value is Resource:
		return value

	return null


## 读取地形交互行为资源。
##
## @param terrain_data 地形配置资源。
## @return 交互行为资源；缺失或类型不符时返回 null。
func _read_interaction(terrain_data: Resource) -> Resource:
	var value: Variant = terrain_data.get("InteractionBehavior")
	if value is Resource:
		return value

	return null


## 读取采集完成状态，等价旧 C# TerrainInstanceProtocol.TryReadBool(..., "IsHarvested", ...)。
##
## @param terrain 地形实例。
## @return 已采集完成返回 true；字段缺失或类型不符返回 false。
func _read_harvested(terrain: RefCounted) -> bool:
	if terrain == null:
		return false

	var value: Variant = terrain.get("IsHarvested")
	if typeof(value) == TYPE_BOOL:
		return bool(value)

	return false


## 读取棋盘显示位置，等价旧 C# TerrainInstanceProtocol.TryReadBoardPosition。
##
## @param terrain 地形实例。
## @return 棋盘显示位置；字段缺失或类型不符时返回零向量。
func _read_board_position(terrain: RefCounted) -> Vector2:
	if terrain == null:
		return Vector2.ZERO

	var value: Variant = terrain.get("BoardPosition")
	if typeof(value) == TYPE_VECTOR2:
		return Vector2(value)

	return Vector2.ZERO
