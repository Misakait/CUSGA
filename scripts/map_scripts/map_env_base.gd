extends "res://scripts/map_scripts/map_son_scripts/map_base.gd"

## map_env 场景统一基类。
##
## 继承 map_base，提供 initialize_scene() 和 terrain_profile 导出。
## 每个群系的场景挂此脚本后：
## - 地图进入时自动调用 initialize_scene() → 触发 RoomBoardPresenter 刷新地形资源
## - 在 Inspector 中为 terrain_profile 配置 RoomTerrainProfile 即可控制资源生成
##
## 如果特定场景需要特殊行为，可单独创建脚本继承此类。
