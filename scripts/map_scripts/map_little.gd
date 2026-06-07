extends Node2D

@onready var map_position_create = $"../MapPositionCreate"

@export_dir var cell_pic: String
@export_dir var bridge_pic: String

@export var if_see_all_little_map: bool = false
@export var if_show_the_scene: bool = false

@export var subviewport: SubViewport;

var offeset_cell: float = 20
var offeset_bridge: float = 10

# 位置-场景 的字典 {Vector2i : Node2D}
var map_scene: Dictionary

var map: Array
var s2s: Dictionary

var cnt: int = 0

func _ready() -> void:
	map = map_position_create.map
	s2s = map_position_create.scene_to_scene
	
	if if_see_all_little_map == true:
		build_all_little_map()
	build_little_map(map_position_create.start_position.x, map_position_create.start_position.y)
	change_this_cell_color(map_position_create.start_position.x, map_position_create.start_position.y)
	
func build_all_little_map():
	for x in map.size():
		for y in map[x].size():
			build_little_map(x,y)

func build_little_map(x: int, y: int):
		if map[x][y] != "void" && !map_scene.has(Vector2i(x,y)):
			build_this_cell(x,y)
			build_this_bridge(x,y)

func show_the_id(cell_scene):
	cell_scene.get_node("Label").text = str(cnt)
	cnt = cnt + 1
	return cell_scene

# 建立房间
func build_this_cell(x: int, y: int):
	var cell = load(cell_pic)
	var cell_scene = cell.instantiate()
	cell_scene.position = Vector2(y * offeset_cell, x * offeset_cell)
	map_scene[Vector2i(x,y)] = cell_scene
	
	if if_show_the_scene == true:
		cell_scene = show_the_id(cell_scene)
	
	add_child(cell_scene)

# 连接房间
func build_this_bridge(x: int, y: int):
	var cell_position = Vector2(y * offeset_cell, x * offeset_cell)
	
	if !s2s.has(Vector2i(x,y)):
		return
	
	for i in range(4):
		if s2s[Vector2i(x,y)][i] == 1:
			var bridge = load(bridge_pic)
			var bridge_scene = bridge.instantiate()
			match i:
				0: bridge_scene.position = Vector2(cell_position.x , cell_position.y - offeset_bridge) # 上
				1: bridge_scene.position = Vector2(cell_position.x + offeset_bridge , cell_position.y) # 右
				2: bridge_scene.position = Vector2(cell_position.x , cell_position.y + offeset_bridge) # 下
				3: bridge_scene.position = Vector2(cell_position.x - offeset_bridge , cell_position.y) # 左
			add_child(bridge_scene)

# 改变场景颜色 与 修改小地图渲染中心
func change_this_cell_color(x: int, y: int):
	if map_scene.has(Vector2i(x,y)):
		map_scene[Vector2i(x,y)].get_node("Cell").self_modulate = Color.RED
	
	#修改小地图渲染中心
	if subviewport:
		subviewport.camera_node.global_position = map_scene[Vector2i(x,y)].global_position

# 恢复场景颜色
func return_this_cell_color(x: int, y: int):
	if map_scene.has(Vector2i(x,y)):
		map_scene[Vector2i(x,y)].get_node("Cell").self_modulate = Color.WHITE
