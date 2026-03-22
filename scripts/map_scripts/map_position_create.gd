extends Node2D

@onready var map_types_ref = $"../MapTypes"

@export var map_len_x: int
@export var map_len_y: int

var count_count: int = 0
var map_type_total_cnt: int = 0

var max_dis_from_home: int = 0
var max_dis_from_home_point: Vector2i = Vector2i(1, 1)

# 房间之间的链接 {Vector2i : [上,右,下,左]}
var scene_to_scene: Dictionary = {}

# 创建地图的顺序
var map_arr: Array[Vector2i] = []
# 搜索顺序
var map_search_arr: Array[Vector2i] = []
var map_point_has_search: Dictionary = {}

var map: Array = []

func _ready() -> void:
	randomize()
	
	map_type_total_cnt = map_types_ref.get_map_count_now() -1
	
	# 初始化二维数组
	for x in range(map_len_x + 1):
		var col: Array = []
		for y in range(map_len_y + 1):
			col.append("void")
		map.append(col)
	
	if map_types_ref.get_map_count_now() > 0:
		scene_to_scene[Vector2i(1,1)] = [0,0,0,0]
		bfs_create_map(Vector2i(1,1))
	else:
		print("你的地图数量不对啊")
		
	map_search_arr = [Vector2i(1,1)]
	bfs_search()
	
	map[max_dis_from_home_point.x][max_dis_from_home_point.y] = "boss_room"
	map[1][1] = "home"
	
	# 显示地图
	for col in map:
		print(col)

# 构建二维数组地图
func bfs_create_map(start_point: Vector2i):
	if map[start_point.x][start_point.y] == "void":
		map[start_point.x][start_point.y] = create_what()
		choose_create_position(start_point)
	
	if !map_arr.is_empty():
		var next_point: Vector2i = map_arr.pop_front()
		bfs_create_map(next_point)

func choose_create_position(start_point: Vector2i):
	var scene_can_go: Array = [0,0,0,0]
	var cnt: int = 0
	
	# 检查四个方向能否生成
	var directions = [
		Vector2i(-1,0), 
		Vector2i(0,1),  
		Vector2i(1,0),  
		Vector2i(0,-1) 
	]
	
	for i in range(4):
		var new_pos = start_point + directions[i]
		if if_create(new_pos) && map_types_ref.get_map_count_now() - cnt> map_arr.size():
			scene_can_go[i] = 1
			cnt += 1
		
	count_count += 1
	
	if cnt == 0 || map_type_total_cnt == 0:
		return
	
	# 限制生成数量，至少 1 个，最多 cnt
	var num = randi_range(1, min(cnt, map_type_total_cnt))
	map_type_total_cnt -= num
	
	# 强制保证每个新房间和父房间双向连接
	for i in range(num):
		var available_dirs: Array = []
		for j in range(4):
			if scene_can_go[j] == 1:
				available_dirs.append(j)
		
		if available_dirs.is_empty():
			break
		
		var choose_position = available_dirs[randi_range(0, available_dirs.size()-1)]
		scene_can_go[choose_position] = 0
		
		var new_pos = start_point + directions[choose_position]
		map_arr.append(new_pos)
		
		# 更新父房间和子房间的连接关系
		if !scene_to_scene.has(start_point):
			scene_to_scene[start_point] = [0,0,0,0]
		if !scene_to_scene.has(new_pos):
			scene_to_scene[new_pos] = [0,0,0,0]
		
		match choose_position:
			0: # 左
				scene_to_scene[start_point][0] = 1
				scene_to_scene[new_pos][2] = 1
			1: # 下
				scene_to_scene[start_point][1] = 1
				scene_to_scene[new_pos][3] = 1
			2: # 右
				scene_to_scene[start_point][2] = 1
				scene_to_scene[new_pos][0] = 1
			3: # 上
				scene_to_scene[start_point][3] = 1
				scene_to_scene[new_pos][1] = 1

func if_create(the_position: Vector2i) -> bool:
	if the_position.x >= 0 && the_position.x <= map_len_x && the_position.y >= 0 && the_position.y <= map_len_y:
		if map[the_position.x][the_position.y] == "void" && !map_arr.has(the_position):
			if map_types_ref.get_map_count_now() > 0 :
				return true
	return false

func create_what() -> String:
	if map_types_ref.map_cnt.size() == 0:
		return "void"
	var keys = map_types_ref.map_cnt.keys()
	var randi_num = randi_range(0, keys.size()-1)
	var now_name = keys[randi_num]
	if map_types_ref.map_cnt[now_name] > 0:
		map_types_ref.map_cnt[now_name] -= 1
		return now_name
	else:
		map_types_ref.map_cnt.erase(now_name)
		return create_what()

func bfs_search():
	var new_search_arr: Array[Vector2i] = []
	while !map_search_arr.is_empty():
		var now_point: Vector2i = map_search_arr.pop_front()
		var new_point_arr = scene_to_scene[now_point]
		var id = 0
		for num in new_point_arr:
			if num == 1:
				match id:
					0: new_search_arr.append(Vector2i(now_point.x-1, now_point.y))
					1: new_search_arr.append(Vector2i(now_point.x, now_point.y+1))
					2: new_search_arr.append(Vector2i(now_point.x+1, now_point.y))
					3: new_search_arr.append(Vector2i(now_point.x, now_point.y-1))
			id += 1
	
	for point in new_search_arr:
		if !map_point_has_search.has(point):
			map_search_arr.append(point)
			map_point_has_search[point] = 1
	
	if !map_search_arr.is_empty():
		max_dis_from_home += 1
		max_dis_from_home_point = map_search_arr.back()
		bfs_search()
