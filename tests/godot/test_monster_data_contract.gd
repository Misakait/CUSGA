@tool
extends McpTestSuite

## 怪物数据（MonsterData）生产迁移契约套件。
##
## 套件锁定四件事：53 个怪物资产改用 GDScript 怪物数据脚本且序列化字段未变、
## 旧 C# 垫片与跨语言字段协议同时保留、C# 与 GDScript 消费方都不再按旧类型过滤怪物、
## 场景与战斗脚本的怪物数组边界已放宽到通用 Resource。
## 运行时的“怪物真的被生成并读回数值”由运行中的游戏经 game_eval 验证。
## C# 物理退役后，依赖垫片的对照断言经 CS_OPTIONAL 自动退场（见 tests/godot/csharp_optional.gd）。

## 本批 GDScript 怪物数据脚本路径。
const MONSTER_DATA_SCRIPT_PATH: String = "res://resources/monster/monster_data.gd"
## 本批 GDScript 怪物数据脚本 UID。
const MONSTER_DATA_SCRIPT_UID: String = "uid://buhigatdeqss6"
## 旧 C# 怪物数据兼容垫片路径。
const LEGACY_MONSTER_DATA_PATH: String = "res://resources/monster/MonsterData.cs"
## 跨语言怪物字段协议路径。
const PROTOCOL_PATH: String = "res://resources/monster/MonsterDataProtocol.cs"
## 怪物资产目录。
const MONSTER_DIR: String = "res://resources/monster"
## 怪物场景路径。
const MONSTER_SCENE_PATH: String = "res://scenes/monster_scenes/monster.tscn"
## 战斗场景路径。
const BATTLE_SCENE_PATH: String = "res://scenes/battle_scenes/battle.tscn"
## 测试怪物资产路径。
const TEST_MONSTER_PATH: String = "res://resources/monster/test_monster_1.tres"
## 生产怪物资产路径。
const PRODUCTION_MONSTER_PATH: String = "res://resources/monster/merchant_heixinyongbing.tres"
## 生产怪物资产数量，必须与迁移前保持一致。
const MONSTER_ASSET_COUNT: int = 53
## C# 可选助手：C# 退役后没有对照源文，相关用例记跳过而不是假通过或 0 断言失败。
const CS_OPTIONAL := preload("res://tests/godot/csharp_optional.gd")


## 返回 GodotAI 使用的稳定套件名称。
##
## @return 怪物数据契约套件名。
func suite_name() -> String:
	return "monster_data_contract"


## 验证全部怪物资产改用 GDScript 怪物数据且不再引用旧 C# 脚本。
func test_all_monster_assets_switched_to_gdscript() -> void:
	var directory: DirAccess = DirAccess.open(MONSTER_DIR)
	assert_true(directory != null, "必须能打开怪物资产目录。")
	if directory == null:
		return

	var asset_count: int = 0
	var missing_script: Array[String] = []
	var legacy_hits: Array[String] = []
	var script_class_hits: Array[String] = []
	directory.list_dir_begin()
	var file_name: String = directory.get_next()
	while file_name != "":
		if not directory.current_is_dir() and file_name.ends_with(".tres"):
			asset_count += 1
			var text: String = FileAccess.get_file_as_string(MONSTER_DIR + "/" + file_name)
			if not text.contains(MONSTER_DATA_SCRIPT_PATH):
				missing_script.append(file_name)
			if text.contains("monster/MonsterData.cs"):
				legacy_hits.append(file_name)
			if text.contains('script_class="MonsterData"'):
				script_class_hits.append(file_name)
		file_name = directory.get_next()
	directory.list_dir_end()

	assert_eq(asset_count, MONSTER_ASSET_COUNT, "怪物资产数量必须保持不变。")
	assert_true(missing_script.is_empty(), "以下资产未指向 GDScript 怪物数据：%s" % str(missing_script))
	assert_true(legacy_hits.is_empty(), "以下资产仍引用旧 C# 怪物数据：%s" % str(legacy_hits))
	assert_true(
		script_class_hits.is_empty(),
		"以下资产仍声明旧 C# script_class：%s" % str(script_class_hits)
	)


## 验证旧 C# 垫片与跨语言字段协议同时保留。
func test_legacy_shim_and_protocol_kept() -> void:
	## 本用例整体只对照 C# 垫片与 C# 协议源文；C# 退役后记跳过。
	if not CS_OPTIONAL.present(LEGACY_MONSTER_DATA_PATH):
		skip(CS_OPTIONAL.SKIP_REASON)
		return
	assert_true(FileAccess.file_exists(LEGACY_MONSTER_DATA_PATH), "旧 C# 怪物数据垫片必须保留。")
	assert_true(FileAccess.file_exists(PROTOCOL_PATH), "跨语言怪物字段协议必须存在。")

	var legacy: String = FileAccess.get_file_as_string(LEGACY_MONSTER_DATA_PATH)
	for field: String in [
		"MonsterName", "InitialAttributes", "ElementalProperty", "ModelScene",
		"LootTable", "BehaviorTreeScene", "Faction", "SkillSet",
	]:
		assert_true(legacy.contains(field), "旧 C# 垫片必须保留字段 %s。" % field)
	assert_true(legacy.contains("enum MonsterFaction"), "旧 C# 阵营枚举必须保留。")

	var protocol: String = FileAccess.get_file_as_string(PROTOCOL_PATH)
	assert_true(
		protocol.contains('ScriptPath = "res://resources/monster/monster_data.gd"'),
		"协议必须声明生产脚本路径。"
	)
	assert_true(protocol.contains("FilterMonsters"), "协议必须提供跨语言怪物数组过滤。")
	assert_true(protocol.contains("value is MonsterData"), "协议必须保留旧 C# 强类型分支。")
	assert_true(
		protocol.contains("?.ResourcePath == ScriptPath"),
		"协议必须按脚本路径识别 GDScript 怪物数据。"
	)
	assert_true(protocol.contains("ReadMonsterName"), "协议必须提供名称读取。")
	assert_true(protocol.contains("ReadElementalProperty"), "协议必须提供五行属性读取。")
	assert_true(protocol.contains("ReadFaction"), "协议必须提供阵营读取。")


## 验证 GDScript 怪物数据的默认值与旧 C# 字段默认值一致。
func test_gdscript_defaults_match_legacy_fields() -> void:
	var data_script: GDScript = load(MONSTER_DATA_SCRIPT_PATH)
	assert_true(data_script != null, "必须能加载 GDScript 怪物数据脚本。")
	var data: Resource = data_script.new()
	assert_eq(str(data.get("MonsterName")), "未知怪物", "名称默认值必须与旧 C# 一致。")
	assert_eq(int(data.get("ElementalProperty")), 0, "五行属性默认值必须与旧 C# 一致。")
	assert_eq(int(data.get("Faction")), 0, "阵营默认值必须与旧 C# 一致。")
	assert_eq(data.get("ModelScene"), null, "外观预制体默认值必须为 null。")
	assert_eq(data.get("LootTable"), null, "掉落表默认值必须为 null。")
	assert_eq(data.get("SkillSet"), null, "技能集合默认值必须为 null。")
	assert_eq(data.get("InitialAttributes"), null, "初始属性默认值为 null，由消费方回退旧默认值。")
	assert_eq(
		str(data.get_script().resource_path),
		MONSTER_DATA_SCRIPT_PATH,
		"实例必须由 GDScript 怪物数据脚本创建。"
	)


## 验证测试与生产怪物资产的序列化字段仍在。
func test_serialized_monster_fields_preserved() -> void:
	var test_monster: Resource = load(TEST_MONSTER_PATH)
	assert_true(test_monster != null, "必须能加载测试怪物资产。")
	assert_eq(
		str(test_monster.get_script().resource_path),
		MONSTER_DATA_SCRIPT_PATH,
		"测试怪物资产必须使用 GDScript 怪物数据脚本。"
	)
	assert_eq(str(test_monster.get("MonsterName")), "测试怪物1", "测试怪物名称必须保持不变。")
	assert_eq(int(test_monster.get("ElementalProperty")), 3, "测试怪物五行属性必须保持不变。")
	assert_true(test_monster.get("InitialAttributes") != null, "测试怪物必须保留初始属性子资源。")
	assert_true(test_monster.get("LootTable") != null, "测试怪物必须保留掉落表子资源。")
	var skill_set: Resource = test_monster.get("SkillSet")
	assert_true(skill_set != null, "测试怪物必须保留技能集合子资源。")
	if skill_set != null:
		var entries: Variant = skill_set.get("Skills")
		assert_true(entries is Array, "技能集合必须保留 Skills 数组字段。")
		assert_eq((entries as Array).size(), 1, "测试怪物技能条目数量必须保持不变。")

	var production: Resource = load(PRODUCTION_MONSTER_PATH)
	assert_true(production != null, "必须能加载生产怪物资产。")
	assert_eq(
		str(production.get_script().resource_path),
		MONSTER_DATA_SCRIPT_PATH,
		"生产怪物资产必须使用 GDScript 怪物数据脚本。"
	)
	assert_true(str(production.get("MonsterName")) != "", "生产怪物必须保留名称。")
	assert_true(production.get("SkillSet") != null, "生产怪物必须保留技能集合。")
	assert_true(int(production.get("Faction")) >= 0, "生产怪物必须保留阵营整数值。")


## 验证 C# 消费方改用跨语言协议而不是旧 C# 类型过滤。
func test_csharp_consumers_use_cross_language_protocol() -> void:
	## 本用例整体只对照 C# 消费者源文；C# 退役后记跳过。
	if not CS_OPTIONAL.present("res://entities/Monster.cs"):
		skip(CS_OPTIONAL.SKIP_REASON)
		return
	var monster: String = CS_OPTIONAL.read("res://entities/Monster.cs")
	assert_true(monster.contains("public Resource BaseData"), "Monster.BaseData 必须放宽到 Resource。")
	assert_true(
		monster.contains("public void Initialize(Resource data)"),
		"Monster.Initialize 必须接受跨语言 Resource。"
	)
	assert_true(monster.contains("MonsterDataProtocol.ReadMonsterName"), "Monster 必须经协议读名称。")
	assert_true(monster.contains("MonsterDataProtocol.ReadFaction"), "Monster 必须经协议读阵营。")
	assert_true(
		monster.contains('MonsterDataProtocol.ReadResourceField(data, "InitialAttributes")'),
		"Monster 必须经协议读初始属性并回退旧默认值。"
	)

	var damage_receiver: String = FileAccess.get_file_as_string(
		"res://entities/components/DamageReceiverComponent.cs"
	)
	assert_true(
		damage_receiver.contains("MonsterDataProtocol.ReadElementalProperty"),
		"属性克制必须经协议读取怪物五行属性。"
	)

	for path: String in [
		"res://core/application/GameplayPort.cs",
		"res://core/gameflow/WorldInteractionCoordinator.cs",
		"res://core/gameflow/WorldCombatScenePresenter.cs",
		"res://core/gameflow/TerrainInteractionExecutor.cs",
		"res://core/map/PassageGuardMonsterResolver.cs",
	]:
		var text: String = FileAccess.get_file_as_string(path)
		assert_false(
			text.contains("is MonsterData"),
			"%s 不得继续用旧 C# 类型过滤怪物。" % path
		)
		assert_false(
			text.contains("Array<MonsterData>"),
			"%s 不得继续使用旧 C# 强类型怪物数组。" % path
		)

	var resolver: String = FileAccess.get_file_as_string(
		"res://core/map/PassageGuardMonsterResolver.cs"
	)
	assert_true(resolver.contains("MonsterDataProtocol.IsMonsterData"), "驻守解析器必须经协议判定。")


## 验证场景与战斗脚本的怪物数组边界放宽到通用 Resource。
func test_scenes_and_battle_scripts_use_resource_boundary() -> void:
	var monster_scene: String = FileAccess.get_file_as_string(MONSTER_SCENE_PATH)
	assert_true(monster_scene.contains(MONSTER_DATA_SCRIPT_PATH), "怪物场景必须引用 GDScript 怪物数据。")
	assert_false(monster_scene.contains("monster/MonsterData.cs"), "怪物场景不得引用旧 C# 脚本。")
	assert_true(
		monster_scene.contains(MONSTER_DATA_SCRIPT_UID),
		"怪物场景的自定义类型元数据必须指向新 UID。"
	)

	var battle_scene: String = FileAccess.get_file_as_string(BATTLE_SCENE_PATH)
	assert_false(battle_scene.contains("monster/MonsterData.cs"), "战斗场景不得引用旧 C# 脚本。")
	assert_true(
		battle_scene.contains("starting_monster_data = Array[Resource]("),
		"战斗场景的初始怪物数组必须改为通用 Resource 数组。"
	)
	assert_true(
		battle_scene.contains("starting_deck_data = Array[Resource]("),
		"战斗场景的初始卡组数组必须保持通用 Resource 数组。"
	)

	var battle_manager: String = FileAccess.get_file_as_string(
		"res://scripts/battle_scripts/battle_manager.gd"
	)
	assert_true(
		battle_manager.contains("@export var starting_monster_data: Array[Resource]"),
		"战斗管理器必须接受跨语言怪物数组。"
	)


## 验证 GDScript 消费方同时识别两种怪物数据实现。
func test_gdscript_consumers_accept_both_implementations() -> void:
	for path: String in [
		"res://core/application/encounter_manager.gd",
		"res://core/application/gameplay_port.gd",
		"res://core/gameflow/world_interaction_coordinator.gd",
		"res://resources/encounters/gathering_encounter_result.gd",
	]:
		var text: String = FileAccess.get_file_as_string(path)
		assert_true(text.contains("MONSTER_DATA_REQUIRED_FIELDS"), "%s 必须声明跨语言字段协议。" % path)
		assert_true(text.contains("func _is_monster_data("), "%s 必须共享跨语言判定。" % path)
		assert_false(text.contains("is MonsterData"), "%s 不得再按旧 C# 类型判定。" % path)
		assert_false(text.contains("as MonsterData"), "%s 不得再强制转换旧 C# 类型。" % path)
		assert_false(
			text.contains("Array[MonsterData]"),
			"%s 不得再使用旧 C# 强类型怪物数组。" % path
		)

	var encounter_manager: String = FileAccess.get_file_as_string(
		"res://core/application/encounter_manager.gd"
	)
	assert_true(
		encounter_manager.contains("func _new_monster_like("),
		"遭遇缩放必须按源脚本创建怪物副本。"
	)
	assert_true(
		encounter_manager.contains("func _scale_monster("),
		"遭遇缩放入口必须保留原名。"
	)
	assert_true(
		encounter_manager.contains("source: Resource,"),
		"遭遇缩放必须接受通用 Resource 怪物。"
	)
