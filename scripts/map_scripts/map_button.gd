extends Node2D

@onready var map_instantiator = $"../MapInstantiator"
@onready var map_position_create =  $"../MapPositionCreate"

var current_position: Vector2i = Vector2i(1,1)
var connect_scene = [0,0,0,0]
var posx: int = 1
var posy: int = 1

#储存每个场景的button
var scene_button: Dictionary

func _ready() -> void:
	update_scene_button(current_position)
	
func update_scene_button(position: Vector2i):
	
	#画地图
	get_node("Label").text = "你处在" + str(position)
	get_node("Label2").text = ""
	for row in map_position_create.map:
		for col in row:
			get_node("Label2").text += "%-20s" % col 
		get_node("Label2").text += '\n'
	
	#更新自身位置
	current_position = position
	posx = position.x
	posy = position.y
	
	connect_scene = map_position_create.scene_to_scene[position]
	
	#检测相连房间
	for the_scene in range(0,4):
		
		check_these_button(the_scene)
		

func check_these_button(the_scene: int):
	if connect_scene[the_scene] == 0:
		match the_scene:
			0:
				if get_node("UpButton"):
					get_node("UpButton").visible = false
				else:
					print("没有UpButton,去map_button看看吧")
			1:
				if get_node("RightButton"):
					get_node("RightButton").visible = false
				else:
					print("没有RightButton,去map_button看看吧")
			2:
				if get_node("DownButton"):
					get_node("DownButton").visible = false
				else:
					print("没有DownButton,去map_button看看吧")
			3:
				if get_node("LeftButton"):
					get_node("LeftButton").visible = false
				else:
					print("没有LeftButton,去map_button看看吧")
			_:
				print("如果你看到这个，那就说明map_button节点出问题了")
	else:
		match the_scene:
			0:
				if get_node("UpButton"):
					get_node("UpButton").visible = true
				else:
					print("没有UpButton,去map_button看看吧")
			1:
				if get_node("RightButton"):
					get_node("RightButton").visible = true
				else:
					print("没有RightButton,去map_button看看吧")
			2:
				if get_node("DownButton"):
					get_node("DownButton").visible = true
				else:
					print("没有DownButton,去map_button看看吧")
			3:
				if get_node("LeftButton"):
					get_node("LeftButton").visible = true
				else:
					print("没有LeftButton,去map_button看看吧")
			_:
				print("如果你看到这个，那就说明map_button节点出问题了")

#上按钮
func _on_up_button_pressed() -> void:
	print("你点我干什么，我是上")
	map_instantiator.load_scene_at(Vector2i(posx-1 , posy))

#右按钮
func _on_right_button_pressed() -> void:
	print("卧槽，我是右")
	map_instantiator.load_scene_at(Vector2i(posx , posy+1))

#下按钮
func _on_down_button_pressed() -> void:
	print("点我点我，我是下")
	map_instantiator.load_scene_at(Vector2i(posx+1 , posy))

#左按钮
func _on_left_button_pressed() -> void:
	print("我tm的是左啊")
	map_instantiator.load_scene_at(Vector2i(posx , posy-1))
