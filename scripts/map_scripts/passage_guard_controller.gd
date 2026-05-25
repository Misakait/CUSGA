extends Node

signal guard_state_changed

@export var settings: PassageGuardSettings
@export var map_position_create_path: NodePath = ^"../MapPositionCreate"
@export var map_types_path: NodePath = ^"../MapTypes"
@export var world_interaction_coordinator_path: NodePath = ^"../../Gameplay/WorldInteractionCoordinator"

const DIR_OFFSETS: Array[Vector2i] = [
	Vector2i(-1, 0),
	Vector2i(0, 1),
	Vector2i(1, 0),
	Vector2i(0, -1),
]

var _state: PassageGuardState = PassageGuardState.new()
var _probability_provider: PassageGuardProbabilityProvider = PassageGuardProbabilityProvider.new()
var _monster_resolver: PassageGuardMonsterResolver = PassageGuardMonsterResolver.new()
var _current_room_position: Vector2i = Vector2i(-999999, -999999)

@onready var _map_position_create: Node = get_node_or_null(map_position_create_path)
@onready var _map_types: Node = get_node_or_null(map_types_path)
@onready var _world_interaction_coordinator: Node = get_node_or_null(world_interaction_coordinator_path)

func _ready() -> void:
	if settings == null:
		settings = PassageGuardSettings.new()

	var time_system := get_node_or_null("/root/TimeSystem")
	if time_system != null and time_system.has_signal(&"DayNightToggled"):
		time_system.connect(&"DayNightToggled", Callable(self, "_on_day_night_toggled"))
		if bool(time_system.get("IsNight")):
			_roll_night_guards()

func _exit_tree() -> void:
	var time_system := get_node_or_null("/root/TimeSystem")
	if time_system != null and time_system.has_signal(&"DayNightToggled"):
		var callable := Callable(self, "_on_day_night_toggled")
		if time_system.is_connected(&"DayNightToggled", callable):
			time_system.disconnect(&"DayNightToggled", callable)

func begin_room(position: Vector2i) -> void:
	if _current_room_position == position:
		return

	_current_room_position = position
	_monster_resolver.BeginRoom()

func is_guarded(from: Vector2i, to: Vector2i) -> bool:
	return _state.IsGuarded(from, to)

func get_guard_encounter(from: Vector2i, to: Vector2i) -> Array:
	if not is_guarded(from, to):
		return []

	var pool := _get_guard_pool_for_position(from)
	return _monster_resolver.Resolve(from, to, pool)

func request_guard_battle(from: Vector2i, to: Vector2i) -> bool:
	if not is_guarded(from, to):
		return true

	var monsters := get_guard_encounter(from, to)
	if monsters.is_empty():
		push_warning("通道被标记为驻守，但当前地图类型没有配置驻守怪物池，已放行。")
		_state.ClearGuard(from, to)
		emit_signal(&"guard_state_changed")
		return true

	if _world_interaction_coordinator == null:
		push_error("PassageGuardController 未找到 WorldInteractionCoordinator，无法进入驻守战斗。")
		return false

	var is_victory := await _request_guard_encounter_and_wait(monsters)
	if is_victory:
		_state.ClearGuard(from, to)
		emit_signal(&"guard_state_changed")

	return is_victory

func _on_day_night_toggled(is_night: bool) -> void:
	if is_night:
		_roll_night_guards()
	else:
		_state.ClearAll()
		_monster_resolver.BeginRoom()
		emit_signal(&"guard_state_changed")

func _roll_night_guards() -> void:
	_state.ClearAll()
	_monster_resolver.BeginRoom()

	if _map_position_create == null:
		push_error("PassageGuardController 未绑定 MapPositionCreate。")
		return

	var tag_component := _get_player_tag_component()
	var guard_chance: float = _probability_provider.Calculate(settings, tag_component)
	guard_chance *= _get_player_night_encounter_chance_multiplier()
	var scene_to_scene: Dictionary = _map_position_create.scene_to_scene
	for from in scene_to_scene.keys():
		var connections: Array = scene_to_scene[from]
		for direction in range(DIR_OFFSETS.size()):
			if direction >= connections.size() or int(connections[direction]) != 1:
				continue

			var to: Vector2i = from + DIR_OFFSETS[direction]
			if not _is_canonical_edge(from, to):
				continue
			if _should_skip_home_edge(from, to, tag_component):
				continue
			if randf() <= guard_chance:
				_state.AddGuard(from, to)

	emit_signal(&"guard_state_changed")

func _should_skip_home_edge(from: Vector2i, to: Vector2i, tag_component: Node) -> bool:
	if settings == null or str(settings.HomeProtectionTag).is_empty():
		return false
	if tag_component == null or not tag_component.HasTag(settings.HomeProtectionTag):
		return false

	return _is_home_position(from) or _is_home_position(to)

func _is_home_position(position: Vector2i) -> bool:
	if _map_position_create == null:
		return false

	var map_grid: Array = _map_position_create.map
	if position.x < 0 or position.x >= map_grid.size():
		return false
	var column: Array = map_grid[position.x]
	if position.y < 0 or position.y >= column.size():
		return false

	return String(column[position.y]) == "home"

func _get_guard_pool_for_position(position: Vector2i) -> Array[PassageGuardEncounterData]:
	if _map_position_create == null or _map_types == null:
		return []

	var map_grid: Array = _map_position_create.map
	if position.x < 0 or position.x >= map_grid.size():
		return []
	var column: Array = map_grid[position.x]
	if position.y < 0 or position.y >= column.size():
		return []

	var map_type_name := String(column[position.y])
	var map_attr: map_attribute = _map_types.from_name_get_attribute(map_type_name)
	if map_attr == null:
		return []

	return map_attr.guard_encounter_pool

func _get_player_tag_component() -> Node:
	var player := _get_player()
	if player == null:
		return null

	return player.get_node_or_null("Components/TagComponent")

func _get_player_night_encounter_chance_multiplier() -> float:
	var player := _get_player()
	if player == null:
		return 1.0

	var equipment_component := player.get_node_or_null("Components/EquipmentComponent")
	if equipment_component == null or not equipment_component.has_method(&"GetNightEncounterChanceMultiplier"):
		return 1.0

	return max(0.0, float(equipment_component.call(&"GetNightEncounterChanceMultiplier")))

func _get_player() -> Node:
	var map_control := get_parent()
	if map_control == null:
		return null
	var player = map_control.get("player")
	if player == null:
		return null

	return player

func _is_canonical_edge(from: Vector2i, to: Vector2i) -> bool:
	if from.x != to.x:
		return from.x < to.x
	return from.y <= to.y

func _request_guard_encounter_and_wait(monsters: Array) -> bool:
	if not _world_interaction_coordinator.has_signal(&"PassageGuardEncounterFinished"):
		push_error("WorldInteractionCoordinator 缺少 PassageGuardEncounterFinished 信号，无法等待驻守战斗结果。")
		return false
	if not _world_interaction_coordinator.has_method(&"RequestPassageGuardEncounter"):
		push_error("WorldInteractionCoordinator 缺少 RequestPassageGuardEncounter 方法，无法进入驻守战斗。")
		return false

	var result := {
		"completed": false,
		"is_victory": false,
	}
	var on_finished := func(is_victory: bool) -> void:
		result["completed"] = true
		result["is_victory"] = is_victory

	# C# 侧在拒绝重复过渡时可能同步发出结果，因此必须先建立一次性连接再发起请求。
	var connect_error := _world_interaction_coordinator.connect(
		&"PassageGuardEncounterFinished",
		on_finished,
		CONNECT_ONE_SHOT
	)
	if connect_error != OK:
		push_error("PassageGuardController 无法连接 PassageGuardEncounterFinished，错误码：%s。" % connect_error)
		return false

	_world_interaction_coordinator.RequestPassageGuardEncounter(monsters)
	while not bool(result["completed"]):
		await get_tree().process_frame

	return bool(result["is_victory"])
