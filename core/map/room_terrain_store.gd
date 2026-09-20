extends Node

## 房间地形实例仓库的 GDScript 生产实现，等价迁移自 RoomTerrainStore.cs。
##
## 只负责按房间坐标缓存 TerrainInstance、按摆放结果创建实例并写入地形浮动倍率；
## 棋盘卡集合、视图、存档与战斗仍由原拥有者负责，本文件不复制任何玩法规则。
##
## 地形实例由本批 GDScript 生产实现提供，字段名与旧 C# 属性逐字一致；
## C# 消费者通过 TerrainInstanceProtocol 读写同一组字段，浮动倍率继续走
## ApplyEncounterVarianceSnapshot / GetEncounterVarianceSnapshot 字典协议。

## GDScript 地形实例脚本；这是全项目唯一的地形实例创建点。
const TERRAIN_INSTANCE_SCRIPT: Script = preload("res://resources/interaction/terrain_instance.gd")

## 房间坐标 -> （房间内局部格子坐标 -> TerrainInstance）。
var _terrainByRoom: Dictionary = {}


## 获取或创建指定房间格子上的地形实例。
##
## @param room_pos 房间坐标。
## @param local_grid_pos 房间内局部格子坐标。
## @param terrain_data 地形配置资源，不能为空。
## @param board_position 地形卡的棋盘显示位置，默认原点。
## @param encounter_variance 该地形的遭遇浮动倍率字典；为空表示中性倍率。
## @return 已存在或新建的地形实例；terrain_data 无效时返回 null。
func GetOrCreate(
	room_pos: Vector2i,
	local_grid_pos: Vector2i,
	terrain_data: Resource,
	board_position: Vector2 = Vector2.ZERO,
	encounter_variance: Variant = null
) -> RefCounted:
	if terrain_data == null:
		push_error("RoomTerrainStore.GetOrCreate 需要非空的 terrain_data。")
		return null

	var room_terrains: Dictionary = _ensure_room(room_pos)
	if room_terrains.has(local_grid_pos):
		return room_terrains[local_grid_pos] as RefCounted

	var instance: RefCounted = _create_terrain_instance(
		local_grid_pos, terrain_data, board_position, encounter_variance
	)
	room_terrains[local_grid_pos] = instance
	return instance


## 判断房间是否已经建立过地形缓存。
##
## @param room_pos 房间坐标。
## @return 房间已存在时返回 true。
func HasRoom(room_pos: Vector2i) -> bool:
	return _terrainByRoom.has(room_pos)


## 按摆放结果批量建立房间地形。
##
## @param room_pos 房间坐标。
## @param placements 摆放字典数组，每项含 TerrainData、LocalGridPos、BoardPosition、Variance。
## @return 全部摆放成功时返回 true；格子已被占用时记录同一旧错误文案并返回 false。
func CreateRoomLayout(room_pos: Vector2i, placements: Array) -> bool:
	var room_terrains: Dictionary = _ensure_room(room_pos)
	for placement: Variant in placements:
		var cell_value: Variant = _read_field(placement, "LocalGridPos", null)
		if cell_value == null:
			continue

		var cell: Vector2i = cell_value
		if room_terrains.has(cell):
			push_error("Room %s already contains terrain at %s." % [room_pos, cell])
			return false

		var terrain_data: Resource = _read_field(placement, "TerrainData", null) as Resource
		var board_position: Vector2 = _read_field(placement, "BoardPosition", Vector2.ZERO)
		var variance: Variant = _read_field(placement, "Variance", null)
		room_terrains[cell] = _create_terrain_instance(
			cell, terrain_data, board_position, variance
		)

	return true


## 读取指定房间格子上的地形实例。
##
## @param room_pos 房间坐标。
## @param local_grid_pos 房间内局部格子坐标。
## @return 地形实例；房间或格子不存在时返回 null。
func TryGetTerrain(room_pos: Vector2i, local_grid_pos: Vector2i) -> RefCounted:
	if not _terrainByRoom.has(room_pos):
		return null
	var room_terrains: Dictionary = _terrainByRoom[room_pos]
	if not room_terrains.has(local_grid_pos):
		return null
	return room_terrains[local_grid_pos] as RefCounted


## 返回房间内的全部地形实例。
##
## @param room_pos 房间坐标。
## @return 局部格子坐标到 TerrainInstance 的映射；房间不存在时返回空字典。
func GetRoomTerrainsOrEmpty(room_pos: Vector2i) -> Dictionary:
	if _terrainByRoom.has(room_pos):
		return _terrainByRoom[room_pos]
	return {}


## 确保房间缓存字典存在。
##
## @param room_pos 房间坐标。
## @return 该房间的房间内格子映射字典。
func _ensure_room(room_pos: Vector2i) -> Dictionary:
	if not _terrainByRoom.has(room_pos):
		_terrainByRoom[room_pos] = {}
	return _terrainByRoom[room_pos]


## 创建地形实例并写入旧实现的初始化默认值。
##
## @param local_grid_pos 房间内局部格子坐标。
## @param terrain_data 地形配置资源。
## @param board_position 地形卡棋盘显示位置。
## @param encounter_variance 遭遇浮动倍率字典。
## @return 新建的地形实例。
func _create_terrain_instance(
	local_grid_pos: Vector2i,
	terrain_data: Resource,
	board_position: Vector2,
	encounter_variance: Variant
) -> RefCounted:
	var instance: RefCounted = TERRAIN_INSTANCE_SCRIPT.new()
	instance.set("LocalGridPos", local_grid_pos)
	instance.set("BoardPosition", board_position)
	instance.set("TerrainData", terrain_data)
	instance.set("IsOccupied", false)
	instance.set("IsHarvested", false)
	instance.set("GrowthStage", 0)
	_apply_encounter_variance(instance, encounter_variance)
	return instance


## 通过字典协议写入浮动倍率。
##
## @param instance 新建的地形实例。
## @param encounter_variance 倍率字典；为空时保持旧实现的中性倍率默认值。
## @return 无；缺少跨语言写入协议时记录错误，避免倍率被静默忽略。
func _apply_encounter_variance(instance: RefCounted, encounter_variance: Variant) -> void:
	if encounter_variance == null:
		return
	if not instance.has_method("ApplyEncounterVarianceSnapshot"):
		push_error("TerrainInstance 缺少 ApplyEncounterVarianceSnapshot 协议，浮动倍率无法写入。")
		return
	instance.call("ApplyEncounterVarianceSnapshot", encounter_variance)


## 从摆放字典或对象读取字段。
##
## @param source 摆放条目。
## @param field_name 字段名称。
## @param fallback 字段缺失时的默认值。
## @return 字段值或默认值。
func _read_field(source: Variant, field_name: String, fallback: Variant) -> Variant:
	if source == null:
		return fallback
	if source is Dictionary:
		var dictionary: Dictionary = source
		return dictionary[field_name] if dictionary.has(field_name) else fallback
	if source is Object:
		var object: Object = source
		return object.get(field_name)
	return fallback
