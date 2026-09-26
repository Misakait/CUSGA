extends SceneTree

const PassageGuardControllerScript: GDScript = preload("res://scripts/map_scripts/passage_guard_controller.gd")
const MapInstantiatorScript: GDScript = preload("res://scripts/map_scripts/map_instantiator.gd")
const MapButtonScript: GDScript = preload("res://scripts/map_scripts/map_button/map_button.gd")
const PassageGuardProbabilityModifierScript: GDScript = preload("res://resources/map/passage_guard_probability_modifier.gd")
const PassageGuardStateScript: GDScript = preload("res://core/map/passage_guard_state.gd")
const PassageGuardProbabilityProviderScript: GDScript = preload("res://core/map/passage_guard_probability_provider.gd")
const PassageGuardMonsterResolverScript: GDScript = preload("res://core/map/passage_guard_monster_resolver.gd")
## 迁移后的怪物数据与驻守遭遇数据 GDScript 载体（C# 全局类已随物理退役删除）。
const MonsterDataScript: GDScript = preload("res://resources/monster/monster_data.gd")
const PassageGuardEncounterDataScript: GDScript = preload("res://resources/map/passage_guard_encounter_data.gd")
const PassageGuardSettingsScript: GDScript = preload("res://resources/map/passage_guard_settings.gd")
const TagComponentScript: GDScript = preload("res://entities/components/tag_component.gd")
const CurrentMapBackgroundResolverScript: GDScript = preload("res://core/gameflow/current_map_background_resolver.gd")

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


class FakeWorldHoldCoordinator:
	extends Node

	signal WorldHoldCompleted(owner: Node)

	# 记录地图是否把长按请求交给稳定的协调器边界。
	var begin_hold_count: int = 0
	# 保存开始时快照的行动值，以验证长按时长输入没有被地图脚本丢失。
	var received_action_point_cost: int = -1
	# 保存地图传入的可见方向按钮，验证圆环不会错误锚定地图脚本根节点。
	var received_progress_target: Node
	# 记录松开按钮是否会走同一协调器的取消出口。
	var cancel_hold_count: int = 0

	func BeginWorldHoldForMap(_owner: Node, action_point_cost: int, progress_target: Node) -> void:
		begin_hold_count += 1
		received_action_point_cost = action_point_cost
		received_progress_target = progress_target

	func CancelWorldHoldFor(_owner: Node) -> void:
		cancel_hold_count += 1


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

	# 模拟 C# 自动加载对地图脚本暴露的移动行动值属性。
	var MapMoveTimeCost: int = 10
	# 记录实际移动完成后结算行动值的原有调用顺序。
	var call_log: Array[String]

	func PassMapMoveTime() -> void:
		call_log.append("time")


func _init() -> void:
	call_deferred(&"_run")


func _run() -> void:
	await _test_guard_battle_handles_synchronous_result_signal()
	_test_map_move_hold_routes_through_world_interaction_coordinator()
	await _test_map_move_hold_completion_signal_starts_move()
	await _test_map_move_time_is_settled_before_loading_target_room()
	_test_map_instantiator_keeps_room_sprite_colors_untouched()
	await _test_background_resolver_uses_map_instantiator_current_scene()
	await _test_shop_room_background_uses_standard_background_contract()
	_test_passage_guard_state_treats_edges_as_undirected()
	_test_passage_guard_probability_applies_modifiers()
	_test_passage_guard_probability_accepts_gdscript_modifier()
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


func _test_map_move_hold_routes_through_world_interaction_coordinator() -> void:
	# 地图按钮实例只验证跨语言桥接；移动协程仍由既有独立测试覆盖。
	var map_button: Node = MapButtonScript.new()
	# 该假协调器模拟 Main 场景中已验证的局外交互入口。
	var coordinator := FakeWorldHoldCoordinator.new()
	# 该假自动加载提供地图移动的默认十点行动值。
	var time_system := FakeTimeSystem.new()
	map_button.world_interaction_coordinator = coordinator
	map_button.time_system = time_system
	map_button.current_position = Vector2i(1, 1)
	# 模拟场景中方向容器及其直属可见精灵，让锚点选择逻辑走真实路径。
	var right_direction_button: Node2D = Node2D.new()
	# 精灵位置用于与地图根节点区分，避免测试在错误锚点下仍然通过。
	var right_button_sprite: Sprite2D = Sprite2D.new()
	right_direction_button.add_child(right_button_sprite)
	map_button.add_child(right_direction_button)
	map_button.RightButton = right_direction_button

	map_button._begin_move_hold(1)

	_assert(coordinator.begin_hold_count == 1, "地图方向按下必须经由 WorldInteractionCoordinator 开始长按。")
	_assert(coordinator.received_action_point_cost == 10, "地图长按必须读取 MapMoveTimeCost 作为行动值快照。")
	_assert(coordinator.received_progress_target == right_button_sprite, "地图长按必须传递实际可见的方向按钮作为圆环锚点。")

	map_button._cancel_move_hold()

	_assert(coordinator.cancel_hold_count == 1, "地图方向松开必须经由 WorldInteractionCoordinator 取消长按。")
	map_button.free()
	coordinator.free()
	time_system.free()


func _test_map_move_hold_completion_signal_starts_move() -> void:
	# 使用独立调用日志验证完成信号会回到既有“结算时间后加载场景”流程。
	var call_log: Array[String] = []
	# 地图按钮只挂载必要的假依赖，避免该回归依赖完整主场景。
	var map_button: Node = MapButtonScript.new()
	# 假协调器模拟 C# 在自身 Callable 中发出的完成信号。
	var coordinator := FakeWorldHoldCoordinator.new()
	# 小地图依赖保留原有移动调用接口。
	var map_little := FakeMapLittle.new()
	# 场景实例化依赖记录加载行为。
	var map_instantiator := FakeMapInstantiator.new()
	# 自动加载提供行动值结算接口。
	var time_system := FakeTimeSystem.new()
	# 过场假节点异步发出既有淡出完成信号。
	var screen_transitions := FakeScreenTransitions.new()
	map_instantiator.call_log = call_log
	time_system.call_log = call_log
	map_button.world_interaction_coordinator = coordinator
	map_button.map_little = map_little
	map_button.map_instantiator = map_instantiator
	map_button.time_system = time_system
	map_button.screen_transitions = screen_transitions
	map_button.current_position = Vector2i(1, 1)
	map_button._pending_move_target = Vector2i(1, 2)
	map_button._connect_world_hold_completion()

	coordinator.emit_signal(&"WorldHoldCompleted", map_button)
	await create_timer(0.05).timeout

	_assert(call_log == ["time", "load"], "地图长按完成信号必须启动原有移动流程，并保持先结算时间再加载场景。")
	map_button.free()
	coordinator.free()
	map_little.free()
	map_instantiator.free()
	time_system.free()
	screen_transitions.free()


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
	forest.get_node("Background").self_modulate = Color(0.8, 0.8, 0.8, 1.0)
	map_instantiator.add_child(desert)
	map_instantiator.add_child(forest)
	map_instantiator.current_scene = forest
	var resolver = CurrentMapBackgroundResolverScript.new()

	var duplicated: Sprite2D = resolver.DuplicateCurrentBackground(map_system)

	_assert(duplicated != null, "战斗背景解析器应当能复制当前地图背景。")
	_assert(duplicated.name == "MapBackground", "复制到战斗场景的背景节点应当使用稳定名称。")
	_assert(duplicated.modulate == Color(0, 1, 0, 1), "战斗背景必须来自 MapInstantiator.current_scene，而不是第一个缓存子节点。")
	_assert(duplicated.self_modulate == Color(0.8, 0.8, 0.8, 1.0), "复制背景必须原样保留源背景的 self_modulate，昼夜压暗由屏幕滤镜另行承担。")

	duplicated.free()
	map_system.queue_free()
	await process_frame


func _test_map_instantiator_keeps_room_sprite_colors_untouched() -> void:
	# 昼夜表现已统一交给 core/ui/filters/day_night_filter.gd 的屏幕滤镜；
	# 地图层若再自行改写 self_modulate，会和滤镜叠成双重变暗，因此这条测试守住
	# 「地图实例化器不碰任何 Sprite 颜色」的边界。
	var map_instantiator: Node = MapInstantiatorScript.new()
	var room := _create_room_with_background("Forest", Color.WHITE)
	var foreground := Sprite2D.new()
	foreground.name = "Foreground"
	foreground.self_modulate = Color.WHITE
	room.add_child(foreground)
	map_instantiator.map_scene[Vector2i(0, 0)] = room

	var background: Sprite2D = room.get_node("Background")
	_assert(background.self_modulate == Color.WHITE, "地图实例化器不应改写房间背景颜色，屏幕滤镜才是唯一的昼夜压暗来源。")
	_assert(foreground.self_modulate == Color.WHITE, "地图实例化器不应改写同房间其它 Sprite 的颜色。")
	_assert(not map_instantiator.has_method("_on_day_night_toggled"), "昼夜染色入口已移除，不应再按昼夜状态改写房间颜色。")
	_assert(not map_instantiator.has_method("_apply_background_time_tint"), "房间背景染色实现已移除，不应残留可被误用的私有方法。")
	map_instantiator.free()
	room.free()


func _test_shop_room_background_uses_standard_background_contract() -> void:
	var shop_scene_resource: PackedScene = load("res://scenes/map_scenes/map_son_scenes/map_shop.tscn")
	var shop_scene: Node2D = shop_scene_resource.instantiate()
	var map_system := Node.new()
	var map_instantiator := FakeMapInstantiator.new()
	map_instantiator.name = "MapInstantiator"
	map_instantiator.call_log = []
	map_system.add_child(map_instantiator)
	map_instantiator.add_child(shop_scene)
	map_instantiator.current_scene = shop_scene
	var resolver = CurrentMapBackgroundResolverScript.new()

	var duplicated: Sprite2D = resolver.DuplicateCurrentBackground(map_system)

	_assert(shop_scene.get_node_or_null("Background") is Sprite2D, "商店房间背景节点应当统一命名为 Background。")
	_assert(duplicated != null, "战斗背景解析器应当能复制商店房间背景。")

	if duplicated != null:
		duplicated.free()
	map_system.queue_free()
	await process_frame


func _test_passage_guard_state_treats_edges_as_undirected() -> void:
	var state: RefCounted = PassageGuardStateScript.new()
	var home := Vector2i(1, 1)
	var forest := Vector2i(1, 2)

	state.AddGuard(home, forest)

	_assert(state.IsGuarded(home, forest), "驻守边应当能按原方向查询。")
	_assert(state.IsGuarded(forest, home), "驻守边应当能按反方向查询。")


func _test_passage_guard_probability_applies_modifiers() -> void:
	var settings: Resource = PassageGuardSettingsScript.new()
	settings.set("BaseGuardChance", 0.3)
	settings.get("ProbabilityModifiers").append(_create_modifier(&"quiet_night", 0.1, 1.0))
	settings.get("ProbabilityModifiers").append(_create_modifier(&"guard_discount", 0.0, 0.5))
	settings.get("ProbabilityModifiers").append(_create_modifier(&"inactive", 0.6, 10.0))
	var tags: Node = TagComponentScript.new()
	tags.AddTag(&"quiet_night")
	tags.AddTag(&"guard_discount")
	var provider: RefCounted = PassageGuardProbabilityProviderScript.new()

	var final_chance: float = float(provider.call("Calculate", settings, tags))

	_assert(abs(final_chance - 0.2) < 0.001, "驻守概率应当先加法修正再乘法修正，并忽略未拥有的标签。")
	tags.free()


func _test_passage_guard_probability_accepts_gdscript_modifier() -> void:
	var settings: Resource = PassageGuardSettingsScript.new()
	settings.set("BaseGuardChance", 0.4)
	var modifier: Resource = PassageGuardProbabilityModifierScript.new()
	modifier.set("RequiredTag", &"quiet_night")
	modifier.set("AdditiveChance", 0.2)
	modifier.set("Multiplier", 0.5)
	settings.get("ProbabilityModifiers").append(modifier)
	var tags: Node = TagComponentScript.new()
	tags.AddTag(&"quiet_night")
	var provider: RefCounted = PassageGuardProbabilityProviderScript.new()

	var final_chance: float = float(provider.call("Calculate", settings, tags))

	_assert(abs(final_chance - 0.3) < 0.001, "GDScript 驻守概率修正应通过通用 Resource 边界生效。")
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
	var monster: Resource = MonsterDataScript.new()
	monster.set("MonsterName", "木精")
	var pool: Array = [_create_encounter(monster)]
	var resolver: RefCounted = PassageGuardMonsterResolverScript.new()
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

	var monster: Resource = MonsterDataScript.new()
	monster.set("MonsterName", "驻守测试怪")
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
	controller.settings = PassageGuardSettingsScript.new()
	controller.settings.BaseGuardChance = 1.0
	controller.map_position_create_path = ^"../MapPositionCreate"
	controller.map_types_path = ^"../MapTypes"
	root.add_child(controller)

	return {
		"root": root,
		"controller": controller,
	}


func _create_modifier(required_tag: StringName, additive_chance: float, multiplier: float) -> Resource:
	var modifier: Resource = PassageGuardProbabilityModifierScript.new()
	modifier.set("RequiredTag", required_tag)
	modifier.set("AdditiveChance", additive_chance)
	modifier.set("Multiplier", multiplier)
	return modifier


func _create_encounter(monster: Resource) -> Resource:
	var encounter: Resource = PassageGuardEncounterDataScript.new()
	encounter.get("Monsters").append(monster)
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
