extends SceneTree

const PassageGuardControllerScript: GDScript = preload("res://scripts/map_scripts/passage_guard_controller.gd")
const MapButtonScript: GDScript = preload("res://scripts/map_scripts/map_button/map_button.gd")
const TagComponentScript: CSharpScript = preload("res://entities/components/TagComponent.cs")

var _failures: Array[String] = []


class FakeMapPositionCreate:
	extends Node

	var map: Array = [["forest"]]
	var scene_to_scene: Dictionary = {}


class FakeMapTypes:
	extends Node

	var attribute: map_attribute

	func from_name_get_attribute(scene_name: String) -> map_attribute:
		if scene_name == "forest":
			return attribute
		return null


class FakeWorldInteractionCoordinator:
	extends Node

	signal PassageGuardEncounterFinished(is_victory: bool)

	var request_count: int = 0
	var next_result: bool = true

	func RequestPassageGuardEncounter(monsters: Array) -> void:
		request_count += 1
		emit_signal(&"PassageGuardEncounterFinished", next_result)


class FakeMapControl:
	extends Node

	var player: Node


class FakeEquipmentComponent:
	extends Node

	var encounter_multiplier: float = 1.0

	func GetNightEncounterChanceMultiplier() -> float:
		return encounter_multiplier


class FakeScreenTransitions:
	extends Node

	signal fade_complete

	func fade_out() -> void:
		emit_signal.call_deferred(&"fade_complete")


class FakeMapLittle:
	extends Node

	func build_little_map(_x: int, _y: int) -> void:
		pass

	func change_this_cell_color(_x: int, _y: int) -> void:
		pass

	func return_this_cell_color(_x: int, _y: int) -> void:
		pass


class FakeMapInstantiator:
	extends Node

	var call_log: Array[String]
	var current_scene: Node2D

	func load_scene_at(_position: Vector2i) -> void:
		call_log.append("load")


class FakeTimeSystem:
	extends Node

	var call_log: Array[String]

	func PassMapMoveTime() -> void:
		call_log.append("time")


func _init() -> void:
	call_deferred(&"_run")


func _run() -> void:
	await _test_guard_battle_handles_synchronous_result_signal()
	await _test_map_move_time_is_settled_before_loading_target_room()
	await _test_background_resolver_uses_map_instantiator_current_scene()
	_test_passage_guard_state_treats_edges_as_undirected()
	_test_passage_guard_probability_applies_modifiers()
	_test_torch_multiplier_reduces_night_guard_rolls()
	_test_torch_multiplier_keeps_default_guard_rolls()
	_test_passage_guard_monster_resolver_keeps_visible_room_encounter_stable()

	if _failures.is_empty():
		print("All passage guard Godot tests passed.")
		quit(0)
		return

	for failure in _failures:
		push_error(failure)
	quit(1)


func _test_guard_battle_handles_synchronous_result_signal() -> void:
	var harness := _create_guard_battle_harness(true)
	var controller: Node = harness["controller"]
	var coordinator: Node = harness["coordinator"]
	var from := Vector2i(0, 0)
	var to := Vector2i(1, 0)
	var completion := {"done": false, "result": false}

	controller._state.AddGuard(from, to)
	Callable(self, &"_capture_guard_battle_result").call_deferred(controller, from, to, completion)
	await create_timer(0.05).timeout

	_assert(bool(completion["done"]), "同步发出战斗结果信号时，request_guard_battle 必须完成，不能永久等待。")
	_assert(bool(completion["result"]), "同步胜利结果应当向按钮流程返回 true。")
	_assert(int(coordinator.request_count) == 1, "驻守战斗请求应当只触发一次。")

	harness["root"].queue_free()
	await process_frame


func _capture_guard_battle_result(controller: Node, from: Vector2i, to: Vector2i, completion: Dictionary) -> void:
	completion["result"] = await controller.request_guard_battle(from, to)
	completion["done"] = true


func _test_map_move_time_is_settled_before_loading_target_room() -> void:
	var call_log: Array[String] = []
	var map_button: Node = MapButtonScript.new()
	var map_little := FakeMapLittle.new()
	var map_instantiator := FakeMapInstantiator.new()
	var time_system := FakeTimeSystem.new()
	var screen_transitions := FakeScreenTransitions.new()
	map_button.map_little = map_little
	map_button.map_instantiator = map_instantiator
	map_button.map_instantiator.call_log = call_log
	map_button.time_system = time_system
	map_button.time_system.call_log = call_log
	map_button.screen_transitions = screen_transitions
	map_button.current_position = Vector2i(1, 1)

	await map_button._move_to(Vector2i(1, 2))

	_assert(call_log == ["time", "load"], "地图移动应当先结算耗时，再加载目标房间，避免目标房间按旧昼夜状态初始化。")
	map_button.call_deferred(&"free")
	map_little.call_deferred(&"free")
	map_instantiator.call_deferred(&"free")
	time_system.call_deferred(&"free")
	screen_transitions.call_deferred(&"free")
	await process_frame


func _test_background_resolver_uses_map_instantiator_current_scene() -> void:
	var map_system := Node.new()
	var map_instantiator := FakeMapInstantiator.new()
	map_instantiator.name = "MapInstantiator"
	map_instantiator.call_log = []
	map_system.add_child(map_instantiator)
	var desert := _create_room_with_background("Desert", Color(1, 0, 0, 1))
	var forest := _create_room_with_background("Forest", Color(0, 1, 0, 1))
	map_instantiator.add_child(desert)
	map_instantiator.add_child(forest)
	map_instantiator.current_scene = forest
	var resolver := CurrentMapBackgroundResolver.new()

	var duplicated: Sprite2D = resolver.DuplicateCurrentBackground(map_system)

	_assert(duplicated != null, "战斗背景解析器应当能复制当前地图背景。")
	_assert(duplicated.name == "MapBackground", "复制到战斗场景的背景节点应当使用稳定名称。")
	_assert(duplicated.modulate == Color(0, 1, 0, 1), "战斗背景必须来自 MapInstantiator.current_scene，而不是第一个缓存子节点。")

	duplicated.free()
	map_system.queue_free()
	await process_frame


func _test_passage_guard_state_treats_edges_as_undirected() -> void:
	var state := PassageGuardState.new()
	var home := Vector2i(1, 1)
	var forest := Vector2i(1, 2)

	state.AddGuard(home, forest)

	_assert(state.IsGuarded(home, forest), "驻守边应当能按原方向查询。")
	_assert(state.IsGuarded(forest, home), "驻守边应当能按反方向查询。")


func _test_passage_guard_probability_applies_modifiers() -> void:
	var settings := PassageGuardSettings.new()
	settings.BaseGuardChance = 0.3
	settings.ProbabilityModifiers.append(_create_modifier(&"quiet_night", 0.1, 1.0))
	settings.ProbabilityModifiers.append(_create_modifier(&"guard_discount", 0.0, 0.5))
	settings.ProbabilityModifiers.append(_create_modifier(&"inactive", 0.6, 10.0))
	var tags: Node = TagComponentScript.new()
	tags.AddTag(&"quiet_night")
	tags.AddTag(&"guard_discount")
	var provider := PassageGuardProbabilityProvider.new()

	var final_chance := provider.Calculate(settings, tags)

	_assert(abs(final_chance - 0.2) < 0.001, "驻守概率应当先加法修正再乘法修正，并忽略未拥有的标签。")
	tags.free()


func _test_torch_multiplier_reduces_night_guard_rolls() -> void:
	var harness := _create_guard_roll_harness(0.0)
	var controller: Node = harness["controller"]
	var from := Vector2i(0, 0)
	var to := Vector2i(0, 1)

	controller._roll_night_guards()

	_assert(not controller.is_guarded(from, to), "携带火把时，夜晚通道驻守生成概率应当被装备乘数降低。")
	harness["root"].queue_free()
	await process_frame


func _test_torch_multiplier_keeps_default_guard_rolls() -> void:
	var harness := _create_guard_roll_harness(1.0)
	var controller: Node = harness["controller"]
	var from := Vector2i(0, 0)
	var to := Vector2i(0, 1)

	controller._roll_night_guards()

	_assert(controller.is_guarded(from, to), "没有装备遭遇修正时，夜晚通道驻守生成应当保持原始概率。")
	harness["root"].queue_free()
	await process_frame


func _test_passage_guard_monster_resolver_keeps_visible_room_encounter_stable() -> void:
	var monster := MonsterData.new()
	monster.MonsterName = "木精"
	var pool: Array[PassageGuardEncounterData] = [_create_encounter(monster)]
	var resolver := PassageGuardMonsterResolver.new()
	var from := Vector2i(3, 3)
	var to := Vector2i(3, 4)

	var first_resolve: Array = resolver.Resolve(from, to, pool)
	var second_resolve: Array = resolver.Resolve(from, to, pool)

	_assert(is_same(first_resolve, second_resolve), "同一房间内同一个驻守按钮应当复用同一组怪物。")
	_assert(first_resolve.size() == 1, "解析出的 encounter 应当保留配置的怪物数量。")
	_assert(first_resolve[0].MonsterName == "木精", "解析出的 encounter 应当保留配置的怪物数据。")


func _create_guard_battle_harness(is_victory: bool) -> Dictionary:
	var root := Node.new()
	root.name = "PassageGuardTestHarness"
	get_root().add_child(root)

	var map_position_create := FakeMapPositionCreate.new()
	map_position_create.name = "MapPositionCreate"
	root.add_child(map_position_create)

	var monster := MonsterData.new()
	monster.MonsterName = "驻守测试怪"
	var map_attr := map_attribute.new()
	map_attr.scene_name = "forest"
	map_attr.guard_encounter_pool.append(_create_encounter(monster))
	var map_types := FakeMapTypes.new()
	map_types.name = "MapTypes"
	map_types.attribute = map_attr
	root.add_child(map_types)

	var coordinator := FakeWorldInteractionCoordinator.new()
	coordinator.name = "WorldInteractionCoordinator"
	coordinator.next_result = is_victory
	root.add_child(coordinator)

	var controller: Node = PassageGuardControllerScript.new()
	controller.name = "PassageGuardController"
	controller.map_position_create_path = ^"../MapPositionCreate"
	controller.map_types_path = ^"../MapTypes"
	controller.world_interaction_coordinator_path = ^"../WorldInteractionCoordinator"
	root.add_child(controller)

	return {
		"root": root,
		"controller": controller,
		"coordinator": coordinator,
	}


func _create_guard_roll_harness(encounter_multiplier: float) -> Dictionary:
	var root := FakeMapControl.new()
	root.name = "PassageGuardRollHarness"
	get_root().add_child(root)

	var map_position_create := FakeMapPositionCreate.new()
	map_position_create.name = "MapPositionCreate"
	map_position_create.map = [["forest", "forest"]]
	map_position_create.scene_to_scene = {
		Vector2i(0, 0): [0, 1, 0, 0],
		Vector2i(0, 1): [0, 0, 0, 1],
	}
	root.add_child(map_position_create)

	var map_types := FakeMapTypes.new()
	map_types.name = "MapTypes"
	map_types.attribute = map_attribute.new()
	map_types.attribute.scene_name = "forest"
	root.add_child(map_types)

	var player := Node.new()
	player.name = "Player"
	var components := Node.new()
	components.name = "Components"
	player.add_child(components)
	var tags: Node = TagComponentScript.new()
	tags.name = "TagComponent"
	components.add_child(tags)
	var equipment := FakeEquipmentComponent.new()
	equipment.name = "EquipmentComponent"
	equipment.encounter_multiplier = encounter_multiplier
	components.add_child(equipment)
	root.player = player
	root.add_child(player)

	var controller: Node = PassageGuardControllerScript.new()
	controller.name = "PassageGuardController"
	controller.settings = PassageGuardSettings.new()
	controller.settings.BaseGuardChance = 1.0
	controller.map_position_create_path = ^"../MapPositionCreate"
	controller.map_types_path = ^"../MapTypes"
	root.add_child(controller)

	return {
		"root": root,
		"controller": controller,
	}


func _create_modifier(required_tag: StringName, additive_chance: float, multiplier: float) -> PassageGuardProbabilityModifier:
	var modifier := PassageGuardProbabilityModifier.new()
	modifier.RequiredTag = required_tag
	modifier.AdditiveChance = additive_chance
	modifier.Multiplier = multiplier
	return modifier


func _create_encounter(monster: MonsterData) -> PassageGuardEncounterData:
	var encounter := PassageGuardEncounterData.new()
	encounter.Monsters.append(monster)
	return encounter


func _create_room_with_background(room_name: String, background_color: Color) -> Node2D:
	var room := Node2D.new()
	room.name = room_name
	var background := Sprite2D.new()
	background.name = "Background"
	background.modulate = background_color
	room.add_child(background)
	return room


func _assert(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
