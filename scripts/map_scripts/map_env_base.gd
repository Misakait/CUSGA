extends "res://scripts/map_scripts/map_son_scripts/map_base.gd"

## map_env 场景统一基类。
##
## 继承 map_base，提供 initialize_scene() 和 terrain_profile 导出。
## 每个群系的场景挂此脚本后：
## - 地图进入时自动调用 initialize_scene() → 触发 RoomBoardPresenter 刷新地形资源
## - 在 Inspector 中为 terrain_profile 配置 RoomTerrainProfile 即可控制资源生成
##
## 如果特定场景需要特殊行为，可单独创建脚本继承此类。

var scene_types: Dictionary = {1: "main" , 2: "secondary", 3: "market", 4: "transmitting"}

## 1表示主场景，2表示过渡场景，3表示集市场景，4表示传送场景
@export var scene_type: int

func get_scene_type() -> String:
	return scene_types.get(scene_type, "场景类型错误！")
