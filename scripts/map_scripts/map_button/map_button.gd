extends Node2D

@onready var map_instantiator = $"../MapInstantiator"
@onready var map_position_create =  $"../MapPositionCreate"
@onready var map_little = $"../MapLittle"
@onready var passage_guard_controller = $"../PassageGuardController"
@onready var screen_transitions = get_node_or_null("/root/ScreenTransitions")
@onready var time_system = get_node_or_null("/root/TimeSystem")
# 地图只依赖已验证存在的协调器入口，避免直接绑定其内部长按组件的层级结构。
@onready var world_interaction_coordinator: Node = get_node_or_null("../../Gameplay/WorldInteractionCoordinator")

@export var UpButton:Node2D
@export var RightButton: Node2D
@export var DownButton: Node2D
@export var LeftButton: Node2D

const DIR_OFFSETS: Array[Vector2i] = [
	Vector2i(-1, 0),
	Vector2i(0, 1),
	Vector2i(1, 0),
	Vector2i(0, -1),
]
const NORMAL_LABELS: Array[String] = ["往北走", "往东走", "往南走", "往西走"]
const DIRECTION_ICON_NAMES: Array[String] = ["UpIcon", "RightIcon", "DownIcon", "LeftIcon"]

var current_position: Vector2i
var connect_scene = [0,0,0,0]
var posx: int = 0
var posy: int = 0

# 防止地图淡出、驻守战斗或场景加载尚未结束时重复启动移动流程。
var _is_move_in_progress: bool = false
# 保存当前已开始长按的目标坐标，完成信号只携带 owner 时仍能启动正确方向的移动。
var _pending_move_target: Vector2i = Vector2i.ZERO

#储存每个场景的button
var scene_button: Dictionary

func _ready() -> void:
	current_position = map_position_create.start_position
	if passage_guard_controller != null and passage_guard_controller.has_signal(&"guard_state_changed"):
		passage_guard_controller.connect(&"guard_state_changed", Callable(self, "_on_guard_state_changed"))
	_connect_world_hold_completion()
	update_scene_button(current_position)

func update_scene_button(position: Vector2i):
	if passage_guard_controller != null:
		passage_guard_controller.begin_room(position)

	#更新自身位置
	current_position = position
	posx = position.x
	posy = position.y

	connect_scene = map_position_create.scene_to_scene.get(position, [0,0,0,0])

	#检测相连房间
	for the_scene in range(0,4):
		check_these_button(the_scene)

func check_these_button(the_scene: int):
	var button := _button_for_direction(the_scene)
	if button == null:
		print("如果你看到这个，那就说明map_button节点出问题了")
		return

	button.visible = the_scene < connect_scene.size() and int(connect_scene[the_scene]) == 1
	if button.visible:
		_apply_passage_button_state(the_scene)

func _on_guard_state_changed() -> void:
	update_scene_button(current_position)

#上方向按钮开始长按。
func _on_up_button_button_down() -> void:
	_begin_move_hold(0)

#右方向按钮开始长按。
func _on_right_button_button_down() -> void:
	_begin_move_hold(1)

#下方向按钮开始长按。
func _on_down_button_button_down() -> void:
	_begin_move_hold(2)

#左方向按钮开始长按。
func _on_left_button_button_down() -> void:
	_begin_move_hold(3)

#任意方向按钮松开后取消尚未完成的移动长按。
func _on_direction_button_button_up() -> void:
	_cancel_move_hold()

# 将方向选择转换为统一长按请求；只有进度满后才进入原有移动协程。
func _begin_move_hold(direction: int) -> void:
	if _is_move_in_progress:
		return

	if world_interaction_coordinator == null or not world_interaction_coordinator.has_method("BeginWorldHoldForMap"):
		push_error("MapButton 未找到 WorldInteractionCoordinator 的长按入口，无法开始地图移动长按。")
		return

	if time_system == null:
		push_error("MapButton 未找到 TimeSystem，无法计算地图移动长按耗时。")
		return

	# 经 Object.get 跨越 C# 自动加载边界，避免将动态节点误当作静态 GDScript 属性。
	var map_move_time_cost: Variant = time_system.get("MapMoveTimeCost")
	if map_move_time_cost == null:
		push_error("MapButton 无法读取 TimeSystem.MapMoveTimeCost，无法计算地图移动长按耗时。")
		return

	# 地图移动的行动值是长按时长的唯一输入，零消耗会由控制器即时回调。
	var action_point_cost: int = max(0, int(map_move_time_cost))
	# 本次长按完成后仍应前往同一方向，因此在开始时快照目标坐标。
	var target_position: Vector2i = _target_for_direction(direction)
	_pending_move_target = target_position
	# 传递实际可见的方向按钮精灵，避免 HUD 锚定到地图脚本根节点。
	var hold_progress_target: Node = _hold_progress_target_for_direction(direction)
	# 地图完成事件仅跨越 owner，避免 GDScript Callable 经动态 C# 调用丢失实例。
	world_interaction_coordinator.call("BeginWorldHoldForMap", self, action_point_cost, hold_progress_target)

# 连接 C# 协调器发出的长按完成信号；必须早于按钮按下，才能接收零耗时的同步完成。
func _connect_world_hold_completion() -> void:
	if world_interaction_coordinator == null or not world_interaction_coordinator.has_signal(&"WorldHoldCompleted"):
		push_error("MapButton 未找到 WorldInteractionCoordinator.WorldHoldCompleted 信号，无法响应地图长按完成。")
		return

	# 该 Callable 只用于信号连接，不再作为参数跨越 Object.call 传入 C#。
	var completion_callable: Callable = Callable(self, "_on_world_hold_completed")
	if not world_interaction_coordinator.is_connected(&"WorldHoldCompleted", completion_callable):
		world_interaction_coordinator.connect(&"WorldHoldCompleted", completion_callable)

# 只处理本地图按钮拥有的长按完成事件，随后启动保留的原有移动协程。
func _on_world_hold_completed(owner: Node) -> void:
	if owner != self or _is_move_in_progress:
		return

	await _complete_move_hold(_pending_move_target)

# 仅由统一长按控制器在完成时调用，避免短按提前执行场景切换。
func _complete_move_hold(target_position: Vector2i) -> void:
	if _is_move_in_progress:
		return

	_is_move_in_progress = true
	await _try_move_to(target_position)
	_is_move_in_progress = false

# 只取消本地图按钮发起的请求，不影响棋盘卡牌等其他潜在交互拥有者。
func _cancel_move_hold() -> void:
	if world_interaction_coordinator != null and world_interaction_coordinator.has_method("CancelWorldHoldFor"):
		world_interaction_coordinator.call("CancelWorldHoldFor", self)

# 场景卸载时必须撤销尚未完成的回调，避免旧地图节点在新场景后继续移动。
func _exit_tree() -> void:
	_cancel_move_hold()
	if world_interaction_coordinator != null and world_interaction_coordinator.has_signal(&"WorldHoldCompleted"):
		# 连接由本节点创建，离开场景时主动断开以避免旧地图接收新场景事件。
		var completion_callable: Callable = Callable(self, "_on_world_hold_completed")
		if world_interaction_coordinator.is_connected(&"WorldHoldCompleted", completion_callable):
			world_interaction_coordinator.disconnect(&"WorldHoldCompleted", completion_callable)

func _try_move_to(target_position: Vector2i) -> void:
	if passage_guard_controller != null and passage_guard_controller.is_guarded(current_position, target_position):
		var is_victory: bool = await passage_guard_controller.request_guard_battle(current_position, target_position)
		if not is_victory:
			update_scene_button(current_position)
			return

	await _move_to(target_position)

func _move_to(target_position: Vector2i) -> void:
	var previous_position := current_position
	map_little.build_little_map(target_position.x, target_position.y)
	map_little.change_this_cell_color(target_position.x, target_position.y)
	map_little.return_this_cell_color(previous_position.x, previous_position.y)

	if screen_transitions == null:
		push_error("MapButton 未找到 ScreenTransitions，无法切换地图。")
		return

	screen_transitions.fade_out()
	await screen_transitions.fade_complete

	_pass_map_move_time()
	# 注意：load_scene_at 会改变当前 posx 与 posy；先结算耗时，保证目标房间按最新昼夜状态初始化。
	map_instantiator.load_scene_at(target_position)

func _apply_passage_button_state(direction: int) -> void:
	var button := _button_for_direction(direction)
	if button == null:
		return

	var target := _target_for_direction(direction)
	var is_guarded: bool = passage_guard_controller != null and passage_guard_controller.is_guarded(current_position, target)
	if not is_guarded:
		_set_button_label(button, NORMAL_LABELS[direction])
		_set_direction_icon_visible(button, direction, true)
		return

	var monsters: Array = passage_guard_controller.get_guard_encounter(current_position, target)
	var label := _format_monster_names(monsters)
	if label.is_empty():
		label = "驻守怪物"

	_set_button_label(button, label)
	_set_direction_icon_visible(button, direction, false)

func _target_for_direction(direction: int) -> Vector2i:
	return current_position + DIR_OFFSETS[direction]

func _button_for_direction(direction: int) -> Node2D:
	match direction:
		0:
			return UpButton
		1:
			return RightButton
		2:
			return DownButton
		3:
			return LeftButton
		_:
			return null

# 返回方向容器内的可见精灵，使全局 HUD 能绘制在真实目标右下角。
func _hold_progress_target_for_direction(direction: int) -> Node:
	# 方向容器本身位于地图原点，不能直接作为屏幕位置锚点。
	var direction_button: Node2D = _button_for_direction(direction)
	if direction_button == null:
		return null

	# 只查找直属节点，可避开与精灵同名的嵌套 LinkButton。
	var visible_button_sprite: Node = direction_button.find_child("*Button", false, false)
	return visible_button_sprite

func _set_button_label(button: Node, text: String) -> void:
	var label := button.find_child("Label", true, false)
	if label is Label:
		label.text = text
		return

	var rich_label := button.find_child("RichTextLabel", true, false)
	if rich_label is RichTextLabel:
		rich_label.text = text

func _set_direction_icon_visible(button: Node, direction: int, is_visible: bool) -> void:
	var icon := button.find_child(DIRECTION_ICON_NAMES[direction], true, false)
	if icon is CanvasItem:
		icon.visible = is_visible

func _format_monster_names(monsters: Array) -> String:
	var names := PackedStringArray()
	for monster in monsters:
		if monster == null:
			continue
		var monster_name := String(monster.MonsterName)
		if not monster_name.is_empty():
			names.append(monster_name)

	return "\n".join(names)

func _pass_map_move_time() -> void:
	if time_system == null:
		push_error("MapButton 未找到 TimeSystem，无法结算地图移动耗时。")
		return

	time_system.PassMapMoveTime()
