@tool
extends Node2D

## 世界地图单个房间的方向桥容器。
##
## 该组件只根据上、右、下、左方向掩码生成自己的直接 Sprite2D 子节点。
## 是否应当显示某个方向由 RoomTemplate 的上层协调者决定。

const DIRECTION_NAMES: Array[String] = ["Up", "Right", "Down", "Left"]

## 左右方向使用的横桥纹理。
@export var horizontal_bridge_texture: Texture2D = preload("res://res/room_icon/Room_Bridge.png")
## 上下方向使用的竖桥纹理；单独素材避免旋转像素图产生锯齿。
@export var vertical_bridge_texture: Texture2D = preload("res://res/room_icon/Room_Bridge_V.png")

var _connection_mask: int = 0
var _room_step: Vector2 = Vector2(32.0, 32.0)
var _bridge_nodes: Dictionary = {}


## 按方向掩码刷新本房间拥有的桥。
##
## @param connection_mask 按上、右、下、左映射到低四位的显示掩码。
## @param room_step 相邻房间中心的像素间距，用于把桥放在两个中心的中点。
## @return 无返回值。
func configure_bridges(connection_mask: int, room_step: Vector2) -> void:
	_connection_mask = connection_mask & 0x0F
	_room_step = room_step
	for direction in range(DIRECTION_NAMES.size()):
		if (_connection_mask & (1 << direction)) != 0:
			_ensure_bridge(direction)
		else:
			_remove_bridge(direction)


## 返回当前已经生成的方向桥数量。
##
## @return BridgeContainer 的有效桥子节点数量。
func get_generated_bridge_count() -> int:
	return _bridge_nodes.size()


## 返回当前使用的方向桥显示掩码。
##
## @return 按上、右、下、左映射到低四位的掩码。
func get_connection_mask() -> int:
	return _connection_mask


## 返回指定方向的桥节点，供运行诊断与测试读取。
##
## @param direction 方向索引，0=上、1=右、2=下、3=左。
## @return 该方向已经生成时返回 Sprite2D，否则返回 null。
func get_bridge_node(direction: int) -> Sprite2D:
	var bridge_node: Sprite2D = _bridge_nodes.get(direction, null) as Sprite2D
	if bridge_node == null or not is_instance_valid(bridge_node):
		return null
	return bridge_node


func _ensure_bridge(direction: int) -> void:
	var existing: Sprite2D = get_bridge_node(direction)
	if existing != null:
		_configure_bridge_transform(existing, direction)
		return
	var bridge_node := Sprite2D.new()
	bridge_node.name = "%sBridge" % DIRECTION_NAMES[direction]
	bridge_node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_configure_bridge_transform(bridge_node, direction)
	add_child(bridge_node)
	_bridge_nodes[direction] = bridge_node


func _remove_bridge(direction: int) -> void:
	var bridge_node: Sprite2D = _bridge_nodes.get(direction, null) as Sprite2D
	_bridge_nodes.erase(direction)
	if bridge_node != null and is_instance_valid(bridge_node):
		remove_child(bridge_node)
		bridge_node.queue_free()


func _configure_bridge_transform(bridge_node: Sprite2D, direction: int) -> void:
	bridge_node.texture = (
		vertical_bridge_texture if direction == 0 or direction == 2 else horizontal_bridge_texture
	)
	# 横竖桥都使用美术原始方向，避免像素纹理运行时旋转后产生采样锯齿。
	bridge_node.rotation = 0.0
	match direction:
		0:
			bridge_node.position = Vector2(0.0, -_room_step.y / 2.0)
		1:
			bridge_node.position = Vector2(_room_step.x / 2.0, 0.0)
		2:
			bridge_node.position = Vector2(0.0, _room_step.y / 2.0)
		3:
			bridge_node.position = Vector2(-_room_step.x / 2.0, 0.0)
