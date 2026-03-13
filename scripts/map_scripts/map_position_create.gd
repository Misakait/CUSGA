extends Node2D

@onready var map_types_ref = $"../MapTypes"

@export var map_len_x: int
@export var map_len_y: int

var max_dis_from_home: int
var max_dis_from_home_point: Array = [1,1]

#记录房间之间的链接{vector2i : [1,1,1,1]}
var scene_to_scene: Dictionary

var map: Array
var change_x: Array = [-1,0,1,0]
var change_y: Array = [0,1,0,-1]

func _ready() -> void:
	
	#初始化
	for y: int in range(map_len_y + 1):
		var row: Array = []
		for x: int in range(map_len_x + 1):
			row.append("void")
		map.append(row)
	map[1][1] = "home"
	
	while map_types_ref.get_map_count_now() > 0:
		dfs_create_map(max_dis_from_home_point, max_dis_from_home)
	map[max_dis_from_home_point[0]][max_dis_from_home_point[1]] = "boss_room"
	
	
	
	#显示地图
	for index_x in map.size():
		print(map[index_x])
	
	#显示相连场景
	#for index_x in scene_to_scene.keys():
	#	print(scene_to_scene[index_x])
	
	#显示剩余可创建地图数
	#print(map_types_ref.map_type_now)

#构建二维数组地图
func dfs_create_map(start_point: Array, dis: int, last_scene_come_here_by: int = 3):
	
	var scene_connect: Array = [0,0,0,0]
	
	#记录这个场景是从哪个场景到达的
	match last_scene_come_here_by:
		0:
			scene_connect[2] = 1
		1:
			scene_connect[3] = 1
		2:
			scene_connect[0] = 1
		3:
			scene_connect[1] = 1
		4:
			print("这是第一个房间")
		_:
			print("游戏出问题了")
	
	if dis > max_dis_from_home:
		max_dis_from_home = dis
		max_dis_from_home_point = start_point
	
	#上右下左生成场景
	for change: int in range(0, 4):
		var now_x = start_point[0] + change_x[change]
		var now_y = start_point[1] + change_y[change]
		if if_create(now_x, now_y):
			
			#代表这个场景可以前往change方向的场景
			scene_connect[change] = 1
			
			map[now_x][now_y] = create_what()
			dfs_create_map([now_x,now_y], dis+1, change)
	
	scene_to_scene[Vector2i(start_point[0], start_point[1])] = scene_connect
	
	#查看每次生成地图顺序
	#for index_x in map.size():
		#print(map[index_x])
	#print(map_types_ref.map_type_now)
	

#是否创建场景
func if_create(x: int, y: int):
	if x >= 0 && y >= 0 && x <= map_len_x && y <= map_len_y && map[x][y] == "void":
		if randi() % 2 == 0 && map_types_ref.get_map_count_now() > 0:
			return true
	
	return false

#创建什么场景
func create_what():
	while true:
		
		var randi_num = randi_range(0, map_types_ref.map_type.size() - 1)
		var scene_name: String = map_types_ref.map_type_index[randi_num]
		
		if map_types_ref.map_type_now[scene_name] != 0:
			map_types_ref.map_type_now[scene_name] -= 1
			return scene_name
	
