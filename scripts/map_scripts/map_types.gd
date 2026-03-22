extends Node2D

@export var map_type_attribute: Array[map_attribute]
#地图名字与数量
var map_cnt: Dictionary[String,int]
#地图名字与对应场景路径
var map_road: Dictionary[String,PackedScene]

func _ready() -> void:
	build_map_types()
	build_map_road()

func build_map_types():
	for map_attr in map_type_attribute:
		var scene_name: String = map_attr.scene_name
		var scene_cnt: int = map_attr.scene_count
		map_cnt[scene_name] = scene_cnt

func build_map_road():
	for map_attr in map_type_attribute:
		var scene_name: String = map_attr.scene_name
		var scene_pkg: PackedScene = map_attr.scene_pkg
		map_road[scene_name] = scene_pkg

func get_map_count_now():
	var total_cnt = 0
	#获取可当前地图总数量
	for cnt: map_attribute in map_type_attribute:
		total_cnt += cnt.scene_count
	return total_cnt

func from_name_get_road(name: String):
	match name:
		
		_:
			return "void";
