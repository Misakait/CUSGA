@tool
extends Sprite2D

## 世界地图单个房间的图片 View。
##
## 该组件只负责普通房间与当前房间纹理的切换，不读取地图 Model，
## 也不管理连接桥或相邻房间。

## 普通已探索房间使用的临时纹理。
@export var room_texture: Texture2D = preload("res://res/room_icon/Room.png")
## 玩家当前所在房间使用的临时纹理。
@export var current_room_texture: Texture2D = preload("res://res/room_icon/Room-With-Me.png")

var _is_current_room: bool = false


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_apply_texture()


## 切换本房间是否为玩家当前所在房间。
##
## @param is_current_room 为 true 时显示当前房间纹理，否则显示普通房间纹理。
## @return 无返回值。
func set_current_room(is_current_room: bool) -> void:
	_is_current_room = is_current_room
	_apply_texture()


## 返回当前房间图片使用的资源路径。
##
## @return 已设置纹理时返回资源路径，否则返回空字符串。
func get_texture_path() -> String:
	if texture == null:
		return ""
	return texture.resource_path


func _apply_texture() -> void:
	texture = current_room_texture if _is_current_room else room_texture
