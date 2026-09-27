@tool
extends Node2D

## 世界地图单个房间的组合模板。
##
## 该组件只把画布传入的房间状态分发给 RoomView 与 BridgeContainer，
## 不读取地图 Model，也不实现纹理和桥节点的具体生成逻辑。

var room_position: Vector2i = Vector2i.ZERO

@onready var room_view: Sprite2D = $RoomView
@onready var bridge_container: Node2D = $BridgeContainer


## 配置一个地图房间模板的坐标、视觉状态和方向桥。
##
## @param map_position 房间在 row/column 地图网格中的坐标。
## @param canvas_position 房间图片中心在 WorldMapCanvas 中的局部坐标。
## @param bridge_mask 本模板负责显示的上、右、下、左方向桥掩码。
## @param room_step 相邻房间中心的像素间距。
## @param is_current_room 本房间是否为玩家当前所在房间。
## @return 子组件协议完整并成功配置时返回 true，否则返回 false。
func configure_room(
	map_position: Vector2i,
	canvas_position: Vector2,
	bridge_mask: int,
	room_step: Vector2,
	is_current_room: bool
) -> bool:
	if not _has_required_child_protocol():
		push_error("UIWorldMapRoomTemplate 的 RoomView 或 BridgeContainer 缺少必要接口。")
		return false
	room_position = map_position
	position = canvas_position
	room_view.call(&"set_current_room", is_current_room)
	bridge_container.call(&"configure_bridges", bridge_mask, room_step)
	return true


## 更新本模板的当前房间纹理状态。
##
## @param is_current_room 本房间是否为玩家当前所在房间。
## @return 子组件接口存在并完成更新时返回 true，否则返回 false。
func set_current_room(is_current_room: bool) -> bool:
	if room_view == null or not room_view.has_method(&"set_current_room"):
		return false
	room_view.call(&"set_current_room", is_current_room)
	return true


## 更新本模板负责显示的方向桥。
##
## @param bridge_mask 上、右、下、左方向桥掩码。
## @param room_step 相邻房间中心的像素间距。
## @return 子组件接口存在并完成更新时返回 true，否则返回 false。
func set_bridge_mask(bridge_mask: int, room_step: Vector2) -> bool:
	if bridge_container == null or not bridge_container.has_method(&"configure_bridges"):
		return false
	bridge_container.call(&"configure_bridges", bridge_mask, room_step)
	return true


## 返回 RoomView 当前使用的纹理路径。
##
## @return RoomView 接口存在时返回纹理路径，否则返回空字符串。
func get_room_texture_path() -> String:
	if room_view == null or not room_view.has_method(&"get_texture_path"):
		return ""
	return String(room_view.call(&"get_texture_path"))


## 返回 BridgeContainer 当前已经生成的桥数量。
##
## @return BridgeContainer 接口存在时返回桥数量，否则返回 0。
func get_generated_bridge_count() -> int:
	if bridge_container == null or not bridge_container.has_method(&"get_generated_bridge_count"):
		return 0
	return int(bridge_container.call(&"get_generated_bridge_count"))


## 返回 BridgeContainer 当前使用的方向桥掩码。
##
## @return BridgeContainer 接口存在时返回方向掩码，否则返回 0。
func get_bridge_mask() -> int:
	if bridge_container == null or not bridge_container.has_method(&"get_connection_mask"):
		return 0
	return int(bridge_container.call(&"get_connection_mask"))


func _has_required_child_protocol() -> bool:
	return (
		room_view != null
		and room_view.has_method(&"set_current_room")
		and room_view.has_method(&"get_texture_path")
		and bridge_container != null
		and bridge_container.has_method(&"configure_bridges")
		and bridge_container.has_method(&"get_generated_bridge_count")
	)
