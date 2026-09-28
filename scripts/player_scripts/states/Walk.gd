extends State
class_name Walk_

var if_trans = false

## 进入键盘行走状态时播放走路动画。
## @return 无返回值。
func enter() -> void:
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

## 松开键盘后恢复仍有效的鼠标请求，否则回到空闲状态。
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
