extends Node2D

class_name map_base

## 地图房间根节点的公共基类，提供房间配置与初始化入口。

## 当前场景使用的房间物资生成配置；可直接创建 RoomTerrainProfile 或拖入已有配置。
@export var terrain_profile: RoomTerrainProfile

## 初始化房间显示顺序，并调用具体地图的初始化钩子。
## 返回值：无。
func initialize_scene():
	#print("卧槽，我被初始化了")
	z_index = -1
	child_initialize_scene()

## 由具体地图覆盖的初始化钩子。
## 返回值：无；默认不执行额外操作。
func child_initialize_scene():
	pass
