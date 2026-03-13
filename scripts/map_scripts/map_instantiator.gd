extends Node

@onready var map_position = $"../MapPositionCreate"
@onready var map_road = $"../MapRoad"
@onready var map_button = $"../MapButton"

var current_scene: Node2D = null
var current_position: Vector2i = Vector2i.ZERO
#储存每个点的场景路径
var map_road_in_map : Dictionary[Vector2i , String] = {}
#储存所有已加载场景的实例
var map_scene: Dictionary

func _ready() -> void:
	#创建地图
	create_map()
	load_scene_at(Vector2i(1,1))
	
func create_map():
	var map = map_position.map
	
	#创建地图对应的场景路径
	for x in range(0 , map.size()):
		for y in range(0 , map[x].size()):
			map_road_in_map[Vector2i(x,y)] = map_road.from_name_get_road(map[x][y])

func load_scene_at(position: Vector2i):
	
	print("你目前在",position)
	
	if current_scene:
		remove_child(current_scene)
			
	#情况一：该场景已经创建过
	if map_scene.has(position):
		current_scene = map_scene[position]
	
	#情况二：该场景没创建过，就实例化并保存下来
	else:
		var load_road: String = map_road_in_map[position]
		var load_scene = load(load_road)
		current_scene = load_scene.instantiate()
		
		#添加到“已加载的地图场景”
		map_scene[position] = current_scene
		
		#初始化该场景
		if current_scene.has_method("initialize_scene"):
			current_scene.initialize_scene()
	
	#添加到场景树
	add_child(current_scene)
	current_position = position
	
	#更新按钮
	map_button.update_scene_button(position)
