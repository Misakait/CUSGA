extends Node

## 本局建筑状态仓库；独立于会卸载的地图节点，切换房间不会丢失建筑。
## 与地形仓库一样随 Main 生命周期重建，不把随机地图坐标跨局复用。

## 建筑增删后广播对应房间坐标；实例内部状态由交互策略直接维护。
signal BuildingsChanged(room: Vector2i)
## 房间坐标到建筑记录数组；每条记录包含 id、data、position、state。
var _rooms: Dictionary = {}
## 本局单调递增的实例标识，避免相同建筑牌共享运行时状态。
var _next_id: int = 1


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
