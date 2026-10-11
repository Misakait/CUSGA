extends Resource
class_name RoomTerrainProfile

## 描述房间地形生成所需的池、数量、网格和摆放范围配置。
##
## 该 Resource 只保存可序列化配置；随机抽样与布局计算由
## RoomTerrainLayoutGenerator 负责，不在配置资源中保存房间运行时状态。

## 当前房间可抽取的地形池；新增元素时创建 terrain_pool_entry，再配置地形与权重。
@export var TerrainPool: Array[terrain_pool_entry] = []

## 生成布局时允许的最少地形数量。
@export var MinCount: int = 1

## 生成布局时允许的最多地形数量。
@export var MaxCount: int = 3

## 布局网格的列数。
@export var GridColumns: int = 6

## 布局网格的行数。
@export var GridRows: int = 4

## 地形卡摆放区域的左上角坐标。
@export var PlacementMin: Vector2 = Vector2(360, 220)

## 地形卡摆放区域的右下角坐标。
@export var PlacementMax: Vector2 = Vector2(920, 560)

## 遭遇怪物属性倍率范围资源；为空时使用中性倍率。
@export var EncounterVarianceRange: MonsterStatMultiplierRange
