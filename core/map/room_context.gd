extends Resource
class_name RoomContext

## 单个已生成房间的只读显示上下文。
##
## 只传递地图数据，不持有场景节点或玩家引用；接收方不得修改上下文。

const DIRECTION_UP: int = 0
const DIRECTION_RIGHT: int = 1
const DIRECTION_DOWN: int = 2
const DIRECTION_LEFT: int = 3

## 当前房间在生成地图中的 row/column 坐标。
@export var room_position: Vector2i = Vector2i.ZERO
## 按 MapPositionCreate 的上、右、下、左顺序记录连接方向。
@export_flags("上", "右", "下", "左") var connection_mask: int = 0
## 完整房间场景在连续世界中的尺寸。
@export var room_size: Vector2 = Vector2(1280.0, 720.0)
## 当前房间坐标所使用的场景资源配置。
@export var scene_resource: MapSceneResource


## 返回指定方向是否存在由地图生成器确认的相邻连接。
##
## @param direction 上、右、下、左的方向索引，范围为 0 到 3。
## @return 该方向连接位为 1 时返回 true；索引无效时返回 false。
func has_connection(direction: int) -> bool:
	if direction < DIRECTION_UP or direction > DIRECTION_LEFT:
		return false
	return (connection_mask & (1 << direction)) != 0
