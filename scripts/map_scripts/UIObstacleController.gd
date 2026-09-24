extends Node2D

## 管理房间障碍的直接瓦片子节点。

## 校验场景资源，使固定模块与房间初始化使用同一入口。
## @param context Model 提供的只读房间数据，本模块不读取连接掩码。
## @return 直接瓦片层均有 TileSet 时返回 true；场景设计为空的容器允许存在。
func configure_room_context(context: RoomContext) -> bool:
	return validate_room_context(context)

## 检查直接子图层的资源，不改变场景作者配置。
## @param context Model 提供的只读房间数据。
## @return 上下文和直接子图层资源有效时返回 true。
func validate_room_context(context: RoomContext) -> bool:
	if context == null:
		return false
	# 障碍碰撞在 TileSet 中配置，不随房间连接方向改变。
	for child in get_children():
		if child is TileMapLayer and (child as TileMapLayer).tile_set == null:
			return false
	return true

