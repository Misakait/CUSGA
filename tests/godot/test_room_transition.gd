@tool
extends McpTestSuite

## 房间切换的耗时、重复请求与失败请求契约。
const MODEL = preload("res://core/map/map_world_model.gd")
const CONTROLLER = preload("res://scripts/map_scripts/UIMapWorldController.gd")
const TIME_SYSTEM = preload("res://core/autoloads/time_system.gd")
const CONFIG = preload("res://resources/map/room_transition_config.tres")
const ROOM: String = "res://scenes/map_scenes/map_env/wood/main/ancient_tree.tscn"


class FakeTime extends Node:
	var charges: int = 0
	var points: int = 0
	## 模拟成功移动推进时间；参数：无。返回值：无。
	func PassMapMoveTime() -> void:
		charges += 1
		points += 10


## 返回编辑器测试器识别的套件名；参数：无。
## @return 房间切换套件名称。
func suite_name() -> String:
	return "room_transition"


func _controller() -> Node:
	var model: Node = track(MODEL.new()) as Node
	model.set("map", [["ancient_tree", "ancient_tree", "ancient_tree"]])
	model.set("current_position", Vector2i.ZERO)
	model.set("map_road_in_map", {Vector2i(0, 0): ROOM, Vector2i(0, 1): ROOM, Vector2i(0, 2): ROOM})
	model.set("scene_to_scene", {Vector2i(0, 0): [0, 1, 0, 0], Vector2i(0, 1): [0, 1, 0, 1], Vector2i(0, 2): [0, 0, 0, 1]})
	var controller: Node = track(CONTROLLER.new()) as Node
	controller.set("_map_world_model", model)
	controller.set("_time_system", track(FakeTime.new()))
	return controller


## 初始房间和重复请求免费；同名但坐标不同的房间仍需按每次成功移动收费。
## @return 无返回值；参数：无。
func test_charge_only_once_per_real_room_change() -> void:
	var controller := _controller()
	var time: Node = controller.get("_time_system")
	assert_true(controller.call("request_room_transition", Vector2i.ZERO))
	assert_eq(time.get("charges"), 0)
	assert_true(controller.call("request_room_transition", Vector2i(0, 1)))
	assert_true(controller.call("request_room_transition", Vector2i(0, 1)))
	assert_eq(time.get("charges"), 1)
	assert_true(controller.call("request_room_transition", Vector2i.ZERO))
	assert_eq(time.get("charges"), 2)
	assert_eq(time.get("points"), 20)


## 越界、隔房、单向连接及缺失资源都不能收费或改变当前房间。
## @return 无返回值；参数：无。
func test_failed_room_requests_do_not_advance_time() -> void:
	var controller := _controller()
	var model: Node = controller.get("_map_world_model")
	var time: Node = controller.get("_time_system")
	assert_false(controller.call("request_room_transition", Vector2i(-1, 0)))
	assert_false(controller.call("request_room_transition", Vector2i(0, 2)))
	var connections: Dictionary = model.get("scene_to_scene")
	connections[Vector2i(0, 1)] = [0, 1, 0, 0]
	assert_false(controller.call("request_room_transition", Vector2i(0, 1)))
	connections[Vector2i(0, 1)] = [0, 1, 0, 1]
	var roads: Dictionary = model.get("map_road_in_map")
	roads[Vector2i(0, 1)] = "res://missing_room_for_transition_test.tscn"
	assert_false(controller.call("request_room_transition", Vector2i(0, 1)))
	assert_eq(time.get("charges"), 0)
	assert_eq(model.get("current_position"), Vector2i.ZERO)


## 同步房间信号内发出的第二个请求必须被拒绝，防止内容回调重复收费。
## @return 无返回值；参数：无。
func test_signal_reentry_cannot_charge_a_second_transition() -> void:
	var controller := _controller()
	var model: Node = controller.get("_map_world_model")
	var nested_results: Array[bool] = []
	model.connect("current_room_changed", func(_position: Vector2i) -> void:
		nested_results.append(controller.call("request_room_transition", Vector2i(0, 2)))
	)
	assert_true(controller.call("request_room_transition", Vector2i(0, 1)))
	assert_eq(nested_results, [false])
	assert_eq((controller.get("_time_system") as Node).get("charges"), 1)
	assert_eq(model.get("current_position"), Vector2i(0, 1))


## 真实时间系统读取资源成本、支持零成本和运行时覆盖，并正确跨越昼夜。
## @return 无返回值；参数：无。
func test_time_configuration_zero_cost_and_day_night_boundary() -> void:
	var time: Node = track(TIME_SYSTEM.new()) as Node
	assert_eq(time.get("MapMoveTimeCost"), CONFIG.action_cost)
	time.call("RestoreSnapshot", 95, 1, false)
	time.call("SetMapMoveTimeCost", 10)
	time.call("PassMapMoveTime")
	assert_eq(time.call("get_TotalTimePassed"), 105)
	assert_true(time.get("IsNight"))
	time.call("SetMapMoveTimeCost", 0)
	time.call("PassMapMoveTime")
	assert_eq(time.call("get_TotalTimePassed"), 105)
	time.call("SetMapMoveTimeCost", -5)
	assert_eq(time.get("MapMoveTimeCost"), 0)
	time.call("SetMapMoveTimeCost", 25)
	time.call("PassMapMoveTime")
	assert_eq(time.call("get_TotalTimePassed"), 130)


## 所有当前五行生态房间都有中文显示名，内部生成标识不会被误改。
## @return 无返回值；参数：无。
func test_all_current_biome_rooms_have_display_names() -> void:
	for biome_id: String in ["wood", "earth", "water", "fire", "gold"]:
		var biome: Resource = load("res://resources/map/biomes_new/%s_biome.tres" % biome_id)
		var rooms: Array = []
		rooms.append_array(biome.get("main_scenes"))
		rooms.append_array(biome.get("special_scenes"))
		for room: Resource in rooms:
			assert_false(String(CONFIG.room_names.get(String(room.get("scene_name")), "")).is_empty())
