extends Node2D

## 管理已连接窄桥两侧边界；只操作本容器的四个直接瓦片子节点。
const LAYER_NAMES: Array[StringName] = [
	&"UpBridgeBoundary", &"RightBridgeBoundary", &"DownBridgeBoundary", &"LeftBridgeBoundary",
]

## 根据生成连接数据同步本模块方向状态。
## @param context Model 提供的只读房间数据，方向顺序为上、右、下、左。
## @return 四个方向瓦片层齐全且已应用状态时返回 true。
func configure_room_context(context: RoomContext) -> bool:
	if not validate_room_context(context):
		push_error("UIBridgeBoundaryController 收到无效上下文或缺少有效方向瓦片。")
		return false
	for direction in range(LAYER_NAMES.size()):
		var active: bool = context.has_connection(direction)
		var layer := get_node(NodePath(LAYER_NAMES[direction])) as TileMapLayer
		layer.visible = active
		# 隐藏画面本身不会移除物理阻挡，必须同时明确同步碰撞开关。
		layer.collision_enabled = active
	return true


## 只校验直接方向图层，供协调器在切换任意桥口前统一预检。
## @param context Model 提供的只读房间数据。
## @return 上下文和四个方向图层有效时返回 true；不改变任何图层。
func validate_room_context(context: RoomContext) -> bool:
	if context == null:
		return false
	for layer_name in LAYER_NAMES:
		var layer := get_node_or_null(NodePath(layer_name)) as TileMapLayer
		if layer == null or layer.tile_set == null or layer.get_used_cells().is_empty():
			return false
	return true
