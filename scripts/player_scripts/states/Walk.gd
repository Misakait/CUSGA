extends State
class_name Walk_

var if_trans = false

## 键盘行走接管时清除鼠标目标，确保键盘松开后不会恢复旧指令。
## @return 无返回值。
func enter() -> void:
	var click_walk_state: ClickWalkState = state_machine.states.get("clickwalk") as ClickWalkState
	if click_walk_state != null:
		click_walk_state.CancelMovementRequest()
	player.anim_state.travel("walk")
	if_trans = false

## 检查状态切换后执行本帧键盘移动。
## @param _delta 本次物理帧间隔秒数。
## @return 无返回值。
func physics_update(_delta: float) -> void:
	if_trans = check_trans_condition()
	if if_trans:
		return
	
	player.move_player(_delta)
	player.move_and_slide()

## 松开键盘后因鼠标请求已被接管时清除，所以直接回到空闲状态。
## @return 发生状态切换时返回 true。
func check_trans_condition() -> bool:
	if Input.get_vector("move_left", "move_right", "move_up", "move_down") == Vector2.ZERO:
		var click_walk_state: ClickWalkState = state_machine.states.get("clickwalk") as ClickWalkState
		if click_walk_state != null and click_walk_state.has_movement_request():
			transition_to("ClickWalk")
		else:
			transition_to("Idle")
		return true

	return false
