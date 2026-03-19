extends Node2D

@onready var map_position_create = $"../MapPositionCreate"

@export_dir var cell_pic: String
@export_dir var bridge_pic: String

var offeset_cell: float = 20
var offeset_bridge: float = 10

var cnt: int = 0

# 位置-场景 的字典 {Vector2i : Node2D}
var map_scene: Dictionary

var map: Array
var s2s: Dictionary


func _ready() -> void:
	map = map_position_create.map
	s2s = map_position_create.scene_to_scene
	
	build_little_map()
	change_this_cell_color(1,1)
	
	
func build_little_map():
	for x in map.size():
		for y in map[x].size():
			if map[x][y] != "void":
				build_this_cell(x,y)
				build_this_bridge(x,y)

# 建立房间
func build_this_cell(x: int, y: int):
	var cell = load(cell_pic)
	var cell_scene = cell.instantiate()
	cell_scene.position = Vector2(y * offeset_cell, x * offeset_cell)
	cell_scene.get_node("Label").text = str(cnt)
	cnt += 1
	map_scene[Vector2i(x,y)] = cell_scene
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

# 改变场景颜色
func change_this_cell_color(x: int, y: int):
	if map_scene.has(Vector2i(x,y)):
		map_scene[Vector2i(x,y)].get_node("Cell").self_modulate = Color.RED

# 恢复场景颜色
func return_this_cell_color(x: int, y: int):
	if map_scene.has(Vector2i(x,y)):
		map_scene[Vector2i(x,y)].get_node("Cell").self_modulate = Color.WHITE
