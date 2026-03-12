extends Node2D

@onready var map_types_ref = $"../map_types"

@export var map_len_x: int
@export var map_len_y: int

var max_dis_from_home: int
var max_dis_from_home_point: Array = [1,1]

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
	
	for index_x in map.size():
		print(map[index_x])
	print(map_types_ref.map_type_now)

#构建二维数组地图
func dfs_create_map(start_point: Array, dis: int):
	
	if dis > max_dis_from_home:
		max_dis_from_home = dis
		max_dis_from_home_point = start_point
	
	for change: int in range(0, 4):
		var now_x = start_point[0] + change_x[change]
		var now_y = start_point[1] + change_y[change]
		#上下左右
		if if_create(now_x, now_y):
			map[now_x][now_y] = create_what()
			dfs_create_map([now_x,now_y], dis+1)
	
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
		
		var name: String = map_types_ref.map_type_index[randi_range(0, map_types_ref.map_type.size() - 1)]
			
		if map_types_ref.map_type_now[name] != 0:
			map_types_ref.map_type_now[name] -= 1
			return name
	
