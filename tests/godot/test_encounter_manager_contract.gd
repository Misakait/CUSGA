@tool
extends McpTestSuite

## 采集遭遇管理器 GDScript 生产边界契约套件。
##
## 套件同时锁定生产场景脚本路径、概率公式、倍率缩放公式、跨语言结果协议、
## 旧 C# 兼容垫片保留状态和 C# 消费者的动态调用协议，避免迁移回退到旧节点。

const ENCOUNTER_MANAGER_SCRIPT: GDScript = preload("res://core/application/encounter_manager.gd")
const GATHERING_RESULT_SCRIPT: GDScript = preload("res://resources/encounters/gathering_encounter_result.gd")
const GATHERING_RULE_SCRIPT: GDScript = preload("res://resources/encounters/gathering_encounter_rule.gd")
const STARTING_STATS_SCRIPT: GDScript = preload("res://resources/stats/starting_stats.gd")
const TERRAIN_STORE_SCRIPT: GDScript = preload("res://core/map/room_terrain_store.gd")
## 迁移后的怪物数据 GDScript 载体（C# 全局类 MonsterData 已随物理退役删除）。
const MONSTER_DATA_SCRIPT: GDScript = preload("res://resources/monster/monster_data.gd")

## 固定随机种子，让概率分支在聚焦测试中保持可复现。
const RANDOM_SEED: int = 1234


## 返回套件名称，供 MCP 按批次筛选测试。
func suite_name() -> String:
	return "encounter_manager_contract"


## 提供时间节点协议，替代 /root/TimeSystem Autoload。
class FakeTimeSystem extends Node:
	## 当前是否夜晚。
	var IsNight: bool = false
	## 当前游戏天数。
	var CurrentDay: int = 1


## 提供生产 TerrainInstance 的倍率快照协议。
class FakeTerrain extends RefCounted:
	## GetEncounterVarianceSnapshot 返回的字段。
	var snapshot: Dictionary = {}

	## 返回配置好的倍率快照。
	## @return 六个倍率字段的字典。
	func GetEncounterVarianceSnapshot() -> Dictionary:
		return snapshot


## 提供缺少倍率快照协议的旧地形对象。
class LegacyTerrain extends RefCounted:
	pass


## C# 可选助手：C# 退役后安全收起跨语言对照，避免解析期错误与「空源文假通过」。
const CS_OPTIONAL := preload("res://tests/godot/csharp_optional.gd")


## 验证生产 Main 场景已切换到 GDScript 管理器，旧 C# 实现仍作为垫片保留。
func test_production_scene_and_compat_shims() -> void:
	var main_scene := FileAccess.get_file_as_string("res://scenes/Main.tscn")
	assert_true(
		main_scene.contains('path="res://core/application/encounter_manager.gd"'),
		"生产 Main 场景必须使用 GDScript 遭遇管理器。"
	)
	assert_false(main_scene.contains("EncounterManager.cs"), "生产 Main 场景不得继续引用旧 C# 遭遇管理器。")
	for compat_path: String in [
		"res://core/application/EncounterManager.cs",
		"res://core/application/EncounterMonsterScaler.cs",
		"res://resources/encounters/GatheringEncounterResult.cs",
	]:
		## C# 垫片仍在时必须可加载；C# 退役后这些路径按条件收起（不再有可加载对象）。
		assert_true(
			not CS_OPTIONAL.present(compat_path) or load(compat_path) != null,
			"%s 必须作为兼容垫片保留并且可以加载。" % compat_path
		)


## 验证 C# 消费者只依赖稳定方法协议，不再编译期引用具体类型。
func test_consumers_use_dynamic_protocol() -> void:
	var coordinator_source := FileAccess.get_file_as_string("res://core/gameflow/world_interaction_coordinator.gd")
	## C# 源文对照：C# 退役后 read() 返回空串，C# 侧断言按条件收起。
	var executor_source := CS_OPTIONAL.read("res://core/gameflow/TerrainInteractionExecutor.cs")
	var port_source := FileAccess.get_file_as_string("res://core/application/gameplay_port.gd")
	assert_false(coordinator_source.contains("as EncounterManager"), "协调器不得声明具体 EncounterManager 字段。")
	assert_true(
		coordinator_source.contains('_encounter_manager.call("ScaleEncounterMonsters"'),
		"协调器必须按 ScaleEncounterMonsters 方法协议调用倍率入口。"
	)
	if not executor_source.is_empty():
		assert_true(executor_source.contains("Node encounterManager"), "地形执行器必须以 Node 持有遭遇管理器。")
		assert_true(
			executor_source.contains('"ResolveGatheringEncounter"'),
			"地形执行器必须按 ResolveGatheringEncounter 方法协议结算遭遇。"
		)
		assert_true(
			executor_source.contains("ConvertEncounterResult"),
			"地形执行器必须把跨语言遭遇结果转换为旧 C# 结果类型。"
		)
	assert_false(port_source.contains("EncounterManager.Instance"), "生产 GDScript 门面不得依赖 C# 静态单例。")

	var terrain_source := FileAccess.get_file_as_string("res://resources/interaction/terrain_instance.gd")
	assert_true(
		terrain_source.contains("GetEncounterVarianceSnapshot"),
		"生产地形实例必须为 GDScript 提供稳定的倍率快照协议。"
	)
	var legacy_terrain_source := CS_OPTIONAL.read("res://resources/interaction/TerrainInstance.cs")
	if not legacy_terrain_source.is_empty():
		assert_true(
			legacy_terrain_source.contains("GetEncounterVarianceSnapshot"),
			"旧 C# 地形实例兼容垫片必须保留同一套倍率快照协议。"
		)


## 验证导出默认值与旧 C# 管理器保持一致。
func test_export_defaults_match_legacy_manager() -> void:
	var manager: Node = ENCOUNTER_MANAGER_SCRIPT.new()
	track(manager)
	assert_eq((manager.get("GatheringRules") as Array).size(), 0, "采集规则列表默认必须为空。")
	assert_true(
		is_equal_approx(float(manager.get("BaseGatheringSpawnChance")), 0.05),
		"基础遭遇概率必须沿用 0.05。"
	)
	assert_true(
		is_equal_approx(float(manager.get("NightChanceMultiplier")), 6.0),
		"夜晚遭遇倍率必须沿用 6.0。"
	)
	for growth_field: String in [
		"MaxHealthDailyGrowth", "PhysAtkDailyGrowth", "PhysDefDailyGrowth",
		"MagPowerDailyGrowth", "MagResistDailyGrowth", "SpeedDailyGrowth",
	]:
		assert_true(
			is_equal_approx(float(manager.get(growth_field)), 0.0),
			"%s 默认必须为 0。" % growth_field
		)


## 验证采集遭遇的命中、未命中、结果载荷与额外倍率连乘。
func test_gathering_encounter_probability_and_payload() -> void:
	seed(RANDOM_SEED)
	var manager: Node = ENCOUNTER_MANAGER_SCRIPT.new()
	track(manager)
	var monster: Resource = MONSTER_DATA_SCRIPT.new()
	monster.set("MonsterName", "测试木精")

	var matched_rule: Resource = GATHERING_RULE_SCRIPT.new()
	matched_rule.set("TriggerTag", &"wood")
	matched_rule.get("MonsterToSpawn").append(monster)
	matched_rule.set("SpawnMessage", "林中传来响动")

	var other_rule: Resource = GATHERING_RULE_SCRIPT.new()
	other_rule.set("TriggerTag", &"stone")
	other_rule.get("MonsterToSpawn").append(monster)

	var rules: Array[Resource] = [matched_rule, other_rule]
	manager.set("GatheringRules", rules)
	manager.set("BaseGatheringSpawnChance", 1.0)

	var hit: RefCounted = manager.call("ResolveGatheringEncounter", &"wood", 1.0)
	assert_true(bool(hit.get("Triggered")), "概率为 1 且标签匹配时必须触发遭遇。")
	var hit_monsters: Array = hit.get("MonsterToSpawn")
	assert_eq(hit_monsters.size(), 1, "触发结果必须携带原怪物数量。")
	assert_true(hit_monsters[0] == monster, "触发结果必须保留 MonsterData Resource 身份。")
	assert_eq(String(hit.get("SpawnMessage")), "林中传来响动", "触发结果必须保留规则提示文本。")

	var miss: RefCounted = manager.call("ResolveGatheringEncounter", &"metal", 1.0)
	assert_false(bool(miss.get("Triggered")), "没有匹配标签时不得触发遭遇。")
	assert_eq((miss.get("MonsterToSpawn") as Array).size(), 0, "未触发结果不得携带怪物。")
	assert_eq(String(miss.get("SpawnMessage")), "", "未触发结果不得携带提示文本。")

	var empty_tag: RefCounted = manager.call("ResolveGatheringEncounter", &"", 1.0)
	assert_false(bool(empty_tag.get("Triggered")), "空标签必须直接返回未触发结果。")

	matched_rule.set("ExtraChanceMultiplier", 0.0)
	var blocked: RefCounted = manager.call("ResolveGatheringEncounter", &"wood", 1.0)
	assert_false(bool(blocked.get("Triggered")), "额外概率倍率为 0 时不得触发遭遇。")


## 验证结果对象与旧 C# GatheringEncounterResult 的字段协议一致。
func test_result_protocol_matches_legacy_type() -> void:
	var result: RefCounted = GATHERING_RESULT_SCRIPT.new()
	result.Setup(false, [], "")
	assert_false(bool(result.get("Triggered")), "未触发结果的 Triggered 必须为 false。")
	assert_eq((result.get("MonsterToSpawn") as Array).size(), 0, "未触发结果不得携带怪物。")
	assert_eq(String(result.get("SpawnMessage")), "", "未触发结果的提示文本必须为空。")

	var monster: Resource = MONSTER_DATA_SCRIPT.new()
	monster.set("MonsterName", "测试落石兽")
	result.Setup(true, [monster, RefCounted.new()], "岩壁崩塌")
	assert_true(bool(result.get("Triggered")), "已触发结果必须置位 Triggered。")
	assert_eq((result.get("MonsterToSpawn") as Array).size(), 1, "结果必须过滤非 MonsterData 元素。")
	assert_eq(String(result.get("SpawnMessage")), "岩壁崩塌", "结果必须保留提示文本。")


## 验证怪物缩放公式、副本语义、中性倍率回退和空输入。
func test_monster_scaling_matches_legacy_scaler() -> void:
	var manager: Node = ENCOUNTER_MANAGER_SCRIPT.new()
	track(manager)
	var time_system := FakeTimeSystem.new()
	time_system.CurrentDay = 3
	track(time_system)
	manager.set("TimeSystemNode", time_system)
	manager.set("MaxHealthDailyGrowth", 0.1)

	var stats: Resource = STARTING_STATS_SCRIPT.new()
	stats.set("BaseMaxHealth", 1000.0)
	stats.set("BasePhysAtk", 100.0)
	stats.set("PhysAtkGrowth", 25.0)

	var monster: Resource = MONSTER_DATA_SCRIPT.new()
	monster.set("MonsterName", "测试岩兽")
	monster.set("InitialAttributes", stats)

	var terrain := FakeTerrain.new()
	terrain.snapshot = {"MaxHealth": 2.0, "PhysAtk": 0.5}

	var scaled: Array = manager.call("ScaleEncounterMonsters", terrain, [monster, null])
	assert_eq(scaled.size(), 1, "缩放必须跳过空怪物并保持原顺序。")
	var scaled_monster: Resource = scaled[0]
	assert_true(scaled_monster != null and scaled_monster != monster, "缩放必须返回新的怪物副本。")
	assert_eq(String(scaled_monster.get("MonsterName")), "测试岩兽", "副本必须保留怪物名称。")
	var scaled_stats: Resource = scaled_monster.get("InitialAttributes")
	# 生命上限 = 1000 * 2.0（地形）* (1 + 2 * 0.1)（第 3 天成长） = 2400
	assert_true(
		is_equal_approx(float(scaled_stats.get("BaseMaxHealth")), 2400.0),
		"生命上限必须按地形与天数倍率缩放。"
	)
	assert_true(
		is_equal_approx(float(scaled_stats.get("BasePhysAtk")), 50.0),
		"物理攻击必须按地形倍率缩放。"
	)
	assert_true(
		is_equal_approx(float(scaled_stats.get("PhysAtkGrowth")), 25.0),
		"非缩放字段必须原样复制。"
	)
	assert_true(
		is_equal_approx(float(scaled_stats.get("BaseCritDamage")), 1.5),
		"暴击伤害等默认字段必须原样复制。"
	)
	assert_true(
		is_equal_approx(float(stats.get("BaseMaxHealth")), 1000.0),
		"缩放不得修改原始属性资源。"
	)

	var identity_scaled: Array = manager.call("ScaleEncounterMonsters", LegacyTerrain.new(), [monster])
	# 使用字段协议读取，避免把断言绑死在某一种怪物数据实现上。
	var identity_stats: Resource = identity_scaled[0].get("InitialAttributes")
	assert_true(
		is_equal_approx(float(identity_stats.get("BaseMaxHealth")), 1200.0),
		"缺少倍率协议时必须按中性地形倍率缩放。"
	)
	assert_true(
		is_equal_approx(float(identity_stats.get("BasePhysAtk")), 100.0),
		"缺少倍率协议时物理攻击必须保持原值。"
	)

	assert_eq(manager.call("ScaleEncounterMonsters", null, []).size(), 0, "空数组必须返回空数组。")
	assert_eq(manager.call("ScaleEncounterMonsters", null, [null]).size(), 0, "全空数组必须被过滤为空。")

	# 生产怪物数据已切换到 GDScript：同一缩放入口必须同时接受 GDScript 实现，并按源脚本产出副本。
	var gdscript_monster: Resource = load("res://resources/monster/test_monster_1.tres")
	assert_true(gdscript_monster != null, "测试必须能加载 GDScript 怪物数据资产。")
	if gdscript_monster != null:
		var gdscript_scaled: Array = manager.call(
			"ScaleEncounterMonsters",
			terrain,
			[gdscript_monster]
		)
		assert_eq(gdscript_scaled.size(), 1, "GDScript 怪物数据必须参与缩放。")
		if gdscript_scaled.size() == 1:
			var gdscript_copy: Resource = gdscript_scaled[0]
			assert_true(gdscript_copy != gdscript_monster, "GDScript 怪物数据缩放必须返回新副本。")
			assert_eq(
				gdscript_copy.get_script().resource_path,
				"res://resources/monster/monster_data.gd",
				"GDScript 怪物数据副本必须沿用同一脚本。"
			)
			assert_eq(
				String(gdscript_copy.get("MonsterName")),
				"测试怪物1",
				"GDScript 怪物数据副本必须保留怪物名称。"
			)
			assert_true(
				gdscript_copy.get("InitialAttributes") != null,
				"GDScript 怪物数据副本必须保留缩放后的初始属性。"
			)


## 验证 GDScript 地形仓库创建的地形实例已提供可读的倍率快照协议。
func test_production_terrain_instance_snapshot_bridge() -> void:
	var store: Node = TERRAIN_STORE_SCRIPT.new()
	track(store)
	var terrain_data: Resource = load("res://resources/map/terrain/wood_terrain.tres")
	assert_true(terrain_data != null, "测试必须能加载生产地形资源。")
	var terrain: Variant = store.call("GetOrCreate", Vector2i.ZERO, Vector2i.ZERO, terrain_data)
	assert_true(terrain != null, "生产地形仓库必须返回地形实例。")
	assert_true(
		terrain.has_method("GetEncounterVarianceSnapshot"),
		"生产 TerrainInstance 必须暴露 GDScript 可读的倍率快照方法。"
	)
	var snapshot: Dictionary = terrain.call("GetEncounterVarianceSnapshot")
	for field: String in ["MaxHealth", "PhysAtk", "PhysDef", "MagPower", "MagResist", "Speed"]:
		assert_true(snapshot.has(field), "倍率快照必须包含 %s 字段。" % field)
		assert_true(
			is_equal_approx(float(snapshot[field]), 1.0),
			"未配置浮动倍率时 %s 必须为中性值 1。" % field
		)
