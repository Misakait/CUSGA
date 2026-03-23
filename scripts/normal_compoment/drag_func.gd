extends TextureRect

@export var draggable: Draggable

func _gui_input(event):
	if draggable:
		draggable.handle_event(event, self)
	else:
		print("你没有设置draggable")
