@tool
extends McpTestSuite

## 地形实例（TerrainInstance）生产迁移契约套件。
##
## 套件锁定房间仓库创建的是本批 GDScript 实现、旧 C# 垫片仍然可用、
## 字段默认值与倍率字典协议未变，并确认 C# 消费者只依赖跨语言字段协议。

## 本批 GDScript 地形实例脚本。
const TERRAIN_INSTANCE_SCRIPT: GDScript = preload("res://resources/interaction/terrain_instance.gd")
## 生产房间地形仓库脚本。
const TERRAIN_STORE_SCRIPT: GDScript = preload("res://core/map/room_terrain_store.gd")
## 旧 C# 地形实例兼容垫片路径（C# 退役后此路径不再存在，相关对照按条件收起）。
const LEGACY_TERRAIN_INSTANCE_CS_PATH: String = "res://resources/interaction/TerrainInstance.cs"
## 旧 C# 世界交互协调器路径（仅用于核对跨语言字段协议）。
const WORLD_INTERACTION_COORDINATOR_CS_PATH: String = "res://core/gameflow/WorldInteractionCoordinator.cs"
## 旧 C# 交互上下文路径（仅用于核对跨语言字段协议）。
const WORLD_INTERACTION_CONTEXT_CS_PATH: String = "res://resources/interaction/WorldInteractionContext.cs"
## 旧 C# 地形实例字段协议路径（仅用于核对跨语言字段协议）。
const TERRAIN_INSTANCE_PROTOCOL_CS_PATH: String = "res://resources/interaction/TerrainInstanceProtocol.cs"
## 旧 C# 玩法门面路径（仅用于核对跨语言方法协议）。
const GAMEPLAY_PORT_CS_PATH: String = "res://core/application/GameplayPort.cs"
## C# 可选助手：C# 缺席时安全收起跨语言对照，避免解析期错误与「空源文假通过」。
const CS_OPTIONAL := preload("res://tests/godot/csharp_optional.gd")
## 倍率字段顺序，与旧 C# MonsterStatMultiplier 完全一致。
const VARIANCE_FIELDS: Array[String] = [
	"MaxHealth", "PhysAtk", "PhysDef", "MagPower", "MagResist", "Speed",
]


## 返回 GodotAI 使用的稳定套件名称。
##
## @return 地形实例契约套件名。
func suite_name() -> String:
	return "terrain_instance_contract"


## 验证房间仓库创建的是 GDScript 实例，且旧 C# 垫片仍然存在可加载。
func test_production_store_creates_gdscript_instance() -> void:
	var store: Node = TERRAIN_STORE_SCRIPT.new()
	track(store)
	var terrain_data: Resource = load("res://resources/map/terrain/wood_terrain.tres")
	assert_true(terrain_data != null, "测试必须能加载生产地形资源。")

	var instance: Variant = store.call("GetOrCreate", Vector2i.ZERO, Vector2i.ZERO, terrain_data)
	assert_true(instance != null, "房间仓库必须返回地形实例。")
	assert_eq(
		String(instance.get_script().resource_path),
		"res://resources/interaction/terrain_instance.gd",
		"房间仓库必须创建本批 GDScript 地形实例。"
	)
	## C# 垫片仍在时必须可加载；C# 退役后该对照按条件收起（不再有可加载对象）。
	if CS_OPTIONAL.present(LEGACY_TERRAIN_INSTANCE_CS_PATH):
		assert_true(CS_OPTIONAL.script(LEGACY_TERRAIN_INSTANCE_CS_PATH) != null, "旧 C# 地形实例必须仍然可以加载。")
	assert_true(
		FileAccess.get_file_as_string("res://core/map/room_terrain_store.gd").contains(
			"res://resources/interaction/terrain_instance.gd"
		),
		"房间仓库必须指向 GDScript 地形实例脚本。"
	)


## 验证新实例的字段默认值与旧 C# 实现逐项一致。
func test_field_defaults_match_legacy_instance() -> void:
	var terrain: RefCounted = TERRAIN_INSTANCE_SCRIPT.new()
	track(terrain)
	assert_eq(terrain.get("LocalGridPos"), Vector2i.ZERO, "局部网格坐标默认必须为零。")
	assert_eq(terrain.get("BoardPosition"), Vector2.ZERO, "棋盘显示位置默认必须为零向量。")
	assert_eq(terrain.get("TerrainData"), null, "地形配置默认必须为空。")
	assert_false(bool(terrain.get("IsOccupied")), "新实例默认不得被占用。")
	assert_false(bool(terrain.get("IsHarvested")), "新实例默认不得标记为已采集。")
	assert_eq(int(terrain.get("GrowthStage")), 0, "成长阶段默认必须为 0。")
	assert_eq(
		int(terrain.get("RemainingGatheringCount")),
		-1,
		"剩余采集次数必须保持旧默认值 -1。"
	)
	assert_eq(int(terrain.get("RefreshReadyTotalTime")), 0, "冷却时间默认必须为 0。")


## 验证倍率字典协议的往返、缺失字段回退与非字典忽略。
func test_variance_protocol_round_trip_and_fallback() -> void:
	var terrain: RefCounted = TERRAIN_INSTANCE_SCRIPT.new()
	track(terrain)

	var neutral: Dictionary = terrain.call("GetEncounterVarianceSnapshot")
	assert_eq(neutral.size(), VARIANCE_FIELDS.size(), "中性快照必须包含六个倍率字段。")
	for field: String in VARIANCE_FIELDS:
		assert_true(
			is_equal_approx(float(neutral[field]), 1.0),
			"未配置浮动倍率时 %s 必须为中性值 1。" % field
		)

	terrain.call(
		"ApplyEncounterVarianceSnapshot",
		{"MaxHealth": 1.5, "Speed": 2, "MagResist": "bad"}
	)
	var partial: Dictionary = terrain.call("GetEncounterVarianceSnapshot")
	assert_true(is_equal_approx(float(partial["MaxHealth"]), 1.5), "写入的倍率必须被保留。")
	assert_true(is_equal_approx(float(partial["Speed"]), 2.0), "整数字段必须按浮点读回。")
	assert_true(
		is_equal_approx(float(partial["MagResist"]), 1.0),
		"类型不符的字段必须回退为中性值 1。"
	)
	assert_true(
		is_equal_approx(float(partial["PhysAtk"]), 1.0),
		"缺失字段必须回退为中性值 1。"
	)

	terrain.call("ApplyEncounterVarianceSnapshot", null)
	var after_null: Dictionary = terrain.call("GetEncounterVarianceSnapshot")
	assert_true(
		is_equal_approx(float(after_null["MaxHealth"]), 1.5),
		"非字典输入必须被忽略，不得清空既有倍率。"
	)


## 验证房间仓库与布局写入仍通过同一套字段与倍率协议。
func test_store_writes_position_and_variance_protocol() -> void:
	var store: Node = TERRAIN_STORE_SCRIPT.new()
	track(store)
	var terrain_data: Resource = load("res://resources/map/terrain/wood_terrain.tres")
	var variance: Dictionary = {"MaxHealth": 1.25, "PhysAtk": 0.75}
	var instance: Variant = store.call(
		"GetOrCreate",
		Vector2i(3, 4),
		Vector2i(1, 2),
		terrain_data,
		Vector2(780.0, 517.5),
		variance
	)
	assert_true(instance != null, "房间仓库必须返回地形实例。")
	assert_eq(instance.get("LocalGridPos"), Vector2i(1, 2), "局部网格坐标必须写入实例。")
	assert_eq(instance.get("BoardPosition"), Vector2(780.0, 517.5), "棋盘位置必须写入实例。")
	assert_eq(instance.get("TerrainData"), terrain_data, "地形配置必须保留原始资源身份。")

	var snapshot: Dictionary = instance.call("GetEncounterVarianceSnapshot")
	assert_true(is_equal_approx(float(snapshot["MaxHealth"]), 1.25), "浮动倍率必须写入实例。")
	assert_true(is_equal_approx(float(snapshot["PhysAtk"]), 0.75), "浮动倍率必须逐字段写入。")
	assert_true(
		is_equal_approx(float(snapshot["Speed"]), 1.0),
		"未提供的倍率字段必须保持中性值 1。"
	)


## 验证旧 C# 地形实例垫片仍保留同一套字段与倍率协议。
func test_legacy_c_shim_still_available() -> void:
	## C# 垫片已退役时本用例没有可测对象，记跳过而不是失败。
	if not CS_OPTIONAL.present(LEGACY_TERRAIN_INSTANCE_CS_PATH):
		skip(CS_OPTIONAL.SKIP_REASON)
		return
	var legacy: RefCounted = CS_OPTIONAL.script(LEGACY_TERRAIN_INSTANCE_CS_PATH).new()
	track(legacy)
	assert_eq(int(legacy.get("RemainingGatheringCount")), -1, "旧垫片默认值必须保持 -1。")
	assert_true(
		legacy.has_method("GetEncounterVarianceSnapshot"),
		"旧垫片必须保留倍率快照协议。"
	)
	assert_true(
		legacy.has_method("ApplyEncounterVarianceSnapshot"),
		"旧垫片必须保留倍率写入协议。"
	)


## 验证数据消费者只通过跨语言字段协议读写地形实例（含已切换的 GDScript 生产协调器）。
func test_csharp_consumers_use_cross_language_protocol() -> void:
	## C# 源文对照：C# 退役后 read() 返回空串，整块按条件收起而不是假通过。
	var coordinator: String = CS_OPTIONAL.read(WORLD_INTERACTION_COORDINATOR_CS_PATH)
	if not coordinator.is_empty():
		assert_true(
			coordinator.contains("TerrainInstanceProtocol.ReadTerrainData"),
			"世界交互协调器必须经协议读取地形配置。"
		)
		assert_false(
			coordinator.contains("terrain.TerrainData"),
			"世界交互协调器不得直接读取 C# 地形属性。"
		)

	var coordinator_gd: String = FileAccess.get_file_as_string(
		"res://core/gameflow/world_interaction_coordinator.gd"
	)
	assert_true(
		coordinator_gd.contains("func _read_terrain_data(terrain: RefCounted) -> Resource:"),
		"GDScript 生产协调器必须经字段协议读取地形配置。"
	)
	assert_true(
		coordinator_gd.contains("terrain.get(\"TerrainData\")"),
		"GDScript 生产协调器必须按字段名读取地形配置。"
	)
	assert_false(
		coordinator_gd.contains("terrain.TerrainData"),
		"GDScript 生产协调器不得直接读取地形属性。"
	)

	var board_controller: String = FileAccess.get_file_as_string(
		"res://core/board/board_controller.gd"
	)
	assert_true(
		board_controller.contains('terrain.get("LocalGridPos")'),
		"棋盘控制器必须经跨语言字段协议读取局部网格坐标。"
	)
	assert_false(
		board_controller.contains("terrainInstance.LocalGridPos"),
		"棋盘控制器不得经具体类型直接读取地形属性。"
	)

	var presenter: String = FileAccess.get_file_as_string(
		"res://core/map/UIRoomBoardPresenter.gd"
	)
	assert_true(
		presenter.contains('terrain.get("TerrainData")'),
		"房间展示层必须经跨语言字段协议读取地形配置。"
	)
	assert_true(
		presenter.contains('terrain.get("IsHarvested")'),
		"房间展示层必须经跨语言字段协议读取采集状态。"
	)
	assert_false(presenter.contains("terrain.TerrainData"), "房间展示层不得经具体类型读取地形属性。")
	assert_false(presenter.contains("terrain.IsHarvested"), "房间展示层不得经具体类型读取地形属性。")

	var context_source: String = CS_OPTIONAL.read(WORLD_INTERACTION_CONTEXT_CS_PATH)
	if not context_source.is_empty():
		assert_true(
			context_source.contains("RefCounted Terrain"),
			"交互上下文必须只保留两种地形实现共同继承的 RefCounted。"
		)

	var protocol_source: String = CS_OPTIONAL.read(TERRAIN_INSTANCE_PROTOCOL_CS_PATH)
	if not protocol_source.is_empty():
		assert_true(protocol_source.contains("is TerrainInstance legacy"), "字段协议必须保留旧垫片分支。")
		assert_true(protocol_source.contains("terrain.Get(fieldName)"), "字段协议必须支持 GDScript 字段读取。")


## 验证遭遇缩放不再依赖 C# 静态单例，而是经节点方法协议调用生产 GDScript 管理器。
func test_encounter_scaling_uses_node_protocol() -> void:
	# 生产门面已经是 GDScript，这里同时锁定它的缩放协议与旧 C# 垫片的行为一致。
	var production_source: String = FileAccess.get_file_as_string(
		"res://core/application/gameplay_port.gd"
	)
	assert_true(
		production_source.contains("ScaleEncounterMonsters"),
		"生产 GDScript 门面必须调用遭遇管理器缩放协议。"
	)

	var port_source: String = CS_OPTIONAL.read(GAMEPLAY_PORT_CS_PATH)
	if not port_source.is_empty():
		assert_true(
			port_source.contains("_encounterManager.Call(\"ScaleEncounterMonsters\""),
			"旧 C# 门面兼容垫片必须经稳定方法协议调用遭遇管理器。"
		)
		assert_false(
			port_source.contains("EncounterManager.Instance"),
			"旧 C# 门面垫片不得继续依赖只为 C# 管理器赋值的静态单例。"
		)
		assert_true(
			port_source.contains("EncounterManagerPath"),
			"旧 C# 门面垫片必须导出遭遇管理器路径，默认指向同级节点。"
		)
