extends "res://scripts/map_scripts/map_son_scripts/map_base.gd"

## map_env 场景统一基类。
##
## 继承 map_base，提供 initialize_scene() 和 terrain_profile 导出。
## 每个群系的场景挂此脚本后：
## - 地图进入时自动调用 initialize_scene() → 触发 RoomBoardPresenter 刷新地形资源
## - 在 Inspector 中为 terrain_profile 配置地形布局 Resource 即可控制资源生成
##
## 如果特定场景需要特殊行为，可单独创建脚本继承此类。

var scene_types: Dictionary = {1: "main" , 2: "secondary", 3: "market", 4: "transmitting"}

## 1表示主场景，2表示过渡场景，3表示集市场景，4表示传送场景
@export var scene_type: int

## 将世界视图提供的房间数据转交给 MapContainer 协调器。
##
## @param context 当前房间的纯数据上下文。
## @return MapContainer 和全部模块配置成功时返回 true，否则返回 false。
func configure_room_context(context: RoomContext) -> bool:
	if context == null:
		push_error("%s 收到空的 RoomContext。" % scene_file_path)
		return false

	var map_container: Node = get_node_or_null("MapContainer")
	if map_container == null:
		push_error("%s 缺少 MapContainer，无法配置房间模块。" % scene_file_path)
		return false
	if not map_container.has_method(&"configure_room_context"):
		push_error("%s 的 MapContainer 缺少 configure_room_context(context)。" % scene_file_path)
		return false

	return bool(map_container.call(&"configure_room_context", context))

## 返回场景类型的兼容名称。
## @return 已配置的类型名称；未知编号返回错误说明。
func get_scene_type() -> String:
	return scene_types.get(scene_type, "场景类型错误！")
