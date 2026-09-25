extends Node

## 本局建筑状态仓库；独立于会卸载的地图节点，切换房间不会丢失建筑。
## 与地形仓库一样随 Main 生命周期重建，不把随机地图坐标跨局复用。

## 建筑增删后广播对应房间坐标；实例内部状态由交互策略直接维护。
signal BuildingsChanged(room: Vector2i)
## 房间坐标到建筑记录数组；每条记录包含 id、data、position、state。
var _rooms: Dictionary = {}
## 本局单调递增的实例标识，避免相同建筑牌共享运行时状态。
var _next_id: int = 1


## 从局内快照恢复所有房间建筑与下一个稳定 ID。
## @param rooms 房间坐标到建筑记录数组的映射。
## @param next_id 后续新增建筑使用的 ID。
## @return 无返回值。
func Restore(rooms: Dictionary, next_id: int) -> void:
	_rooms = rooms.duplicate(true)
	_next_id = maxi(next_id, 1)


## 读取引用隔离的本局建筑记录。
## @return 含 rooms 和 next_id 的字典。
func Snapshot() -> Dictionary:
	return {"rooms": _rooms.duplicate(true), "next_id": _next_id}


## 从编码记录恢复建筑；无效资源项会跳过并保留其它房间。
## @param rooms 编码后的房间建筑字典。
## @param next_id 下一个实例 ID。
## @return 无返回值。
func RestoreEncoded(rooms: Dictionary, next_id: int) -> void:
	_rooms.clear()
	_next_id = maxi(next_id, 1)
	for room_key: Variant in rooms:
		var parts: PackedStringArray = str(room_key).split(",")
		if parts.size() < 2:
			continue
		var room := Vector2i(int(parts[0]), int(parts[1]))
		var records: Array = []
		for entry: Dictionary in rooms[room_key]:
			var data: Resource = _load_data(entry)
			var position: Array = entry.get("position", [0.0, 0.0])
			if data == null:
				continue
			records.append({"id": int(entry.get("id", -1)), "data": data, "position": Vector2(float(position[0]), float(position[1])), "state": entry.get("state", {}).duplicate(true)})
		_rooms[room] = records


func _load_data(entry: Dictionary) -> Resource:
	var path: String = String(entry.get("data_path", ""))
	if not path.is_empty() and ResourceLoader.exists(path):
		return load(path) as Resource
	var card_id: StringName = StringName(entry.get("card_id", ""))
	if card_id.is_empty():
		return null
	var items_control: Node = get_node_or_null("/root/ItemsControl")
	if items_control != null and items_control.has_method("get_item"):
		var indexed: Resource = items_control.call("get_item", card_id) as Resource
		if indexed != null:
			return indexed
	return _find_data_by_card_id(card_id)


func _find_data_by_card_id(card_id: StringName) -> Resource:
	var directory: DirAccess = DirAccess.open("res://items")
	if directory == null:
		return null
	return _find_data_in_directory(directory, "res://items", card_id)


func _find_data_in_directory(directory: DirAccess, base_path: String, card_id: StringName) -> Resource:
	directory.list_dir_begin()
	var file_name: String = directory.get_next()
	while not file_name.is_empty():
		if file_name != "." and file_name != "..":
			var path: String = base_path.path_join(file_name)
			if directory.current_is_dir():
				var child: DirAccess = DirAccess.open(path)
				if child != null:
					var nested: Resource = _find_data_in_directory(child, path, card_id)
					if nested != null:
						directory.list_dir_end()
						return nested
			elif file_name.ends_with(".tres"):
				var data: Resource = load(path) as Resource
				if data != null and StringName(data.get("CardId")) == card_id:
					directory.list_dir_end()
					return data
		file_name = directory.get_next()
	directory.list_dir_end()
	return null


## 读取房间建筑；room 为地图坐标，返回数组副本，记录字典保持实例身份。
func GetBuildings(room: Vector2i) -> Array:
	return (_rooms.get(room, []) as Array).duplicate()


## 登记建筑；room 为房间坐标，data 为配置，local_position 为房间局部坐标。
## 返回独立的建筑记录；调用方须先完成落点与库存校验。
func AddBuilding(room: Vector2i, data: Resource, local_position: Vector2) -> Dictionary:
	# 每次创建全新的状态字典，配置资源始终只读。
	var record: Dictionary = {"id": _next_id, "data": data, "position": local_position, "state": {}}
	_next_id += 1
	if not _rooms.has(room):
		_rooms[room] = []
	_rooms[room].append(record)
	BuildingsChanged.emit(room)
	return record


## 移除建筑；room 为房间坐标，instance_id 为实例标识，返回是否找到并移除。
## 供后续拆除、破坏系统调用；是否返还物品由调用方决定。
func RemoveBuilding(room: Vector2i, instance_id: int) -> bool:
	# 只删除指定实例，不按资源身份批量删除同类建筑。
	var buildings: Array = _rooms.get(room, [])
	for index in range(buildings.size()):
		if int(buildings[index]["id"]) == instance_id:
			buildings.remove_at(index)
			BuildingsChanged.emit(room)
			return true
	return false
