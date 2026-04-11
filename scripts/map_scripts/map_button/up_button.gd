extends  Node2D

@export var h_e_zoom: hover_exit_zoom



#自己连接需要的按钮

func _on_up_button_mouse_entered() -> void:
	if not h_e_zoom.dragging and not h_e_zoom.is_other_card_hovering():
		h_e_zoom.hovering = true
		z_index = 2
		h_e_zoom.animate_scale(h_e_zoom.hover_scale)


func _on_up_button_mouse_exited() -> void:
	if not h_e_zoom.dragging :
		h_e_zoom.hovering = false
		z_index = 1
		h_e_zoom.animate_scale(h_e_zoom.normal_scale)
