extends Area2D

@export var target_scene: String
@export var target_scene_id: String

## 目标房间里的出生门节点名，例如从南边进入时应从 "UpDoor" 出生。
@export var target_door_id: String

## 触发冷却（秒）。两次传送之间的最短间隔，防止玩家在传送点反复横跳。
@export var cool_down_time: float = 1.0

## 冷却计时结束后是否补一次传送。玩家在冷却期内碰到门时置位。
var ready_to_change: bool = false

## 触发传送的玩家节点。
var player: Node2D

## 剩余冷却时间。
var cool_down_timer: float = 0.0

## 出生点偏移节点；玩家从本门对应的反方向进入房间时，会被放在本门坐标加上该偏移处。
var offset_node: Node2D
var offset: Vector2

## 执行换房的控制器；由 DoorController 在进入房间时注入，避免门反向查找自己的父节点。
var controller: Node = null


## 缓存出生点偏移，并把 body 进入/离开事件连接到传送回调。
func _ready() -> void:
	if get_child_count() >= 2:
		offset_node = get_children()[1]
		offset = offset_node.position
	else:
		offset = Vector2(0, 0)

	cool_down_timer = cool_down_time
	ready_to_change = false

	_connect_signal_once(body_entered, _on_body_entered)
	_connect_signal_once(body_exited, _on_body_exited)


## 仅在尚未连接时建立信号连接。
func _connect_signal_once(target_signal: Signal, handler: Callable) -> void:
	if target_signal.is_connected(handler):
		return

	target_signal.connect(handler)


## 递减冷却；冷却归零时补一次因冷却而被推迟的传送。
func _physics_process(delta: float) -> void:
	cool_down_timer = max(cool_down_timer - delta, 0)
	if ready_to_change and cool_down_timer == 0:
		ready_to_change = false
		_try_change_room(player)


## 玩家进入门范围时的入口。
func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group(&"Player"):
		return

	if cool_down_time > 0.0 and cool_down_timer > 0:
		# 冷却期内碰到门：不立即传送，先记账，等计时归零后补一次。
		ready_to_change = true
		player = body
		return

	_try_change_room(body)


## 重新开始本门的冷却计时。
##
## 为什么必须由 DoorController 在每次传送后调用：
## 本门的冷却只在 _ready 里初始化一次，之后 cool_down_timer 会停在 0 永不回升。
## 不主动重置的话，冷却只能拦住门被创建后的头 1 秒，挡不住玩家在传送点上反复横跳。
func reset_cool_down() -> void:
	cool_down_timer = cool_down_time
	ready_to_change = false

## 玩家离开门范围时清除待触发状态。
func _on_body_exited(_body: Node2D) -> void:
	ready_to_change = false

## 把换房请求转交给控制器；控制器缺失时明确报错而不是静默失败。
func _try_change_room(body: Node2D) -> void:
	if body == null or not is_instance_valid(body):
		return

	if controller == null or not is_instance_valid(controller):
		push_error("门 %s 未注入 DoorController，无法切换房间。" % name)
		return

	if not controller.has_method(&"OnDoorBodyEntered"):
		push_error("门 %s 的控制器缺少 OnDoorBodyEntered 入口。" % name)
		return

	controller.call(&"OnDoorBodyEntered", self, body)
