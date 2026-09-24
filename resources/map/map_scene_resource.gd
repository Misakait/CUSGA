extends Resource
class_name MapSceneResource

## 地图房间的资源配置。
##
## 该资源只描述一个地图坐标对应的完整房间场景，不保存运行时 Node2D。
## 这样可以让窗口外房间释放节点后仍保留配置和 PackedScene 资源。

## 地图坐标对应的场景显示名称。
@export var scene_name: String = ""
## 完整房间场景的 res:// 路径。
@export_file("*.tscn") var scene_path: String = ""
## 已加载的完整房间资源；同一路径由 Model 共享这一份资源。
var packed_scene: PackedScene = null
## 房间地形布局配置，保留给 View 创建显示实例时读取。
var terrain_profile: Resource = null
## 单个完整房间的世界尺寸。
@export var room_size: Vector2 = Vector2(1280.0, 720.0)

