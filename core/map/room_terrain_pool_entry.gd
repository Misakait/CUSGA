extends Resource
class_name terrain_pool_entry

## 描述房间地形池中的一个候选地形及其抽取权重。
##
## 条目只保存地形配置与相对权重；随机抽样由 RoomTerrainLayoutGenerator 负责。

## 候选地形资源点；创建 TerrainCardData 后配置外观与交互行为。
@export var TerrainData: TerrainCardData

## 候选地形的相对抽取权重，非正值不会增加抽取概率。
@export var Weight: float = 1.0
