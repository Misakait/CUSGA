extends State
class_name Idle_

var if_trans = false

func enter() -> void:
	player.anim_state.travel("idle")
	if_trans = false

func physics_update(_delta: float) -> void:
	if_trans = check_trans_condition()
	if if_trans:
		return
	
	player.move_player(_delta)
	player.move_and_slide()

func check_trans_condition() -> bool:
	if Input.get_vector("move_left","move_right","move_up","move_down") != Vector2(0,0):
		transition_to("Walk")
		return true

	return false
