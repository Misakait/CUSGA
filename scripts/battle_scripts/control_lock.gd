extends Node2D
class_name ControlLock

@onready var CardManager = $"../CardManager"

@export var is_lock:bool = false

func lock():
	is_lock = true
	$"../Button/TurnEnd".disabled = true
	$"../Button/DrawCard".disabled = true
	for child in CardManager.get_children():
		if child is SkillCard:
			child.lock()
	
func unlock():
	is_lock = false
	$"../Button/TurnEnd".disabled = false
	$"../Button/DrawCard".disabled = false
	for child in CardManager.get_children():
		if child is SkillCard:
			child.unlock()
