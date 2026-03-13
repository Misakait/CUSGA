extends Node2D

@export var forest_count: int
@export var cave_count: int
@export var farm_count: int
@export var boss_room_count: int

var map_type: Dictionary[String , int]
var map_type_special: Dictionary[String , int]
var map_type_now: Dictionary[String , int]
var map_type_now_special: Dictionary[String , int]
var map_type_index: Dictionary[int , String]
var map_type_index_special: Dictionary[int , String]

func _ready() -> void:
	
	map_type = {
		"forest":forest_count ,
		"cave":cave_count,
		"farm":farm_count
	}
	
	map_type_special = {
		"boss_room" : boss_room_count
	}
	
	var cnt: int = 0
	for key: String in map_type.keys():
		map_type_now[key] = map_type[key]
		map_type_index[cnt] = key
		cnt += 1
	
	cnt = 0
	for key: String in map_type_special.keys():
		map_type_now_special[key] = map_type_special[key]
		map_type_index_special[cnt] = key
		cnt += 1
	

func get_map_count_now():
	var total_cnt = 0
	
	#获取可当前地图总数量
	for cnt: int in map_type_now.values():
		total_cnt += cnt
		
	return total_cnt

func get_map_count_now_special():
	var total_cnt = 0
	
	#获取可当前特殊地图总数量
	for cnt: int in map_type_now_special.values():
		total_cnt += cnt
		
	return total_cnt
