extends Node2D

class_name map_base

## 当前场景使用的地形布局配置；迁移期间兼容 C# 与 GDScript Resource。
@export var terrain_profile: Resource

func initialize_scene():
	#print("卧槽，我被初始化了")
	z_index = -1
	child_initialize_scene()

func child_initialize_scene():
	pass
