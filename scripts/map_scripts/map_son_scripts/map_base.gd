extends Node2D

class_name map_base

func initialize_scene():
	#print("卧槽，我被初始化了")
	z_index = -1
	child_initialize_scene()
	
func child_initialize_scene():
	pass
