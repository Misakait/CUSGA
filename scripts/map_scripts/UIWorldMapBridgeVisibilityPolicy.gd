@tool
extends RefCounted

## 世界地图连接桥显示与所有权策略。
##
## 该无状态策略只根据 Model 连接、探索集合和显示模式计算一个 RoomTemplate
## 应持有的方向桥掩码，不创建或修改任何场景节点。

enum Mode {
	ALL_CONNECTED,
	DISCOVERED_ROOMS_ONLY,
}

const DIRECTION_OFFSETS: Array[Vector2i] = [
	Vector2i(-1, 0),
	Vector2i(0, 1),
	Vector2i(1, 0),
	Vector2i(0, -1),
]


## 返回桥显示模式数值是否受支持。
##
## @param mode 要检查的模式数值。
## @return mode 对应 Mode 枚举中的值时返回 true。
static func is_valid_mode(mode: int) -> bool:
	return mode >= Mode.ALL_CONNECTED and mode <= Mode.DISCOVERED_ROOMS_ONLY


## 计算一个已探索房间模板应持有的方向桥掩码。
##
## @param map_model 提供 are_rooms_connected 的地图 Model。
## @param room_position 当前模板对应的地图坐标。
## @param discovered_rooms 以 Vector2i 为键的已探索房间集合。
## @param mode ALL_CONNECTED 显示未探索方向；DISCOVERED_ROOMS_ONLY 隐藏该方向。
## @return 按上、右、下、左映射到低四位，并且已经去重的方向桥掩码。
static func get_owned_bridge_mask(
	map_model: Node, room_position: Vector2i, discovered_rooms: Dictionary, mode: int
) -> int:
	if map_model == null or not map_model.has_method(&"are_rooms_connected"):
		return 0
	if not is_valid_mode(mode):
		return 0
	var bridge_mask: int = 0
	for direction in range(DIRECTION_OFFSETS.size()):
		var neighbor: Vector2i = room_position + DIRECTION_OFFSETS[direction]
		if not bool(map_model.call(&"are_rooms_connected", room_position, neighbor)):
			continue
		var neighbor_discovered: bool = discovered_rooms.has(neighbor)
		if mode == Mode.DISCOVERED_ROOMS_ONLY and not neighbor_discovered:
			continue
		# 未探索邻居没有模板；双方都探索后由坐标靠前者持有，保证一对房间只有一座桥。
		if neighbor_discovered and _position_precedes(neighbor, room_position):
			continue
		bridge_mask |= 1 << direction
	return bridge_mask


static func _position_precedes(first: Vector2i, second: Vector2i) -> bool:
	return first.x < second.x or (first.x == second.x and first.y < second.y)
