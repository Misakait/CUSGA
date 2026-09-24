@tool
extends McpTestSuite

## 房间地形仓库与布局生成器 GDScript 生产边界契约套件。
##
## 套件锁定生产 Main 场景的脚本切换、C# 表现层的动态方法协议、仓库的
## 创建/去重/读取语义、倍率字典的跨语言往返，以及生成器的权重与数量边界规则。

const TERRAIN_STORE_SCRIPT: GDScript = preload("res://core/map/room_terrain_store.gd")
const LAYOUT_GENERATOR_SCRIPT: GDScript = preload("res://core/map/room_terrain_layout_generator.gd")
const PROFILE_SCRIPT: GDScript = preload("res://core/map/room_terrain_profile.gd")
const POOL_ENTRY_SCRIPT: GDScript = preload("res://core/map/room_terrain_pool_entry.gd")
const VARIANCE_RANGE_SCRIPT: GDScript = preload("res://resources/encounters/monster_stat_multiplier_range.gd")
## C# 可选助手：C# 缺席时安全收起跨语言对照，避免解析期错误与「空源文假通过」。
const CS_OPTIONAL := preload("res://tests/godot/csharp_optional.gd")

## 生产地形卡资源，用于确认仓库仍能创建真实的跨语言地形实例。
const PRODUCTION_TERRAIN_PATH: String = "res://resources/map/terrain/wood_terrain.tres"

## 生产地图场景，用于做资产驱动的布局生成验证。
const PRODUCTION_MAP_SCENE_PATH: String = "res://scenes/map_scenes/map_son_scenes/map_desert.tscn"

## 倍率字段的稳定顺序，与 TerrainInstance 快照协议保持一致。
const VARIANCE_FIELDS: Array[String] = [
	"MaxHealth",
	"PhysAtk",
	"PhysDef",
	"MagPower",
	"MagResist",
	"Speed",
]

## 固定随机种子，让生成器抽样在聚焦测试中保持可复现。
const FIXED_SEED: int = 20260920


## 返回套件名称，供 MCP 按批次筛选测试。
func suite_name() -> String:
	return "room_terrain_store_contract"


## 生成一个类型化地形池，避免把无类型数组写入 Array[Resource] 导出字段。
##
## @param entries 地形池条目数组。
## @return 类型化后的地形池。
func _typed_pool(entries: Array) -> Array[Resource]:
	var pool: Array[Resource] = []
	for entry: Variant in entries:
		pool.append(entry)
	return pool


## 创建一个只含地形卡与权重的池条目。
##
## @param terrain_data 候选地形卡资源。
## @param weight 抽样权重。
## @return 地形池条目资源。
func _make_pool_entry(terrain_data: Resource, weight: float = 1.0) -> Resource:
	var entry: Resource = POOL_ENTRY_SCRIPT.new()
	entry.set("TerrainData", terrain_data)
	entry.set("Weight", weight)
	return entry


## 创建测试用布局配置。
##
## @param pool 地形池条目。
## @param min_count 最少地形数量。
## @param max_count 最多地形数量。
## @param columns 网格列数。
## @param rows 网格行数。
## @param placement_min 摆放区域左上角。
## @param placement_max 摆放区域右下角。
## @param variance_range 遭遇倍率区间资源；为空表示中性倍率。
## @return 布局配置资源。
func _make_profile(
	pool: Array,
	min_count: int,
	max_count: int,
	columns: int = 2,
	rows: int = 2,
	placement_min: Vector2 = Vector2.ZERO,
	placement_max: Vector2 = Vector2.ZERO,
	variance_range: Resource = null
) -> Resource:
	var profile: Resource = PROFILE_SCRIPT.new()
	profile.set("TerrainPool", pool)
	profile.set("MinCount", min_count)
	profile.set("MaxCount", max_count)
	profile.set("GridColumns", columns)
	profile.set("GridRows", rows)
	profile.set("PlacementMin", placement_min)
	profile.set("PlacementMax", placement_max)
	profile.set("EncounterVarianceRange", variance_range)
	return profile


## 构造一条摆放字典，字段名与生成器输出协议一致。
##
## @param terrain_data 地形卡资源。
## @param cell 房间内局部格子坐标。
## @param board_position 棋盘显示坐标。
## @param variance 遭遇倍率字典；为空表示中性倍率。
## @return 摆放字典。
func _make_placement(
	terrain_data: Resource,
	cell: Vector2i,
	board_position: Vector2,
	variance: Variant
) -> Dictionary:
	return {
		"TerrainData": terrain_data,
		"LocalGridPos": cell,
		"BoardPosition": board_position,
		"Variance": variance,
	}


## 读取一个地形实例的倍率快照，验证跨语言读取协议可用。
##
## @param terrain 地形实例。
## @return 六个倍率字段的字典。
func _read_snapshot(terrain: Variant) -> Dictionary:
	assert_true(terrain != null, "倍率快照读取需要有效地形实例。")
	if terrain == null:
		return {}
	return (terrain as Object).call("GetEncounterVarianceSnapshot")


## 验证生产 Main 场景已切换到 GDScript 仓库，旧 C# 实现仍作为垫片保留。
func test_production_scene_and_compat_shims() -> void:
	var main_scene: String = FileAccess.get_file_as_string("res://scenes/Main.tscn")
	assert_true(
		main_scene.contains('path="res://core/map/room_terrain_store.gd"'),
		"生产 Main 场景必须使用 GDScript 房间地形仓库。"
	)
	assert_false(
		main_scene.contains("RoomTerrainStore.cs"),
		"生产 Main 场景不得继续引用旧 C# 房间地形仓库。"
	)
	assert_true(
		main_scene.contains('TerrainStorePath = NodePath("../../RuntimeState/RoomTerrainStore")'),
		"地形仓库节点路径导出值必须保持不变。"
	)

	for compat_path: String in [
		"res://core/map/RoomTerrainStore.cs",
		"res://core/map/RoomTerrainLayoutGenerator.cs",
	]:
		## C# 垫片仍在时必须可加载；C# 退役后这些路径按条件收起（不再有可加载对象）。
		assert_true(
			not CS_OPTIONAL.present(compat_path) or load(compat_path) != null,
			"%s 必须作为兼容垫片保留并且可以加载。" % compat_path
		)


## 验证 C# 表现层只依赖稳定方法协议，不再编译期引用具体类型。
func test_presenter_uses_dynamic_protocol() -> void:
	# 生产表现层已切换为 GDScript，只依赖稳定方法协议；旧 C# 垫片继续保留同一套协议作为对照。
	var presenter_source: String = FileAccess.get_file_as_string("res://core/map/UIRoomBoardPresenter.gd")
	assert_false(
		presenter_source.contains("RoomTerrainStore"),
		"表现层不得继续引用具体 RoomTerrainStore 类型。"
	)
	assert_false(
		presenter_source.contains("private RoomTerrainStore"),
		"表现层不得继续声明具体 RoomTerrainStore 字段。"
	)
	assert_false(
		presenter_source.contains("RoomTerrainLayoutGenerator"),
		"表现层不得继续引用旧 C# 布局生成器。"
	)
	assert_false(
		presenter_source.contains("new RoomTerrainLayoutGenerator"),
		"表现层不得继续直接实例化旧 C# 布局生成器。"
	)
	for method_name: String in ["HasRoom", "CreateRoomLayout", "GetRoomTerrainsOrEmpty"]:
		assert_true(
			presenter_source.contains('"%s"' % method_name),
			"表现层必须按 %s 方法协议调用地形仓库。" % method_name
		)
	assert_true(
		presenter_source.contains("room_terrain_layout_generator.gd"),
		"表现层必须从 GDScript 布局生成器取回摆放结果。"
	)

	## C# 源文对照：C# 退役后 read() 返回空串，整块按条件收起而不是假通过。
	var presenter_shim_source: String = CS_OPTIONAL.read("res://core/map/RoomBoardPresenter.cs")
	if not presenter_shim_source.is_empty():
		for method_name: String in ["HasRoom", "CreateRoomLayout", "GetRoomTerrainsOrEmpty"]:
			assert_true(
				presenter_shim_source.contains('"%s"' % method_name),
				"旧 C# 表现层垫片必须继续按 %s 方法协议调用地形仓库。" % method_name
			)
		assert_false(
			presenter_shim_source.contains("private RoomTerrainStore"),
			"旧 C# 表现层垫片不得退回具体 RoomTerrainStore 字段。"
		)


## 验证仓库的创建语义、幂等性与新实例默认值。
func test_store_get_or_create_idempotent_and_defaults() -> void:
	var store: Node = TERRAIN_STORE_SCRIPT.new()
	track(store)
	var terrain_data: Resource = load(PRODUCTION_TERRAIN_PATH)
	assert_true(terrain_data != null, "测试必须能加载生产地形资源。")

	var room := Vector2i(2, 3)
	var cell := Vector2i(1, 1)
	assert_false(bool(store.call("HasRoom", room)), "未创建的房间不得报告已存在。")
	assert_eq(
		(store.call("GetRoomTerrainsOrEmpty", room) as Dictionary).size(),
		0,
		"不存在的房间必须返回空字典。"
	)

	var first: Variant = store.call("GetOrCreate", room, cell, terrain_data, Vector2(120, 240))
	assert_true(first != null, "创建房间地形必须返回实例。")
	assert_true(bool(store.call("HasRoom", room)), "创建后房间必须报告已存在。")

	var second: Variant = store.call("GetOrCreate", room, cell, terrain_data, Vector2(999, 999))
	assert_true(second == first, "同一格子重复调用必须返回原实例。")
	assert_true(
		store.call("TryGetTerrain", room, cell) == first,
		"按格子读取必须返回同一实例。"
	)
	assert_eq(
		store.call("TryGetTerrain", room, Vector2i(9, 9)),
		null,
		"未占用格子必须返回 null。"
	)

	var instance: Object = first
	assert_eq(instance.get("LocalGridPos"), cell, "实例必须保留局部格子坐标。")
	assert_eq(
		instance.get("BoardPosition"),
		Vector2(120, 240),
		"重复调用不得覆盖首次写入的棋盘坐标。"
	)
	assert_eq(instance.get("TerrainData"), terrain_data, "实例必须保留地形配置资源。")
	assert_false(bool(instance.get("IsOccupied")), "新地形实例默认不得被占用。")
	assert_false(bool(instance.get("IsHarvested")), "新地形实例默认不得标记为已采集。")
	assert_eq(int(instance.get("GrowthStage")), 0, "新地形实例成长阶段必须为 0。")
	assert_eq(
		int(instance.get("RemainingGatheringCount")),
		-1,
		"剩余采集次数必须保持旧默认值 -1。"
	)
	assert_eq(
		String(instance.get_script().resource_path),
		"res://resources/interaction/terrain_instance.gd",
		"生产地形实例必须由本批 GDScript 实现提供。"
	)
	## C# 垫片仍在时必须可加载；C# 退役后该路径按条件收起（不再有可加载对象）。
	assert_true(
		not CS_OPTIONAL.present("res://resources/interaction/TerrainInstance.cs")
			or load("res://resources/interaction/TerrainInstance.cs") != null,
		"旧 C# TerrainInstance 必须作为兼容垫片保留并且可以加载。"
	)


## 验证缺少地形配置时与旧实现的空值分支一致。
func test_store_rejects_missing_terrain_data() -> void:
	var store: Node = TERRAIN_STORE_SCRIPT.new()
	track(store)
	assert_eq(
		store.call("GetOrCreate", Vector2i(7, 7), Vector2i.ZERO, null),
		null,
		"缺少地形配置时必须返回 null。"
	)
	assert_false(
		bool(store.call("HasRoom", Vector2i(7, 7))),
		"失败调用不得建立房间缓存。"
	)


## 验证批量布局、重复格子错误分支与空布局的房间缓存语义。
func test_layout_creation_and_duplicate_detection() -> void:
	var store: Node = TERRAIN_STORE_SCRIPT.new()
	track(store)
	var terrain_data: Resource = load(PRODUCTION_TERRAIN_PATH)
	assert_true(terrain_data != null, "测试必须能加载生产地形资源。")

	var room := Vector2i(1, 1)
	var placements: Array = [
		_make_placement(terrain_data, Vector2i(0, 0), Vector2(10, 20), null),
		_make_placement(terrain_data, Vector2i(1, 0), Vector2(30, 40), null),
	]
	assert_true(
		bool(store.call("CreateRoomLayout", room, placements)),
		"首次布局必须成功。"
	)
	assert_eq(
		(store.call("GetRoomTerrainsOrEmpty", room) as Dictionary).size(),
		2,
		"布局必须写入两个格子。"
	)
	assert_eq(
		(store.call("TryGetTerrain", room, Vector2i(1, 0)) as Object).get("BoardPosition"),
		Vector2(30, 40),
		"布局必须写入摆放坐标。"
	)

	var duplicate: Array = [
		_make_placement(terrain_data, Vector2i(0, 0), Vector2(99, 99), null),
	]
	assert_false(
		bool(store.call("CreateRoomLayout", room, duplicate)),
		"重复格子必须报告失败。"
	)
	assert_eq(
		(store.call("TryGetTerrain", room, Vector2i(0, 0)) as Object).get("BoardPosition"),
		Vector2(10, 20),
		"重复格子不得覆盖原实例。"
	)

	var empty_room := Vector2i(4, 4)
	assert_true(
		bool(store.call("CreateRoomLayout", empty_room, [])),
		"空布局必须成功。"
	)
	assert_true(bool(store.call("HasRoom", empty_room)), "空布局必须建立房间缓存。")
	assert_eq(
		(store.call("GetRoomTerrainsOrEmpty", empty_room) as Dictionary).size(),
		0,
		"空布局房间不得包含地形。"
	)


## 验证倍率字典可以写回 GDScript TerrainInstance 并按快照协议读回。
func test_variance_round_trip_matches_snapshot_protocol() -> void:
	var store: Node = TERRAIN_STORE_SCRIPT.new()
	track(store)
	var terrain_data: Resource = load(PRODUCTION_TERRAIN_PATH)
	assert_true(terrain_data != null, "测试必须能加载生产地形资源。")

	var room := Vector2i(5, 5)
	var variance: Dictionary = {
		"MaxHealth": 1.25,
		"PhysAtk": 0.75,
		"PhysDef": 1.1,
		"MagPower": 1.0,
		"MagResist": 0.9,
		"Speed": 2.0,
	}
	var placements: Array = [
		_make_placement(terrain_data, Vector2i(0, 0), Vector2.ZERO, variance),
		_make_placement(terrain_data, Vector2i(0, 1), Vector2.ZERO, {"MaxHealth": 0.5}),
		_make_placement(terrain_data, Vector2i(0, 2), Vector2.ZERO, null),
	]
	assert_true(
		bool(store.call("CreateRoomLayout", room, placements)),
		"带倍率的布局必须成功。"
	)

	var rolled: Dictionary = _read_snapshot(store.call("TryGetTerrain", room, Vector2i(0, 0)))
	for field: String in VARIANCE_FIELDS:
		assert_true(
			is_equal_approx(float(rolled.get(field, -1.0)), float(variance[field])),
			"倍率 %s 必须按字典写回地形实例。" % field
		)

	var partial: Dictionary = _read_snapshot(store.call("TryGetTerrain", room, Vector2i(0, 1)))
	assert_true(
		is_equal_approx(float(partial.get("MaxHealth", -1.0)), 0.5),
		"部分倍率字典必须写入提供的字段。"
	)
	assert_true(
		is_equal_approx(float(partial.get("Speed", -1.0)), 1.0),
		"缺失的倍率字段必须回退为中性值 1。"
	)

	var identity: Dictionary = _read_snapshot(store.call("TryGetTerrain", room, Vector2i(0, 2)))
	for field: String in VARIANCE_FIELDS:
		assert_true(
			is_equal_approx(float(identity.get(field, -1.0)), 1.0),
			"未提供倍率时 %s 必须为中性值 1。" % field
		)


## 验证同一种子产生完全相同的布局，且数量落在配置区间内。
func test_generator_determinism_and_bounds() -> void:
	var pool: Array[Resource] = _typed_pool([
		_make_pool_entry(Resource.new(), 3.0),
		_make_pool_entry(Resource.new(), 1.0),
	])
	var variance_range: Resource = VARIANCE_RANGE_SCRIPT.new()
	variance_range.set("MinMaxHealth", 1.0)
	variance_range.set("MaxMaxHealth", 2.0)
	variance_range.set("MinSpeed", 0.5)
	variance_range.set("MaxSpeed", 0.5)
	var profile: Resource = _make_profile(
		pool, 2, 5, 3, 3, Vector2(360, 220), Vector2(920, 560), variance_range
	)

	var first_generator: Object = LAYOUT_GENERATOR_SCRIPT.new(FIXED_SEED)
	var second_generator: Object = LAYOUT_GENERATOR_SCRIPT.new(FIXED_SEED)
	var first: Array = first_generator.call("Generate", profile)
	var second: Array = second_generator.call("Generate", profile)
	assert_eq(first, second, "同一种子必须产生完全相同的布局。")
	assert_true(
		first.size() >= 2 and first.size() <= 5,
		"布局数量必须落在 MinCount/MaxCount 区间。"
	)

	var cells: Array = []
	for placement: Variant in first:
		var placement_dict: Dictionary = placement
		assert_true(
			placement_dict.get("TerrainData", null) != null,
			"每个摆放必须携带地形配置。"
		)
		assert_false(
			cells.has(placement_dict["LocalGridPos"]),
			"同一房间不得在同一格子重复摆放。"
		)
		cells.append(placement_dict["LocalGridPos"])

		var rolled: Dictionary = placement_dict["Variance"]
		var max_health: float = float(rolled["MaxHealth"])
		assert_true(
			max_health >= 1.0 and max_health <= 2.0,
			"抽样倍率必须落在配置区间内。"
		)
		assert_true(
			is_equal_approx(float(rolled["Speed"]), 0.5),
			"上下界相同的倍率字段必须固定为配置值。"
		)


## 验证总权重为 0 时退化为第一个有效地形，与旧实现的无随机分支一致。
func test_generator_weight_zero_fallback() -> void:
	var first_data: Resource = Resource.new()
	var second_data: Resource = Resource.new()
	var pool: Array[Resource] = _typed_pool([
		_make_pool_entry(first_data, 0.0),
		_make_pool_entry(second_data, 0.0),
	])
	var profile: Resource = _make_profile(pool, 3, 3, 3, 3)
	var generator: Object = LAYOUT_GENERATOR_SCRIPT.new(FIXED_SEED)
	var placements: Array = generator.call("Generate", profile)
	assert_eq(placements.size(), 3, "零权重地形池必须仍按配置数量生成摆放。")
	for placement: Variant in placements:
		var placement_dict: Dictionary = placement
		assert_eq(
			placement_dict["TerrainData"],
			first_data,
			"总权重为 0 时必须退化为第一个有效地形。"
		)


## 验证数量上下界被格子总数与 MinCount 正确夹紧。
func test_generator_count_clamping() -> void:
	var pool: Array[Resource] = _typed_pool([_make_pool_entry(Resource.new(), 1.0)])
	var generator: Object = LAYOUT_GENERATOR_SCRIPT.new(FIXED_SEED)

	var over_profile: Resource = _make_profile(pool, 5, 99, 2, 2)
	assert_eq(
		generator.call("Generate", over_profile).size(),
		4,
		"数量上界必须被格子总数截断。"
	)

	var inverted_profile: Resource = _make_profile(pool, 3, 1, 6, 4)
	assert_eq(
		generator.call("Generate", inverted_profile).size(),
		3,
		"MaxCount 小于 MinCount 时必须按 MinCount 生成。"
	)

	var zero_profile: Resource = _make_profile(pool, 0, 0, 6, 4)
	assert_eq(
		generator.call("Generate", zero_profile).size(),
		0,
		"MinCount 与 MaxCount 同时为 0 时必须生成空布局。"
	)


## 验证摆放坐标按格子中心在摆放矩形内插值。
func test_generator_board_position_lerp() -> void:
	var pool: Array[Resource] = _typed_pool([_make_pool_entry(Resource.new(), 1.0)])
	var profile: Resource = _make_profile(
		pool, 4, 4, 2, 2, Vector2.ZERO, Vector2(100, 100)
	)
	var generator: Object = LAYOUT_GENERATOR_SCRIPT.new(FIXED_SEED)
	var placements: Array = generator.call("Generate", profile)
	assert_eq(placements.size(), 4, "2x2 网格必须摆放四个地形。")

	var by_cell: Dictionary = {}
	for placement: Variant in placements:
		var placement_dict: Dictionary = placement
		by_cell[placement_dict["LocalGridPos"]] = placement_dict["BoardPosition"]

	for y in 2:
		for x in 2:
			var cell := Vector2i(x, y)
			var expected := Vector2(
				(float(x) + 0.5) / 2.0 * 100.0,
				(float(y) + 0.5) / 2.0 * 100.0
			)
			assert_true(by_cell.has(cell), "网格必须覆盖格子 %s。" % cell)
			if not by_cell.has(cell):
				continue
			assert_true(
				(by_cell[cell] as Vector2).is_equal_approx(expected),
				"格子 %s 的摆放坐标必须按格子中心插值。" % cell
			)


## 验证空配置、空地形池和无效池条目都返回空布局。
func test_generator_empty_inputs() -> void:
	var generator: Object = LAYOUT_GENERATOR_SCRIPT.new(FIXED_SEED)
	assert_eq(
		(generator.call("Generate", null) as Array).size(),
		0,
		"空配置必须返回空布局。"
	)

	var empty_pool_profile: Resource = _make_profile(_typed_pool([]), 1, 3)
	assert_eq(
		(generator.call("Generate", empty_pool_profile) as Array).size(),
		0,
		"空地形池必须返回空布局。"
	)

	var invalid_pool: Array[Resource] = _typed_pool([_make_pool_entry(null, 1.0)])
	var invalid_profile: Resource = _make_profile(invalid_pool, 1, 3)
	assert_eq(
		(generator.call("Generate", invalid_profile) as Array).size(),
		0,
		"缺少地形卡的池条目必须被忽略。"
	)


## 用生产地图配置验证生成器输出可以写入 GDScript 仓库。
func test_production_map_profile_generates_layout() -> void:
	var scene: PackedScene = load(PRODUCTION_MAP_SCENE_PATH)
	assert_true(scene != null, "生产地图场景必须能够加载。")
	if scene == null:
		return

	var map_node: Node = scene.instantiate()
	var profile: Resource = map_node.get("terrain_profile") as Resource
	assert_true(profile != null, "生产地图必须保留地形布局配置。")
	if profile == null:
		map_node.free()
		return

	var generator: Object = LAYOUT_GENERATOR_SCRIPT.new(FIXED_SEED)
	var placements: Array = generator.call("Generate", profile)
	assert_true(placements.size() >= 1, "生产地形配置必须至少生成一个摆放。")

	var store: Node = TERRAIN_STORE_SCRIPT.new()
	track(store)
	var room := Vector2i(0, 0)
	assert_true(
		bool(store.call("CreateRoomLayout", room, placements)),
		"生产摆放结果必须能写入 GDScript 仓库。"
	)
	var terrains: Dictionary = store.call("GetRoomTerrainsOrEmpty", room)
	assert_eq(terrains.size(), placements.size(), "仓库必须写入全部生产摆放。")

	# 逐格核对：写进仓库的倍率必须与生成器产出的倍率完全一致，
	# 这样即使策划配置了非中性区间，跨语言写入协议也不会丢字段或改数值。
	var expected_variance: Dictionary = {}
	for placement: Variant in placements:
		var placement_dict: Dictionary = placement
		expected_variance[placement_dict["LocalGridPos"]] = placement_dict["Variance"]

	for cell: Variant in terrains.keys():
		var instance: Object = terrains[cell]
		assert_true(
			instance.get("TerrainData") != null,
			"生产地形实例必须保留地形配置资源。"
		)
		assert_true(
			instance.has_method("GetEncounterVarianceSnapshot"),
			"生产地形实例必须保留倍率快照协议。"
		)
		assert_true(
			expected_variance.has(cell),
			"仓库不得出现生成器未产出的格子。"
		)
		if not expected_variance.has(cell):
			continue

		var snapshot: Dictionary = _read_snapshot(instance)
		var placement_variance: Dictionary = expected_variance[cell]
		for field: String in VARIANCE_FIELDS:
			assert_true(
				is_equal_approx(
					float(snapshot.get(field, -1.0)),
					float(placement_variance[field])
				),
				"生产倍率 %s 必须与生成器产出一致。" % field
			)
	map_node.free()
