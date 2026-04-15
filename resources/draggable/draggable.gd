extends Resource
class_name Draggable

@export var drag_speed: int = 1

var dragging := false
var drag_offset := Vector2.ZERO

func handle_event(event: InputEvent, target_node) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			dragging = true
			drag_offset = event.global_position - target_node.global_position
		else:
			dragging = false
	
	if event is InputEventMouseMotion and dragging:
		var new_pos = event.global_position - drag_offset
		#print("offeset",drag_offset)
		#print("target_node.position:",target_node.position)
		#print("event.position",event.position)
		# 获取屏幕大小
		var screen_size = target_node.get_viewport().size
		new_pos.x = clamp(new_pos.x, 0, screen_size.x)
		new_pos.y = clamp(new_pos.y, 0, screen_size.y)
		
		target_node.global_position = new_pos
