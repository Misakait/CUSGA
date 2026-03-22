extends Node2D
class_name map_types

@export var map_type: Dictionary[String,int]

func get_map_count_now():
	var total_cnt = 0
	#获取可当前地图总数量
	for cnt: int in map_type.values():
		total_cnt += cnt
	return total_cnt
