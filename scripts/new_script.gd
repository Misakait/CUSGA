extends Node2D


func _ready() -> void:
	var arr1 = [0,1,2,3]
	var arr2 = [114]
	arr2.append_array(arr1)
	print(arr2)
