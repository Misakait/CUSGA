@tool
class_name MapMarkerConfig
extends Resource

## 地图标记的可编辑表现配置。
##
## Resource 只保存可复用配置，不保存某一局中的放置位置。玩家标记与场景来源标记
## 的运行时坐标统一由 MapWorldModel 管理。

## 标记类型的稳定键；发布后的资源应保持该值不变。
@export var marker_type: StringName = &"marker"
## 图例和提示中显示的中文名称。
@export var display_name: String = "地图标记"
## 大小地图共同使用的图标。
@export var icon: Texture2D
## 是否允许该配置在地图上显示。
@export var allow_map_display: bool = true
## 当前配置是否处于激活状态。
@export var active: bool = true
## 图标相对于原始纹理尺寸的显示倍率。
@export_range(0.1, 8.0, 0.05) var marker_scale: float = 1.0
## 玩家是否可以从大地图图例选择并自由放置该标记。
@export var player_placeable: bool = true
