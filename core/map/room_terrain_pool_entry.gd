extends Resource

## 描述房间地形池中的一个候选地形及其抽取权重。
##
## TerrainData 保持为通用 Resource，使尚未迁移的 C# TerrainCardData
## 与本批 GDScript 资源可以共存；权重抽样仍由 RoomTerrainLayoutGenerator 负责。

## 候选地形卡资源。
@export var TerrainData: Resource

## 候选地形的相对抽取权重，非正值不会增加抽取概率。
@export var Weight: float = 1.0
