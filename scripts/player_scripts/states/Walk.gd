extends State
class_name Walk_

var if_trans = false

func enter() -> void:
	player.anim_state.travel("walk")
	if_trans = false

func physics_update(_delta: float) -> void:
	if_trans = check_trans_condition()
	if if_trans:
		return
	
	player.move_player(_delta)
	player.move_and_slide()

func check_trans_condition() -> bool:
	if Input.get_axis("move_left", "move_right") == 0 and Input.get_axis("move_up","move_down") == 0:
		transition_to("Idle")
		return true

	return false
