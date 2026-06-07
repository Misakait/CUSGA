extends Node2D

@onready var map_instantiator = $"../MapInstantiator"
@onready var map_position_create =  $"../MapPositionCreate"
@onready var map_little = $"../MapLittle"
@onready var passage_guard_controller = $"../PassageGuardController"
@onready var screen_transitions = get_node_or_null("/root/ScreenTransitions")
@onready var time_system = get_node_or_null("/root/TimeSystem")

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

#储存每个场景的button
var scene_button: Dictionary

func _ready() -> void:
	current_position = map_position_create.start_position
	if passage_guard_controller != null and passage_guard_controller.has_signal(&"guard_state_changed"):
		passage_guard_controller.connect(&"guard_state_changed", Callable(self, "_on_guard_state_changed"))
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

#上按钮
func _on_up_button_pressed() -> void:
	await _try_move_to(_target_for_direction(0))

#右按钮
func _on_right_button_pressed() -> void:
	await _try_move_to(_target_for_direction(1))

#下按钮
func _on_down_button_pressed() -> void:
	await _try_move_to(_target_for_direction(2))

#左按钮
func _on_left_button_pressed() -> void:
	await _try_move_to(_target_for_direction(3))

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
