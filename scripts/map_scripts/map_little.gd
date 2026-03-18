extends Node2D

@onready var map_position_create = $"../MapPositionCreate"

@export_dir var cell_pic: String
@export_dir var bridge_pic: String

var offeset_cell: float = 20
var offeset_bridge: float = 10

var cnt: int = 0

#这个是 位置-场景 的字典，类型为{Vector2i : Node2D}
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

#建立房间
#注意：position的第一个参数是列，第二个参数是行，与x行y列相反
func build_this_cell(y: int, x: int):
	
	var cell = load(cell_pic)
	var cell_scene = cell.instantiate()
	cell_scene.position = Vector2(x * offeset_cell, y * offeset_cell)
	cell_scene.get_node("Label").text = str(cnt)
	cnt+=1
	map_scene[Vector2i(x,y)] = cell_scene
	add_child(cell_scene)

#连接房间
func build_this_bridge(y: int, x: int):
	var bridge = load(bridge_pic)
	var bridge_scene = bridge.instantiate()
	var cell_position = Vector2(x * offeset_cell, y * offeset_cell)
	
	for i in range(0,4):
		
		if s2s[Vector2i(y,x)][i] == 1:
			match i:
				0:
					bridge_scene.position = Vector2(cell_position.x , cell_position.y - offeset_bridge)
				1:
					bridge_scene.position = Vector2(cell_position.x + offeset_bridge , cell_position.y)
				2:
					bridge_scene.position = Vector2(cell_position.x , cell_position.y + offeset_bridge)
				3:
					bridge_scene.position = Vector2(cell_position.x - offeset_bridge , cell_position.y)
				_:
					print("如果你看到这个，就说明有错误发生在map_little这个脚本")
		add_child(bridge_scene)

func change_this_cell_color(y: int,x :int):
	map_scene[Vector2i(x,y)].get_node("Cell").self_modulate = Color.RED
	
func return_this_cell_color(y:int ,x: int):
	map_scene[Vector2i(x,y)].get_node("Cell").self_modulate = Color.WHITE
