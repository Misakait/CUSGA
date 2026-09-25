extends Node

## 按房间保存本局掉落状态；视图卸载不会改变记录。
signal LootAdded(room: Vector2i, record: Dictionary)
## 掉落被成功领取后通知表现层。
signal LootRemoved(room: Vector2i, instance_id: int)

var _rooms: Dictionary = {}
var _next_id: int = 1


## 登记掉落的最终房间局部落点。
## @param room 地图房间坐标。
## @param stack 有效物品堆叠。
## @param local_position 房间局部最终落点。
## @return 新记录；堆叠无效时返回空字典。
func AddLoot(room: Vector2i, stack: RefCounted, local_position: Vector2) -> Dictionary:
	if stack == null or stack.get("Item") == null or int(stack.get("Amount")) <= 0:
		return {}
	var record: Dictionary = {
		"id": _next_id, "stack": stack, "position": local_position,
	}
	_next_id += 1
	if not _rooms.has(room):
		_rooms[room] = []
	(_rooms[room] as Array).append(record)
	LootAdded.emit(room, record)
	return record


## 读取房间掉落记录的数组副本，记录本身仍由仓库拥有。
## @param room 地图房间坐标。
## @return 掉落记录数组。
func GetLoot(room: Vector2i) -> Array:
	return (_rooms.get(room, []) as Array).duplicate()


## 按稳定 ID 移除已领取掉落，防止重复点击再次结算。
## @param room 地图房间坐标。
## @param instance_id 掉落实例 ID。
## @return 只在首次找到记录时返回 true。
func RemoveLoot(room: Vector2i, instance_id: int) -> bool:
	var records: Array = _rooms.get(room, [])
	for index in range(records.size()):
		if int(records[index].get("id", -1)) == instance_id:
			records.remove_at(index)
			LootRemoved.emit(room, instance_id)
			return true
	return false


## 清空并恢复已解码的房间记录；供局内快照入口调用。
## @param rooms 房间坐标到记录数组的映射。
## @param next_id 下一个不会与旧记录冲突的 ID。
## @return 无返回值。
func Restore(rooms: Dictionary, next_id: int) -> void:
	_rooms = rooms.duplicate(true)
	_next_id = maxi(next_id, 1)


## 返回当前状态的引用隔离快照。
## @return 含 rooms 与 next_id 的字典。
func Snapshot() -> Dictionary:
	return {"rooms": _rooms.duplicate(true), "next_id": _next_id}


## 把掉落堆叠编码成可写入 JSON 的稳定资源信息。
## @return 房间坐标键到掉落数组的字典。
func SnapshotEncoded() -> Dictionary:
	var output: Dictionary = {}
	for room: Variant in _rooms:
		var records: Array = []
		for record: Dictionary in _rooms[room]:
			var stack: RefCounted = record.get("stack") as RefCounted
			var item: Resource = stack.get("Item") as Resource if stack != null else null
			records.append({
				"id": int(record.get("id", -1)),
				"path": item.resource_path if item != null else "",
				"card_id": String(item.get("CardId")) if item != null else "",
				"amount": int(stack.get("Amount")) if stack != null else 0,
				"rolled": stack.get("RolledAttributes").duplicate(true) if stack != null else {},
				"position": [record.get("position", Vector2.ZERO).x, record.get("position", Vector2.ZERO).y],
			})
		output["%d,%d" % [room.x, room.y]] = records
	return {"rooms": output, "next_id": _next_id}


## 从快照字典恢复掉落堆叠；资源解析由 card_id 目录查找兜底。
## @param encoded 编码后的房间掉落。
## @return 无返回值。
func RestoreEncoded(encoded: Dictionary) -> void:
	_rooms.clear()
	_next_id = maxi(int(encoded.get("next_id", 1)), 1)
	for room_key: Variant in encoded.get("rooms", {}):
		var room_parts: PackedStringArray = str(room_key).split(",")
		if room_parts.size() < 2:
			continue
		var room := Vector2i(int(room_parts[0]), int(room_parts[1]))
		var records: Array = []
		for encoded_record: Dictionary in encoded["rooms"][room_key]:
			var item: Resource = _load_item(encoded_record)
			var amount: int = int(encoded_record.get("amount", 0))
			var position: Array = encoded_record.get("position", [0.0, 0.0])
			if item == null or amount <= 0:
				continue
			var stack: RefCounted = load("res://resources/item/item_stack.gd").new() as RefCounted
			stack.call("SetItem", item, amount)
			stack.set("RolledAttributes", encoded_record.get("rolled", {}).duplicate(true))
			records.append({"id": int(encoded_record.get("id", -1)), "stack": stack, "position": Vector2(float(position[0]), float(position[1]))})
		_rooms[room] = records


func _load_item(entry: Dictionary) -> Resource:
	var path: String = String(entry.get("path", ""))
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
	return _find_item_by_card_id(card_id)


func _find_item_by_card_id(card_id: StringName) -> Resource:
	var directory: DirAccess = DirAccess.open("res://items")
	if directory == null:
		return null
	return _find_item_in_directory(directory, "res://items", card_id)


func _find_item_in_directory(directory: DirAccess, base_path: String, card_id: StringName) -> Resource:
	directory.list_dir_begin()
	var file_name: String = directory.get_next()
	while not file_name.is_empty():
		if file_name != "." and file_name != "..":
			var path: String = base_path.path_join(file_name)
			if directory.current_is_dir():
				var child: DirAccess = DirAccess.open(path)
				if child != null:
					var nested: Resource = _find_item_in_directory(child, path, card_id)
					if nested != null:
						directory.list_dir_end()
						return nested
			elif file_name.ends_with(".tres"):
				var item: Resource = load(path) as Resource
				if item != null and StringName(item.get("CardId")) == card_id:
					directory.list_dir_end()
					return item
		file_name = directory.get_next()
	directory.list_dir_end()
	return null
