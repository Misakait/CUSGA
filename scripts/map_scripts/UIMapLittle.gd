extends Node2D

## 小地图 View。
##
## 只负责把地图坐标显示成小地图格子和连线，不创建真实地图房间。

@onready var map_position_create = $"../MapPositionCreate"

@export_dir var cell_pic: String
@export_dir var bridge_pic: String
@export var if_see_all_little_map: bool = false
@export var if_show_the_scene: bool = false
@export var subviewport: SubViewport

var offeset_cell: float = 20
var offeset_bridge: float = 10
var map_scene: Dictionary = {}
var map: Array
var s2s: Dictionary
var cnt: int = 0

func _ready() -> void:
	map = map_position_create.map
	s2s = map_position_create.scene_to_scene
	if if_see_all_little_map:
		_build_all_little_map()
	_build_little_map(map_position_create.start_position.x, map_position_create.start_position.y)
	change_this_cell_color(map_position_create.start_position.x, map_position_create.start_position.y)

func _build_all_little_map() -> void:
	for x in map.size():
		for y in map[x].size():
			_build_little_map(x, y)

func _build_little_map(x: int, y: int) -> void:
	if map[x][y] != "void" and not map_scene.has(Vector2i(x, y)):
		_build_this_cell(x, y)
		_build_this_bridge(x, y)

func _show_the_id(cell_scene):
	cell_scene.get_node("Label").text = str(cnt)
	cnt += 1
	return cell_scene

func _build_this_cell(x: int, y: int) -> void:
	var cell = load(cell_pic)
	var cell_scene = cell.instantiate()
	cell_scene.position = Vector2(y * offeset_cell, x * offeset_cell)
	map_scene[Vector2i(x, y)] = cell_scene
	if if_show_the_scene:
		cell_scene = _show_the_id(cell_scene)
	add_child(cell_scene)

func _build_this_bridge(x: int, y: int) -> void:
	var cell_position = Vector2(y * offeset_cell, x * offeset_cell)
	if not s2s.has(Vector2i(x, y)):
		return
	for i in range(4):
		if s2s[Vector2i(x, y)][i] != 1:
			continue
		var bridge = load(bridge_pic)
		var bridge_scene = bridge.instantiate()
		match i:
			0: bridge_scene.position = Vector2(cell_position.x, cell_position.y - offeset_bridge)
			1: bridge_scene.position = Vector2(cell_position.x + offeset_bridge, cell_position.y)
			2: bridge_scene.position = Vector2(cell_position.x, cell_position.y + offeset_bridge)
			3: bridge_scene.position = Vector2(cell_position.x - offeset_bridge, cell_position.y)
		add_child(bridge_scene)

func _change_this_cell_color(x: int, y: int) -> void:
	if map_scene.has(Vector2i(x, y)):
		map_scene[Vector2i(x, y)].get_node("Cell").self_modulate = Color.RED
	if subviewport:
		subviewport.camera_node.global_position = map_scene[Vector2i(x, y)].global_position

## 兼容旧门和按钮脚本的小地图格子创建入口。
##
## @param x 地图行坐标。
## @param y 地图列坐标。
## @return 无返回值。
func build_little_map(x: int, y: int) -> void:
	_build_little_map(x, y)

## 兼容旧门和按钮脚本的小地图当前格高亮入口。
##
## @param x 地图行坐标。
## @param y 地图列坐标。
## @return 无返回值。
func change_this_cell_color(x: int, y: int) -> void:
	_change_this_cell_color(x, y)

func _return_this_cell_color(x: int, y: int) -> void:
	if map_scene.has(Vector2i(x, y)):
		map_scene[Vector2i(x, y)].get_node("Cell").self_modulate = Color.WHITE

## 兼容旧门和按钮脚本的前一格恢复入口。
##
## @param x 地图行坐标。
## @param y 地图列坐标。
## @return 无返回值。
func return_this_cell_color(x: int, y: int) -> void:
	_return_this_cell_color(x, y)

## 刷新当前地图坐标，并保留已经探索过的小地图格子。
##
## @param room_position 当前地图坐标。
## @return 无返回值。
func update_current_position(room_position: Vector2i) -> void:
	_build_little_map(room_position.x, room_position.y)
	for cell_position_value in map_scene.keys():
		var cell_position := cell_position_value as Vector2i
		_return_this_cell_color(cell_position.x, cell_position.y)
	_change_this_cell_color(room_position.x, room_position.y)
