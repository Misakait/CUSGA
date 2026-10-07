extends State
class_name ClickWalkState

## PlayerChar 的鼠标移动状态：短按设定目的地，长按期间持续跟随鼠标。

## 按住达到此时长后，从短点输入切换为跟随鼠标。
const LONG_PRESS_THRESHOLD_SECONDS: float = 0.25
## 到达点击目标的世界坐标容差。
const ARRIVAL_TOLERANCE: float = 2.0

var _mouse_button_down: bool = false
var _mouse_pressed_at_usec: int = 0
var _pressed_world_position: Vector2 = Vector2.ZERO
var _target_world_position: Vector2 = Vector2.ZERO
var _has_target: bool = false
var _following_mouse: bool = false
var _world_interaction_active: bool = false


## 进入鼠标移动后播放与键盘行走相同的走路动画。
## @return 无返回值。
func enter() -> void:
	player.anim_state.travel("walk")


## 响应未被 UI 或世界交互消费的左键输入。
## @param event 当前输入事件。
## @return 无返回值。
func _unhandled_input(event: InputEvent) -> void:
	if _world_interaction_active:
		return

	var mouse_event: InputEventMouseButton = event as InputEventMouseButton
	if mouse_event == null or mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return

	if mouse_event.pressed:
		if _mouse_button_down or Input.get_vector("move_left", "move_right", "move_up", "move_down") != Vector2.ZERO:
			return
		_mouse_button_down = true
		_mouse_pressed_at_usec = Time.get_ticks_usec()
		_pressed_world_position = player.get_global_mouse_position()
		_has_target = false
		_following_mouse = false
		return

	if not _mouse_button_down:
		return

	var held_seconds: float = _get_mouse_hold_seconds()
	_mouse_button_down = false
	if held_seconds < LONG_PRESS_THRESHOLD_SECONDS \
		and Input.get_vector("move_left", "move_right", "move_up", "move_down") == Vector2.ZERO:
		_target_world_position = _pressed_world_position
		_has_target = true
	else:
		_following_mouse = false
		_has_target = false


## 根据键盘优先级、点击目标或按住状态移动角色。
## @param delta 本次物理帧间隔秒数。
## @return 无返回值。
func physics_update(delta: float) -> void:
	if Input.get_vector("move_left", "move_right", "move_up", "move_down") != Vector2.ZERO:
		transition_to("Walk")
		return
	if _world_interaction_active:
		_stop_movement()
		transition_to("Idle")
		return

	if _mouse_button_down and not _following_mouse \
		and _get_mouse_hold_seconds() >= LONG_PRESS_THRESHOLD_SECONDS:
		_following_mouse = true
		_has_target = false

	if not _following_mouse and not _has_target:
		_stop_movement()
		transition_to("Idle")
		return

	if delta <= 0.0:
		return

	var destination: Vector2 = player.get_global_mouse_position() \
		if _following_mouse else _target_world_position
	var offset: Vector2 = destination - player.global_position
	var distance: float = offset.length()
	if distance <= ARRIVAL_TOLERANCE:
		if _has_target:
			_has_target = false
			_stop_movement()
			transition_to("Idle")
		else:
			_stop_movement()
		return

	var player_data: PlayerData = player.get("player_data") as PlayerData
	if player_data == null or player_data.walk_speed <= 0.0:
		_has_target = false
		_following_mouse = false
		_stop_movement()
		transition_to("Idle")
		return

	var direction: Vector2 = offset / distance
	var target_velocity: Vector2 = direction * player_data.walk_speed
	var next_velocity: Vector2 = player.velocity.move_toward(
		target_velocity,
		player_data.walk_speed * 12.0 * delta
	)
	if next_velocity.length() * delta >= distance:
		next_velocity = direction * distance / delta
	player.velocity = next_velocity

	var sprite: Sprite2D = player.get("sprite") as Sprite2D
	if sprite != null and direction.x != 0.0:
		sprite.flip_h = direction.x < 0.0
	player.move_and_slide()


## 取消旧鼠标目标并在地形交互期间屏蔽鼠标移动。
## @return 无返回值。
func BeginWorldInteraction() -> void:
	_world_interaction_active = true
	_clear_mouse_request()
	if state_machine != null and state_machine.current_state == self:
		_stop_movement()


## 地形交互结束后解除鼠标移动屏蔽，不恢复旧目标。
## @return 无返回值。
func EndWorldInteraction() -> void:
	_world_interaction_active = false
	_clear_mouse_request()


## 键盘行走接管时取消鼠标移动请求，避免松开按键后继续旧目标。
## @return 无返回值。
func CancelMovementRequest() -> void:
	_clear_mouse_request()


## 判断是否有待执行的鼠标移动请求，供 Idle 与 Walk 状态选择优先级。
## @return 短点目标或已达到长按阈值的按住请求存在时返回 true。
func has_movement_request() -> bool:
	if _world_interaction_active:
		return false
	if _has_target or _following_mouse:
		return true
	return _mouse_button_down and _get_mouse_hold_seconds() >= LONG_PRESS_THRESHOLD_SECONDS


## 获取本次左键按住时长。
## @return 当前按住秒数；鼠标未按下时返回 0。
func _get_mouse_hold_seconds() -> float:
	if not _mouse_button_down:
		return 0.0
	return float(Time.get_ticks_usec() - _mouse_pressed_at_usec) / 1000000.0


## 清除残余速度，避免鼠标松开后角色继续滑动。
## @return 无返回值。
func _stop_movement() -> void:
	player.velocity = Vector2.ZERO
	player.move_and_slide()


## 清空所有鼠标按住状态与待执行目标。
## @return 无返回值。
func _clear_mouse_request() -> void:
	_mouse_button_down = false
	_mouse_pressed_at_usec = 0
	_pressed_world_position = Vector2.ZERO
	_target_world_position = Vector2.ZERO
	_has_target = false
	_following_mouse = false
