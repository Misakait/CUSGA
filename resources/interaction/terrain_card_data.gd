extends Resource

## 描述棋盘地形卡的显示信息与交互资源。
##
## 该资源只保留原 TerrainCardData 的序列化字段。地图生成、棋盘显示和交互执行
## 通过通用 Resource 字段协议读取，以便迁移期间继续接收旧 C# TerrainCardData。

## 地形卡稳定标识，用于地图与存档中的资源识别。
@export var CardId: StringName = &""

## 地形卡显示名称。
@export var CardName: String = ""

## 地形卡显示图标。
@export var CardIcon: Texture2D

## 地形卡描述文本。
@export_multiline var Description: String = ""

## 地形卡点击后执行的交互资源。
@export var InteractionBehavior: Resource
