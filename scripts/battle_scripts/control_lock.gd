extends Node2D

@export var is_lock:bool = false

func lock():
	is_lock = true
	
func unlock():
	is_lock = false
