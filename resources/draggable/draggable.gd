extends Resource
class_name Draggable

@export var drag_speed: int = 1

var dragging := false
var drag_offset := Vector2.ZERO

func handle_event(event: InputEvent, target_node) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			dragging = true
			drag_offset = event.position - target_node.position
		else:
			dragging = false
	
	if event is InputEventMouseMotion and dragging:
		target_node.position = event.position - drag_offset
