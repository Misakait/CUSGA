extends Node2D

@onready var map_types_ref = $"../MapTypes"

@export var map_len_x: int
@export var map_len_y: int

var max_dis_from_home: int = 0
var max_dis_from_home_point: Array = [1,1]

#记录房间之间的链接{vector2i : [1,1,1,1]}
var scene_to_scene: Dictionary

#创建地图的顺序
var map_arr: Array
#搜索顺序
var map_search_arr: Array
var map: Array

func _ready() -> void:
	
	randomize()
	
	#初始化
	for y: int in range(map_len_y + 1):
		var row: Array = []
		for x: int in range(map_len_x + 1):
			row.append("void")
		map.append(row)
	map[1][1] = "home"
	
	if map_types_ref.get_map_count_now() > 0:
		scene_to_scene[Vector2i(1,1)] = [0,0,0,0]
		bfs_create_map(max_dis_from_home_point)
	
	map_search_arr = []
	bfs_search([1,1])
	map[max_dis_from_home_point[0]][max_dis_from_home_point[1]] = "boss_room"
	
	for key in scene_to_scene.keys():
		print(key," ",scene_to_scene[key])
	
	#显示地图
	for index_x in map.size():
		print(map[index_x])

#构建二维数组地图
func bfs_create_map(start_point: Array):
	
	map[start_point[0]][start_point[1]] = create_what()
	
	choose_create_position(start_point)
	
	if !map_arr.is_empty():
		var next_point: Array = map_arr.pop_front()
		bfs_create_map(next_point)


func choose_create_position(start_point: Array):
	
	var new_start_point: Vector2i = Vector2i(start_point[0],start_point[1])
	
	#这个场景可衍生的场景
	var scene_can_go: Array = [0,0,0,0]
	#这个场景最多可以衍生的场景数,并记录可衍生的场景
	var cnt: int = 4
	var cnt_id = 0
	for num in scene_to_scene[Vector2i(start_point[0],start_point[1])]:
		cnt -= num
		if num == 0:
			scene_can_go[cnt_id] = 1
		cnt_id += 1
		
	
	#与剩余可生成场景比较,防止cnt大于最大可生成场景数
	if cnt > map_types_ref.map_type_total_cnt:
		cnt = map_types_ref.map_type_total_cnt
		
	if cnt == 0:
		return
		
	#这个场景衍生个多少场景
	var num = randi_range(1,cnt)
	map_types_ref.map_type_total_cnt -= num
	
	for scene_id in range(0,num):
		var choose_position: int = 0
		var choose_position_id = randi_range(1,cnt)
		
		#从上右下左选一个方向
		var id = 0;
		for i in scene_can_go:
			if i == 1:
				choose_position_id -= 1
			if choose_position_id == 0:
				choose_position = id
				scene_can_go[id] = 0
				cnt -= 1
				break
			id += 1
			
		#上右下左衍生场景
		match choose_position:
			0:
				var new_x: int = start_point[0]-1
				var new_y: int = start_point[1]
				var new_pos = Vector2i(new_x,new_y)
				
				if if_create(new_pos):
					map_arr.append([new_x,new_y])
				else:
					continue
				
				scene_to_scene[new_start_point][0] = 1
				if !scene_to_scene.has(new_pos):
					scene_to_scene[new_pos] = [0,0,1,0]
				else:
					scene_to_scene[new_pos][2] = 1
			1:
				var new_x: int = start_point[0]
				var new_y: int = start_point[1]+1
				var new_pos = Vector2i(new_x,new_y)
				
				if if_create(new_pos):
					map_arr.append([new_x,new_y])
				else:
					continue
				
				scene_to_scene[new_start_point][1] = 1
				if !scene_to_scene.has(new_pos):
					scene_to_scene[new_pos] = [0,0,0,1]
				else:
					scene_to_scene[new_pos][3] = 1
			2:
				var new_x: int = start_point[0]+1
				var new_y: int = start_point[1]
				var new_pos = Vector2i(new_x,new_y)
				
				if if_create(new_pos):
					map_arr.append([new_x,new_y])
				else:
					continue
				
				scene_to_scene[new_start_point][2] = 1
				if !scene_to_scene.has(new_pos):
					scene_to_scene[new_pos] = [1,0,0,0]
				else:
					scene_to_scene[new_pos][0] = 1
			3:
				var new_x: int = start_point[0]
				var new_y: int = start_point[1]-1
				var new_pos = Vector2i(new_x,new_y)
				
				if if_create(new_pos):
					map_arr.append([new_x,new_y])
				else:
					continue
				
				scene_to_scene[new_start_point][3] = 1
				if !scene_to_scene.has(new_pos):
					scene_to_scene[new_pos] = [0,1,0,0]
				else:
					scene_to_scene[new_pos][1] = 1
			_:
				print("如果你看到这个，就说明有错误在map_position_create脚本")

#能否创建这个点
func if_create(the_position: Vector2i):
	if the_position.x >= 0 && the_position.x <= map_len_x && the_position.y >= 0 && the_position.y <= map_len_y:
		if map[the_position.x][the_position.y] == "void" && map_types_ref.get_map_count_now() > 0:
			return true
	return false

#创建什么场景
func create_what():
	while true:
		
		if map_types_ref.map_type_now.size() == 0:
			return "void"
			
		var randi_num = randi_range(1, map_types_ref.map_type_now.size())
		var id = 1
		
		for now_name in map_types_ref.map_type_now.keys():
			if id == randi_num:
				if map_types_ref.map_type_now[now_name] != 0:
					map_types_ref.map_type_now[now_name] -= 1
					return now_name
				else:
					map_types_ref.map_type_now.erase(now_name)
					break
			else:
				id += 1
		
func bfs_search(start_point: Array):
	var new_search_arr: Array = []
	while !map_search_arr.is_empty():
		var now_point = map_search_arr.pop_front()
		var new_point_arr = scene_to_scene[Vector2i(now_point[0],now_point[1])]
		var id = 0
		for num in new_point_arr:
			if num == 1:
				match id:
					0:
						new_search_arr.append([now_point[0]-1,now_point[1]])
					1:
						new_search_arr.append([now_point[0],now_point[1]+1])
					2:
						new_search_arr.append([now_point[0]+1,now_point[1]])
					3:
						new_search_arr.append([now_point[0],now_point[1]-1])
					_:
						print("如果你看到这个,说明map_position_create出错了")
			id += 1
	map_search_arr.append_array(new_search_arr)
	max_dis_from_home += 1
	max_dis_from_home_point = map_search_arr.front()
	
