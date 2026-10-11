extends Resource
class_name TerrainCardData

## 描述棋盘地形卡的显示信息与交互资源。
##
## 该资源保存资源点外观与交互配置；地图生成、棋盘显示和交互执行读取稳定字段。

## 地形卡稳定标识，用于地图与存档中的资源识别。
@export var CardId: StringName = &""

## 地形卡显示名称。
@export var CardName: String = ""

## 地形卡显示图标。
@export var CardIcon: Texture2D

## 地形卡描述文本。
@export_multiline var Description: String = ""

## 地形卡的交互规则；选择一次性采集、可重复采集、农场、密库或首领交互。
@export_custom(PROPERTY_HINT_RESOURCE_TYPE, "GatheringInteraction,ReusableGatheringInteraction,FarmingInteraction,VaultInteraction,BossInteraction") var InteractionBehavior: Resource
