extends Node

## 局内世界快照参与者。
##
## 快照只保存稳定的字符串、数字、数组和字典，不保存 Node、PackedScene 或运行时 Resource
## 引用。恢复顺序由 Main 的节点顺序保证：先给地图生成器布局，再由开局初始化恢复玩家，
## 最后在所有房间节点就绪后恢复仓库内容。

const SAVE_KEY: String = "run_world"
const SAVE_SCOPE: String = "run"
const ITEM_STACK_SCRIPT: GDScript = preload("res://resources/item/item_stack.gd")
const SAVE_MANAGER_PATH: NodePath = ^"/root/SaveManager"

@export var MapModelPath: NodePath = ^"../../MapSystem/MapWorldModel"
@export var MapGeneratorPath: NodePath = ^"../../MapSystem/MapPositionCreate"
@export var TerrainStorePath: NodePath = ^"../RoomTerrainStore"
@export var LootStorePath: NodePath = ^"../RoomLootStore"
@export var BuildingStorePath: NodePath = ^"../RoomBuildingStore"
@export var PlayerCharPath: NodePath = ^"../../PlayerChar"
@export var PlayerPath: NodePath = ^"../../Player"

var _pending: Dictionary = {}
var _has_pending: bool = false
var _restored_player: bool = false
var _restored_world: bool = false


## 注册参与者并读取已经由 SaveManager 分发的局内 payload。
## @return 无返回值。
func _ready() -> void:
	var save_manager: Node = get_node_or_null(SAVE_MANAGER_PATH)
	if save_manager == null or not save_manager.has_method("register_participant"):
		push_error("RunSnapshot: 未找到 SaveManager，局内快照不会保存。")
		return
	save_manager.call("register_participant", self)
	var loaded: Dictionary = save_manager.call("get_loaded_run_data", SAVE_KEY)
	_pending = loaded.duplicate(true)
	_has_pending = not _pending.is_empty()
	# RuntimeState 排在地图和内容 View 之前，因此这里恢复仓库能让首次 3×3
	# 激活直接读取旧布局，不会先随机生成一份再被快照覆盖。
	_restore_runtime_state()


## 返回稳定参与者键。
## @return `run_world`。
func save_key() -> String:
	return SAVE_KEY


## 返回局内作用域。
## @return `run`。
func save_scope() -> String:
	return SAVE_SCOPE


## 快照不依赖单独变更信号，由各个已有参与者的保存请求覆盖它。
## @return 空信号数组。
func save_change_signals() -> Array:
	return []


## 采集地图、房间仓库、时间、玩家位置和背包。
## @return 可直接写入 JSON 的纯字典。
func capture_save_data() -> Dictionary:
	var map_model: Node = get_node_or_null(MapModelPath)
	var player_char: Node2D = get_node_or_null(PlayerCharPath) as Node2D
	var time_system: Node = get_node_or_null("/root/TimeSystem")
	var payload: Dictionary = {
		"map": [], "connections": {}, "start": _encode_vec2i(Vector2i.ZERO),
		"current": _encode_vec2i(Vector2i.ZERO), "player_position": [0.0, 0.0],
		"time": 0, "day": 1, "night": false,
		"terrain": {}, "loot": {}, "buildings": {}, "building_next_id": 1,
		"inventory": [],
	}
	if map_model != null:
		payload["map"] = (map_model.get("map") as Array).duplicate(true)
		payload["connections"] = _encode_connections(map_model.get("scene_to_scene"))
		payload["start"] = _encode_vec2i(map_model.get("start_position"))
		payload["current"] = _encode_vec2i(map_model.get("current_position"))
	if player_char != null:
		payload["player_position"] = [player_char.global_position.x, player_char.global_position.y]
	if time_system != null:
		payload["time"] = int(time_system.get("TotalTimePassed"))
		payload["day"] = int(time_system.get("CurrentDay"))
		payload["night"] = bool(time_system.get("IsNight"))
	payload["terrain"] = _encode_terrain_store()
	payload["loot"] = _encode_loot_store()
	var building_data: Dictionary = _encode_building_store()
	payload["buildings"] = building_data.get("rooms", {})
	payload["building_next_id"] = int(building_data.get("next_id", 1))
	payload["inventory"] = _encode_inventory()
	return payload


## 接收 SaveManager 的数据；空字典表示新局。
## @param data 已校验的局内 payload。
## @return 始终返回 true，字段缺失按默认值处理。
func apply_save_data(data: Dictionary) -> bool:
	_pending = data.duplicate(true)
	_has_pending = not _pending.is_empty()
	return true


## 判断是否存在待恢复的局内快照。
## @return 当前模式允许且 payload 非空时返回 true。
func HasPendingRun() -> bool:
	return _has_pending


## 把快照中的地图数组和连接表应用到生成器，阻止启动时重新随机地图。
## @param generator 地图生成器节点。
## @return 成功应用布局时为 true。
func ApplyMapToGenerator(generator: Node) -> bool:
	if not _has_pending or generator == null or not _pending.has("map"):
		return false
	var map_data: Variant = _pending.get("map")
	if not (map_data is Array) or (map_data as Array).is_empty():
		return false
	generator.set("map", (map_data as Array).duplicate(true))
	generator.set("scene_to_scene", _decode_connections(_pending.get("connections", {})))
	generator.set("start_position", _decode_vec2i(_pending.get("start", "0,0")))
	return true


## 读取快照中的当前房间；地图尚未恢复时返回 null。
## @return 当前房间坐标或 null。
func GetCurrentRoomOrNull() -> Variant:
	if not _has_pending:
		return null
	return _decode_vec2i(_pending.get("current", "0,0"))


## 在 RunStartInitializer 阶段恢复玩家位置与背包，避免新局带入逻辑覆盖存档。
## @param player 数值玩家节点。
## @param inventory 玩家背包组件。
## @param player_char 世界移动角色。
## @return 恢复成功时为 true。
func RestorePlayer(player: Node, inventory: Node, player_char: Node2D) -> bool:
	if not _has_pending:
		return false
	if player_char != null and _pending.get("player_position") is Array:
		var position: Array = _pending.get("player_position")
		if position.size() >= 2:
			player_char.global_position = Vector2(float(position[0]), float(position[1]))
	_restore_inventory(inventory)
	_restored_player = true
	return true


## 完成所有节点 ready 后恢复时间、房间仓库和建筑仓库。
## @return 无返回值。
func _restore_runtime_state() -> void:
	if not _has_pending or _restored_world:
		return
	var terrain_store: Node = get_node_or_null(TerrainStorePath)
	var loot_store: Node = get_node_or_null(LootStorePath)
	var building_store: Node = get_node_or_null(BuildingStorePath)
	if terrain_store == null or loot_store == null or building_store == null:
		call_deferred("_restore_runtime_state")
		return
	_restore_time()
	_restore_terrain_store(terrain_store)
	_restore_loot_store(loot_store)
	_restore_building_store(building_store)
	_restored_world = true


func _encode_vec2i(value: Vector2i) -> String:
	return "%d,%d" % [value.x, value.y]


func _decode_vec2i(value: Variant) -> Vector2i:
	var parts: PackedStringArray = str(value).split(",")
	return Vector2i(int(parts[0]), int(parts[1])) if parts.size() >= 2 else Vector2i.ZERO


func _encode_connections(source: Variant) -> Dictionary:
	var output: Dictionary = {}
	if not source is Dictionary:
		return output
	for key: Variant in source:
		var values: Array = source[key] as Array
		output[_encode_vec2i(key)] = values.duplicate()
	return output


func _decode_connections(source: Variant) -> Dictionary:
	var output: Dictionary = {}
	if not source is Dictionary:
		return output
	for key: Variant in source:
		output[_decode_vec2i(key)] = (source[key] as Array).duplicate()
	return output


func _encode_terrain_store() -> Dictionary:
	var store: Node = get_node_or_null(TerrainStorePath)
	var output: Dictionary = {}
	if store == null:
		return output
	var rooms: Dictionary = store.call("Snapshot")
	for room_key: Variant in rooms:
		var room_data: Dictionary = {}
		for cell_key: Variant in (rooms[room_key] as Dictionary):
			var terrain: RefCounted = rooms[room_key][cell_key] as RefCounted
			if terrain == null:
				continue
			var data: Resource = terrain.get("TerrainData") as Resource
			room_data[_encode_vec2i(cell_key)] = {
				"data_path": data.resource_path if data != null else "",
				"card_id": String(data.get("CardId")) if data != null else "",
				"position": [terrain.get("BoardPosition").x, terrain.get("BoardPosition").y],
				"harvested": bool(terrain.get("IsHarvested")), "occupied": bool(terrain.get("IsOccupied")),
				"growth": int(terrain.get("GrowthStage")), "remaining": int(terrain.get("RemainingGatheringCount")),
				"refresh": int(terrain.get("RefreshReadyTotalTime")),
				"variance": terrain.call("GetEncounterVarianceSnapshot"),
			}
		output[_encode_vec2i(room_key)] = room_data
	return output


func _encode_loot_store() -> Dictionary:
	var store: Node = get_node_or_null(LootStorePath)
	return store.call("SnapshotEncoded") if store != null and store.has_method("SnapshotEncoded") else {}


func _encode_building_store() -> Dictionary:
	var store: Node = get_node_or_null(BuildingStorePath)
	if store == null or not store.has_method("Snapshot"):
		return {"rooms": {}, "next_id": 1}
	var snapshot: Dictionary = store.call("Snapshot")
	var rooms: Dictionary = {}
	for room_key: Variant in snapshot.get("rooms", {}):
		var records: Array = []
		for record: Dictionary in snapshot["rooms"][room_key]:
			var data: Resource = record.get("data") as Resource
			records.append({"id": int(record.get("id", -1)), "data_path": data.resource_path if data != null else "", "card_id": String(data.get("CardId")) if data != null else "", "position": [record["position"].x, record["position"].y], "state": record.get("state", {}).duplicate(true)})
		rooms[_encode_vec2i(room_key)] = records
	return {"rooms": rooms, "next_id": int(snapshot.get("next_id", 1))}


func _encode_inventory() -> Array:
	var player: Node = get_node_or_null(PlayerPath)
	var inventory: Node = player.get_node_or_null("Components/InventoryComponent") if player != null else null
	var output: Array = []
	if inventory == null:
		return output
	for index in range(int(inventory.get("Capacity"))):
		var stack: Variant = inventory.call("GetStackAt", index)
		var item: Resource = stack.get("Item") as Resource if stack != null else null
		output.append({"path": item.resource_path if item != null else "", "card_id": String(item.get("CardId")) if item != null else "", "amount": int(stack.get("Amount")) if stack != null else 0, "rolled": stack.get("RolledAttributes").duplicate(true) if stack != null else {}})
	return output


func _restore_time() -> void:
	var time_system: Node = get_node_or_null("/root/TimeSystem")
	if time_system != null and time_system.has_method("RestoreSnapshot"):
		time_system.call("RestoreSnapshot", int(_pending.get("time", 0)), int(_pending.get("day", 1)), bool(_pending.get("night", false)))


func _restore_inventory(inventory: Node) -> void:
	if inventory == null:
		return
	var entries: Array = _pending.get("inventory", []) as Array
	for index in range(mini(int(inventory.get("Capacity")), entries.size())):
		inventory.call("TryClearStackAt", index)
		var entry: Dictionary = entries[index]
		var item: Resource = _load_resource(entry)
		var amount: int = int(entry.get("amount", 0))
		if item == null or amount <= 0:
			continue
		var stack: RefCounted = ITEM_STACK_SCRIPT.new() as RefCounted
		stack.call("SetItem", item, amount)
		stack.set("RolledAttributes", entry.get("rolled", {}).duplicate(true))
		inventory.call("TrySetStackAt", index, stack)


func _restore_terrain_store(store: Node) -> void:
	if not store.has_method("GetOrCreate"):
		return
	for room_key: Variant in _pending.get("terrain", {}):
		var room: Vector2i = _decode_vec2i(room_key)
		for cell_key: Variant in _pending["terrain"][room_key]:
			var entry: Dictionary = _pending["terrain"][room_key][cell_key]
			var data: Resource = _load_resource(entry)
			if data == null:
				continue
			var position: Array = entry.get("position", [0.0, 0.0])
			var terrain: RefCounted = store.call("GetOrCreate", room, _decode_vec2i(cell_key), data, Vector2(float(position[0]), float(position[1])), entry.get("variance", {}))
			terrain.set("IsHarvested", bool(entry.get("harvested", false)))
			terrain.set("IsOccupied", bool(entry.get("occupied", false)))
			terrain.set("GrowthStage", int(entry.get("growth", 0)))
			terrain.set("RemainingGatheringCount", int(entry.get("remaining", -1)))
			terrain.set("RefreshReadyTotalTime", int(entry.get("refresh", 0)))


func _restore_loot_store(store: Node) -> void:
	if store.has_method("RestoreEncoded"):
		store.call("RestoreEncoded", _pending.get("loot", {}))


func _restore_building_store(store: Node) -> void:
	if store.has_method("RestoreEncoded"):
		store.call("RestoreEncoded", _pending.get("buildings", {}), int(_pending.get("building_next_id", 1)))


func _load_resource(entry: Dictionary) -> Resource:
	var path: String = String(entry.get("data_path", entry.get("path", "")))
	if not path.is_empty() and ResourceLoader.exists(path):
		return load(path) as Resource
	var card_id: String = String(entry.get("card_id", ""))
	return _find_resource_by_card_id(card_id)


func _find_resource_by_card_id(card_id: String) -> Resource:
	if card_id.is_empty():
		return null
	var candidates: Array[String] = []
	# 地形配置位于 resources，背包与建筑卡位于 items；两个根目录都属于快照资源。
	# 只扫描其中一个目录会让路径迁移后的 CardId 兜底只对部分数据生效。
	for root_path: String in ["res://resources", "res://items"]:
		var dir: DirAccess = DirAccess.open(root_path)
		if dir != null:
			_collect_resource_paths(dir, root_path, candidates)
	for path: String in candidates:
		var resource: Resource = load(path) as Resource
		if resource != null and String(resource.get("CardId")) == card_id:
			return resource
	return null


func _collect_resource_paths(dir: DirAccess, base_path: String, output: Array[String]) -> void:
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while not name.is_empty():
		if name == "." or name == "..":
			name = dir.get_next()
			continue
		var path: String = base_path.path_join(name)
		if dir.current_is_dir():
			var child: DirAccess = DirAccess.open(path)
			if child != null:
				_collect_resource_paths(child, path, output)
		elif name.ends_with(".tres"):
			output.append(path)
		name = dir.get_next()
	dir.list_dir_end()
