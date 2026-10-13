extends Node2D

## 横向主线、纵向分支的地图生成器；生态配置归资源，布局参数归本节点。
## 坐标沿用旧协议 Vector2i(行,列)，连接依次为上、右、下、左。
## 分支数量范围对每个生态分别应用，长度不包含主线锚点房间。
@export_range(0, 100, 1, "or_greater") var min_branches: int = 2
@export_range(0, 100, 1, "or_greater") var max_branches: int = 5
@export_range(1, 100, 1, "or_greater") var min_branch_length: int = 2
@export_range(1, 100, 1, "or_greater") var max_branch_length: int = 5
## 零表示每次重新随机；其他值使相同配置得到可重现的地图。
@export var map_seed: int = 0

const DIR_OFFSETS: Array[Vector2i] = [
	Vector2i(-1, 0), Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1),
]
const OPPOSITE_DIR: Array[int] = [2, 3, 0, 1]

## 兼容旧 Model、View 和快照的公开输出。
var map: Array = []
var scene_to_scene: Dictionary = {}
var start_position: Vector2i = Vector2i.ZERO
var map_arr: Array[Vector2i] = []
var map_search_arr: Array[Vector2i] = []
var map_point_has_search: Dictionary = {}
var max_dis_from_home: int = 0
var max_dis_from_home_point: Vector2i = Vector2i.ZERO
## 生成成功后供检查使用的布局记录，不参与现有显示层。
var main_path: Array[Vector2i] = []
var branches: Array[Dictionary] = []
var position_biome: Dictionary = {}
## 最近一次生成失败的具体配置原因；失败时保留此前成功输出。
var last_error: String = ""

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	var run_snapshot: Node = get_node_or_null("../../RuntimeState/RunSnapshot")
	if run_snapshot != null and run_snapshot.has_method(&"ApplyMapToGenerator"):
		if bool(run_snapshot.call(&"ApplyMapToGenerator", self)):
			# 继续本局必须保留已有地图；旧快照没有新布局元数据，不伪造主线与分支。
			_rebuild_compatibility_data()
			return
	generate_map()


## 读取 MapTypes 的有序生态数组，校验全部配置后一次性发布地图。
## @param report_errors 是否把失败原因写入 Godot 错误日志，默认开启。
## @return 成功返回 true；失败返回 false，last_error 保存原因，旧输出保持不变。
func generate_map(report_errors: bool = true) -> bool:
	last_error = ""
	var map_types: Node = get_node_or_null("../MapTypes")
	if map_types == null or not map_types.has_method(&"build_all_dicts"):
		return _fail("MapPositionCreate 未找到可用的 MapTypes 节点。", report_errors)
	var configured: Variant = map_types.get(&"biomes")
	if not (configured is Array) or (configured as Array).is_empty():
		return _fail("MapTypes 的 biomes 数组必须配置至少一个新生态资源。", report_errors)
	if min_branches < 0 or max_branches < min_branches:
		return _fail("分支数量必须满足 0 ≤ 最少数量 ≤ 最多数量。", report_errors)
	if min_branch_length < 1 or max_branch_length < min_branch_length:
		return _fail("分支长度必须满足 1 ≤ 最短长度 ≤ 最长长度。", report_errors)
	if map_seed == 0:
		_rng.randomize()
	else:
		_rng.seed = map_seed
	var plans: Array[Dictionary] = []
	var names: Dictionary = {}
	var biome_names: Dictionary = {}
	for value: Variant in configured:
		var biome: BiomeDefinitionNew = value as BiomeDefinitionNew
		if biome == null:
			return _fail("生态数组不能包含空槽或旧类型生态资源。", report_errors)
		if biome.biome_name.is_empty() or biome.biome_name == "normal":
			return _fail("新生态名称不能为空，也不能使用 normal。", report_errors)
		if biome_names.has(biome.biome_name):
			return _fail("生态数组包含重复名称：%s。" % biome.biome_name, report_errors)
		biome_names[biome.biome_name] = true
		for scene in biome.get_all_scenes():
			if scene == null:
				continue
			if scene.scene_name.is_empty() or scene.scene_name == "void":
				return _fail("生态 %s 的场景名称不能为空或 void。" % biome.biome_name, report_errors)
			if names.has(scene.scene_name):
				return _fail("场景名称重复：%s；每种场景应只配置一次。" % scene.scene_name, report_errors)
			names[scene.scene_name] = true
			if scene.scene_dir.is_empty() or not ResourceLoader.exists(scene.scene_dir, "PackedScene"):
				return _fail("场景 %s 的房间路径无效：%s。" % [scene.scene_name, scene.scene_dir], report_errors)
		var plan: Dictionary = _plan_biome(biome)
		if plan.is_empty():
			return _fail(last_error, report_errors)
		plans.append(plan)
	# 全部生态可行之后才替换缓存与输出，避免后一个生态失败留下半张地图。
	var layout: Dictionary = _create_layout(plans)
	map_types.call(&"build_all_dicts")
	_publish_layout(layout)
	return true


func _plan_biome(biome: BiomeDefinitionNew) -> Dictionary:
	var main_scenes: Array[map_attribute] = []
	for scene in biome.main_scenes:
		if scene == null:
			continue
		if scene.scene_count < 0:
			last_error = "主场景 %s 的 scene_count 不能为负数。" % scene.scene_name
			return {}
		for _repeat in range(scene.scene_count):
			main_scenes.append(scene)
	if main_scenes.is_empty():
		last_error = "生态 %s 至少需要一个主线房间。" % biome.biome_name
		return {}
	# 只打乱生态内部的房间副本，不修改资源数组，生态之间仍按 MapTypes 的数组顺序连接。
	_shuffle(main_scenes)
	var boss_scenes: Array[map_attribute] = []
	for scene in biome.boss_scenes:
		if scene == null:
			continue
		if scene.scene_count < 0:
			last_error = "首领场景 %s 的 scene_count 不能为负数。" % scene.scene_name
			return {}
		for _repeat in range(scene.scene_count):
			boss_scenes.append(scene)
	# 首领单独随机排列，确保不会混入主场景或分支。
	_shuffle(boss_scenes)
	var minimum_special: int = 0
	var special_names: Dictionary = {}
	for scene in biome.special_scenes:
		if scene == null:
			continue
		special_names[scene.scene_name] = true
		var count_range: Vector2i = biome.get_special_scene_count_range(scene)
		if count_range.x < 0 or count_range.y < count_range.x:
			last_error = "特殊场景 %s 的次数必须满足 0 ≤ 最少次数 ≤ 最多次数。" % scene.scene_name
			return {}
		minimum_special += count_range.x
	for special_name: String in biome.special_scene_count_ranges:
		if not special_names.has(special_name):
			last_error = "生态 %s 的数量范围引用了未配置的特殊场景：%s。" % [biome.biome_name, special_name]
			return {}
	var upper_count: int = mini(max_branches, main_scenes.size() * 2)
	var required_count: int = ceili(float(minimum_special) / float(max_branch_length))
	var lower_count: int = maxi(min_branches, required_count)
	if lower_count > upper_count:
		last_error = "生态 %s 的分支容量不足：特殊场景至少 %d 个，可用分支最多 %d 条，每条最多 %d 个房间。" % [
			biome.biome_name, minimum_special, upper_count, max_branch_length,
		]
		return {}
	var count: int = _rng.randi_range(lower_count, upper_count)
	var lengths: Array[int] = []
	var capacity: int = 0
	for index in range(count):
		# 每次抽样为后续分支保留最大容量，确保随机结果也能容纳全部最低次数。
		var required_length: int = minimum_special - capacity - (count - index - 1) * max_branch_length
		var length: int = _rng.randi_range(maxi(min_branch_length, required_length), max_branch_length)
		lengths.append(length)
		capacity += length
	var branch_scenes: Array[map_attribute] = []
	var remaining_minimum: int = minimum_special
	for scene in biome.special_scenes:
		if scene == null:
			continue
		var count_range: Vector2i = biome.get_special_scene_count_range(scene)
		remaining_minimum -= count_range.x
		var upper_special: int = mini(count_range.y, capacity - branch_scenes.size() - remaining_minimum)
		var scene_count: int = _rng.randi_range(count_range.x, upper_special)
		for _repeat in range(scene_count):
			branch_scenes.append(scene)
	while branch_scenes.size() < capacity:
		branch_scenes.append(main_scenes[_rng.randi_range(0, main_scenes.size() - 1)])
	_shuffle(branch_scenes)
	return {
		"biome": biome, "main": main_scenes, "boss": boss_scenes,
		"lengths": lengths, "branch_scenes": branch_scenes,
	}


func _create_layout(plans: Array[Dictionary]) -> Dictionary:
	var rooms: Dictionary = {}
	var connections: Dictionary = {}
	var biome_positions: Dictionary = {}
	var path: Array[Vector2i] = []
	var branch_records: Array[Dictionary] = []
	var column: int = 0
	for plan in plans:
		var biome: BiomeDefinitionNew = plan["biome"]
		var main_scenes: Array[map_attribute] = plan["main"]
		var anchors: Array[Vector2i] = []
		for scene in main_scenes:
			var room_position := Vector2i(0, column)
			_place_room(rooms, connections, biome_positions, room_position, scene, biome.biome_name)
			_append_main_room(path, connections, room_position)
			anchors.append(room_position)
			column += 1
		var boss_scenes: Array[map_attribute] = plan["boss"]
		for scene in boss_scenes:
			var boss_position := Vector2i(0, column)
			_place_room(rooms, connections, biome_positions, boss_position, scene, biome.biome_name)
			_append_main_room(path, connections, boss_position)
			column += 1
		var slots: Array[Vector2i] = []
		for index in range(anchors.size()):
			slots.append(Vector2i(index, 0))
			slots.append(Vector2i(index, 2))
		_shuffle(slots)
		var lengths: Array[int] = plan["lengths"]
		var branch_scenes: Array[map_attribute] = plan["branch_scenes"]
		var scene_index: int = 0
		for index in range(lengths.size()):
			var slot: Vector2i = slots[index]
			var anchor: Vector2i = anchors[slot.x]
			var previous: Vector2i = anchor
			var positions: Array[Vector2i] = []
			for _step in range(lengths[index]):
				var room_position: Vector2i = previous + DIR_OFFSETS[slot.y]
				_place_room(rooms, connections, biome_positions, room_position, branch_scenes[scene_index], biome.biome_name)
				_connect(connections, previous, room_position, slot.y)
				positions.append(room_position)
				previous = room_position
				scene_index += 1
			branch_records.append({
				"biome_name": biome.biome_name, "anchor": anchor,
				"direction": slot.y, "positions": positions,
			})
	return {"rooms": rooms, "connections": connections, "biomes": biome_positions, "path": path, "branches": branch_records}


func _place_room(rooms: Dictionary, connections: Dictionary, biomes: Dictionary,
	room_position: Vector2i, scene: map_attribute, biome_name: String) -> void:
	rooms[room_position] = scene.scene_name
	connections[room_position] = [0, 0, 0, 0]
	biomes[room_position] = biome_name


func _append_main_room(path: Array[Vector2i], connections: Dictionary, room_position: Vector2i) -> void:
	if not path.is_empty():
		_connect(connections, path.back(), room_position, 1)
	path.append(room_position)


func _connect(connections: Dictionary, from: Vector2i, to: Vector2i, direction: int) -> void:
	# 相邻分支只建立各自的纵向连接，不能因为格子相邻就自动横向连通。
	connections[from][direction] = 1
	connections[to][OPPOSITE_DIR[direction]] = 1


func _publish_layout(layout: Dictionary) -> void:
	var rooms: Dictionary = layout["rooms"]
	var minimum_row: int = 0
	var maximum_row: int = 0
	for room_position: Vector2i in rooms:
		minimum_row = mini(minimum_row, room_position.x)
		maximum_row = maxi(maximum_row, room_position.x)
	var offset := Vector2i(1 - minimum_row, 1)
	var path: Array[Vector2i] = layout["path"]
	var new_map: Array = []
	for _row in range(maximum_row - minimum_row + 3):
		var row: Array = []
		row.resize(path.size() + 2)
		row.fill("void")
		new_map.append(row)
	var new_connections: Dictionary = {}
	var new_biomes: Dictionary = {}
	var connections: Dictionary = layout["connections"]
	var biomes: Dictionary = layout["biomes"]
	for room_position: Vector2i in rooms:
		var shifted: Vector2i = room_position + offset
		new_map[shifted.x][shifted.y] = rooms[room_position]
		new_connections[shifted] = connections[room_position]
		new_biomes[shifted] = biomes[room_position]
	var new_path: Array[Vector2i] = []
	for room_position in path:
		new_path.append(room_position + offset)
	var new_branches: Array[Dictionary] = []
	for branch: Dictionary in layout["branches"]:
		var positions: Array[Vector2i] = []
		for room_position: Vector2i in branch["positions"]:
			positions.append(room_position + offset)
		new_branches.append({
			"biome_name": branch["biome_name"], "anchor": branch["anchor"] + offset,
			"direction": branch["direction"], "positions": positions,
		})
	map = new_map
	scene_to_scene = new_connections
	start_position = new_path[0]
	main_path = new_path
	branches = new_branches
	position_biome = new_biomes
	_rebuild_compatibility_data()


func _rebuild_compatibility_data() -> void:
	map_arr.clear()
	map_search_arr.clear()
	map_point_has_search.clear()
	max_dis_from_home = 0
	max_dis_from_home_point = start_position
	for row in range(map.size()):
		for column in range(map[row].size()):
			if String(map[row][column]) != "void":
				map_arr.append(Vector2i(row, column))
	if map_arr.is_empty():
		return
	var distances: Dictionary = {start_position: 0}
	map_search_arr.append(start_position)
	var index: int = 0
	while index < map_search_arr.size():
		var room_position: Vector2i = map_search_arr[index]
		index += 1
		map_point_has_search[room_position] = true
		var mask: Array = scene_to_scene.get(room_position, [0, 0, 0, 0])
		for direction in range(4):
			if int(mask[direction]) != 1:
				continue
			var neighbor: Vector2i = room_position + DIR_OFFSETS[direction]
			if distances.has(neighbor):
				continue
			var distance: int = int(distances[room_position]) + 1
			distances[neighbor] = distance
			map_search_arr.append(neighbor)
			if distance > max_dis_from_home:
				max_dis_from_home = distance
				max_dis_from_home_point = neighbor


func _shuffle(values: Array) -> void:
	# 使用本生成器的随机源，避免其他系统的随机调用破坏地图种子复现。
	for index in range(values.size() - 1, 0, -1):
		var other: int = _rng.randi_range(0, index)
		var temporary: Variant = values[index]
		values[index] = values[other]
		values[other] = temporary


func _fail(message: String, report_errors: bool) -> bool:
	last_error = message
	if report_errors:
		push_error(message)
	return false
