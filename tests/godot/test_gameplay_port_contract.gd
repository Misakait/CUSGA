@tool
extends McpTestSuite

## GameplayPort GDScript 生产实现的稳定信号、节点解析和遭遇转换契约。

const PORT_SCRIPT: GDScript = preload("res://core/application/gameplay_port.gd")
## 生产 GDScript SkillCardData，用于验证动态技能卡边界与旧 C# 兼容输入。
const SKILL_CARD_DATA_SCRIPT: GDScript = preload("res://resources/item/card/skill_card_data.gd")
## 保留的 C# SkillCardData 脚本，用于验证生产切换后仍接受旧兼容输入。
const LEGACY_SKILL_CARD_DATA_SCRIPT: Script = preload("res://resources/item/card/SkillCardData.cs")
## 第一张用于验证卡组顺序与 Resource 身份的生产 GDScript SkillCardData。
const SKILL_CARD_A: Resource = preload("res://resources/skill_cards/test_card_1.tres")
## 第二张用于验证卡组过滤不会改变合法元素相对顺序的生产 GDScript SkillCardData。
const SKILL_CARD_B: Resource = preload("res://resources/skill_cards/test_card_2.tres")
## 技能卡生产资产目录；当前表格同步链固定维护 69 张卡。
const PRODUCTION_SKILL_CARD_DIRECTORY: String = "res://resources/skill_cards"
## 生产技能卡数量；变化时必须由卡表资产变更同步更新。
const PRODUCTION_SKILL_CARD_COUNT: int = 69
## 已迁移的技能卡脚本路径。
const PRODUCTION_SKILL_CARD_SCRIPT_PATH: String = "res://resources/item/card/skill_card_data.gd"
## 旧 C# 技能卡脚本路径，仅允许兼容源码和对照测试继续引用。
const LEGACY_SKILL_CARD_SCRIPT_PATH: String = "res://resources/item/card/SkillCardData.cs"
## 第一只用于验证怪物数组过滤和倍率调用输入的 C# MonsterData。
const MONSTER_A: Resource = preload("res://resources/monster/tree_kumujing.tres")
## 第二只用于验证倍率调用输出顺序与 Resource 身份的 C# MonsterData。
const MONSTER_B: Resource = preload("res://resources/monster/anvil_cuihuotiewei.tres")


## 提供玩家组件树和最小方法协议的测试玩家。
class FakePlayer extends Node:
	## 玩家接收堆叠的累计次数。
	var add_count: int = 0
	## 最近一次交给玩家的原始堆叠引用。
	var last_stack: Variant = null

	## 模拟 Player 的稳定加物品入口。
	## @param stack 要加入的兼容堆叠对象。
	## @return 非空堆叠返回 true。
	func TryAddItemToInventory(stack: Variant) -> bool:
		add_count += 1
		last_stack = stack
		return stack != null


## 提供卡组读取协议的测试节点。
class FakeBattleDeck extends Node:
	## GetSkillCards 返回的动态数组，可混入无效元素验证过滤。
	var cards: Array = []

	## 返回当前测试卡组快照。
	## @return 保持配置顺序的动态数组。
	func GetSkillCards() -> Array:
		return cards


## 模拟生产 Main 中负责过滤动态数组并调用 EncounterManager 的同级 C# 协调器。
class FakeWorldInteractionCoordinator extends Node:
	## ScaleEncounterMonsters 的累计调用次数。
	var scale_call_count: int = 0
	## 最近一次倍率调用收到的地形引用。
	var last_terrain: Variant = null
	## 最近一次倍率调用收到的已过滤怪物数组。
	var last_monsters: Array[MonsterData] = []

	## 记录倍率调用并反转返回顺序，让测试能区分输入与缩放输出。
	## @param terrain 当前地形实例。
	## @param monsters GameplayPort 已过滤的强类型怪物数组。
	## @return 保持 Resource 身份但反转顺序的强类型数组。
	func ScaleEncounterMonsters(terrain: Variant, monsters: Array) -> Array[MonsterData]:
		scale_call_count += 1
		last_terrain = terrain
		last_monsters.clear()
		for raw_monster: Variant in monsters:
			if raw_monster is MonsterData:
				last_monsters.append(raw_monster)
		var scaled: Array[MonsterData] = last_monsters.duplicate()
		scaled.reverse()
		return scaled


## 构造带玩家组件树、同级 EncounterManager、仓库和 GameplayPort 的最小场景。
## @return 包含根节点、玩家、卡组、管理器和端口的夹具字典。
func _build_fixture() -> Dictionary:
	var root := Node.new()
	root.name = "GameplayPortFixture"
	var player := FakePlayer.new()
	player.name = "Player"
	var components := Node.new()
	components.name = "Components"
	for component_name: String in ["InventoryComponent", "HealthComponent", "CraftingComponent"]:
		var component := Node.new()
		component.name = component_name
		components.add_child(component)
	var battle_deck := FakeBattleDeck.new()
	battle_deck.name = "BattleDeckComponent"
	var legacy_skill_card := LEGACY_SKILL_CARD_DATA_SCRIPT.new() as Resource
	legacy_skill_card.set("CardName", "C# 兼容技能卡")
	var gdscript_skill_card := SKILL_CARD_DATA_SCRIPT.new() as Resource
	gdscript_skill_card.set("CardName", "GDScript 技能卡")
	battle_deck.cards = [SKILL_CARD_A, legacy_skill_card, RefCounted.new(), gdscript_skill_card, SKILL_CARD_B]
	components.add_child(battle_deck)
	player.add_child(components)
	root.add_child(player)
	var warehouse := Node.new()
	warehouse.name = "GlobalWarehouse"
	root.add_child(warehouse)
	var encounter_scaler := FakeWorldInteractionCoordinator.new()
	encounter_scaler.name = "WorldInteractionCoordinator"
	root.add_child(encounter_scaler)
	var port: Node = PORT_SCRIPT.new()
	port.name = "GameplayPort"
	port.set("PlayerPath", NodePath("../Player"))
	port.set("GlobalWarehousePath", NodePath("../GlobalWarehouse"))
	root.add_child(port)
	# 夹具根节点未加入 SceneTree，Godot 不会自动触发 _ready；显式初始化以模拟生产挂入流程。
	port.call("_ready")
	return {
		"root": root,
		"player": player,
		"battle_deck": battle_deck,
		"legacy_skill_card": legacy_skill_card,
		"gdscript_skill_card": gdscript_skill_card,
		"encounter_scaler": encounter_scaler,
		"port": port,
	}


## 验证 GameplayPort 的节点绑定、动态 UI 请求、仓库请求和库存委托协议。
## 返回值：无。
func test_gameplay_port_request_contract() -> void:
	var fixture := _build_fixture()
	var root: Node = fixture["root"]
	var player: FakePlayer = fixture["player"]
	var port: Node = fixture["port"]
	var inventory_events: Array = []
	var crafting_toggle_events: Array = []
	var crafting_open_events: Array = []
	var farming_events: Array = []
	var warehouse_events: Array = []
	port.connect("InventoryNodeToggleRequested", func(inventory: Node) -> void:
		inventory_events.append(inventory)
	)
	port.connect("CraftingNodeToggleRequested", func(crafting: Node) -> void:
		crafting_toggle_events.append(crafting)
	)
	port.connect("CraftingNodeOpenRequested", func(crafting: Node) -> void:
		crafting_open_events.append(crafting)
	)
	port.connect("FarmingPanelRequested", func(terrain: Variant) -> void:
		farming_events.append(terrain)
	)
	port.connect("WarehouseNodeRequested", func(player_inventory: Node, warehouse_inventory: Node) -> void:
		warehouse_events.append([player_inventory, warehouse_inventory])
	)
	assert_true(port.get("Player") == player, "GameplayPort 必须解析 PlayerPath。")
	assert_true(port.get("PlayerInventory") == player.get_node("Components/InventoryComponent"), "GameplayPort 必须绑定玩家库存。")
	assert_true(port.get("PlayerInventoryNode") == port.get("PlayerInventory"), "玩家库存 Node 别名必须保持同一节点身份。")
	assert_true(port.get("PlayerCraftingNode") == port.get("PlayerCrafting"), "玩家合成 Node 别名必须保持同一节点身份。")
	assert_true(port.get("GlobalWarehouseNode") == root.get_node("GlobalWarehouse"), "GameplayPort 必须绑定全局仓库 Node 边界。")
	port.call("RequestToggleInventory")
	port.call("RequestToggleCrafting")
	port.call("RequestOpenCrafting")
	var terrain_probe := Resource.new()
	port.call("RequestOpenFarmingPanel", terrain_probe)
	port.call("RequestOpenWarehouse")
	assert_eq(inventory_events.size(), 1, "GDScript 背包请求必须只发出一次 Node 信号。")
	assert_eq(crafting_toggle_events.size(), 1, "GDScript 合成切换必须只发出一次 Node 信号。")
	assert_eq(crafting_open_events.size(), 1, "GDScript 合成打开必须只发出一次 Node 信号。")
	assert_true(farming_events.size() == 1 and farming_events[0] == terrain_probe, "农场请求必须保持地形引用。")
	assert_eq(warehouse_events.size(), 1, "GDScript 仓库请求必须只发出一次 Node 信号。")
	if warehouse_events.size() == 1:
		assert_true(warehouse_events[0][0] == port.get("PlayerInventory"), "仓库请求必须保持玩家库存节点身份。")
		assert_true(warehouse_events[0][1] == port.get("GlobalWarehouseNode"), "仓库请求必须保持全局仓库节点身份。")
	var stack := RefCounted.new()
	assert_true(bool(port.call("TryAddItemToInventory", stack)), "库存添加必须委托给 Player。")
	assert_eq(player.add_count, 1, "玩家库存添加委托次数必须为 1。")
	assert_true(player.last_stack == stack, "玩家必须收到原始堆叠引用。")
	root.free()


## 验证怪物倍率调用、技能卡/怪物过滤以及遭遇数组顺序和身份。
## 返回值：无。
func test_gameplay_port_encounter_conversion_and_scaling_contract() -> void:
	var fixture := _build_fixture()
	var root: Node = fixture["root"]
	var port: Node = fixture["port"]
	var encounter_scaler: FakeWorldInteractionCoordinator = fixture["encounter_scaler"]
	var legacy_skill_card: Resource = fixture["legacy_skill_card"]
	var gdscript_skill_card: Resource = fixture["gdscript_skill_card"]
	var encounter_events: Array = []
	port.connect("EncounterRequested", func(terrain: Variant, battle_deck: Array, monsters: Array, message: String) -> void:
		encounter_events.append([terrain, battle_deck, monsters, message])
	)
	var terrain_probe := Resource.new()
	port.call("RequestEncounter", terrain_probe, [MONSTER_A, RefCounted.new(), MONSTER_B], "遭遇")
	assert_eq(encounter_scaler.scale_call_count, 1, "每次遭遇必须调用同级倍率桥。")
	assert_true(encounter_scaler.last_terrain == terrain_probe, "倍率桥必须收到原地形引用。")
	assert_eq(encounter_scaler.last_monsters.size(), 2, "倍率桥必须过滤非 MonsterData 元素。")
	if encounter_scaler.last_monsters.size() == 2:
		assert_true(encounter_scaler.last_monsters[0] == MONSTER_A, "倍率输入必须保持第一只怪物的 Resource 身份。")
		assert_true(encounter_scaler.last_monsters[1] == MONSTER_B, "倍率输入必须保持第二只怪物的 Resource 身份。")
	assert_eq(encounter_events.size(), 1, "遭遇请求必须发出一次。")
	if encounter_events.size() == 1:
		assert_eq(encounter_events[0][1].size(), 4, "战斗卡组必须过滤无效动态元素并接收生产 GDScript 与旧 C# 技能卡。")
		assert_true(encounter_events[0][1][0] == SKILL_CARD_A, "卡组第一张卡牌的顺序和身份必须保持。")
		assert_true(encounter_events[0][1][1] == legacy_skill_card, "旧 C# 技能卡兼容输入的顺序和身份必须保持。")
		assert_true(encounter_events[0][1][2] == gdscript_skill_card, "临时 GDScript 技能卡的顺序和身份必须保持。")
		assert_true(encounter_events[0][1][3] == SKILL_CARD_B, "卡组最后一张生产技能卡的顺序和身份必须保持。")
		assert_eq(encounter_events[0][2].size(), 2, "遭遇信号必须携带倍率入口的有效怪物结果。")
		assert_true(encounter_events[0][2][0] == MONSTER_B, "遭遇信号必须保持倍率输出的第一只怪物身份。")
		assert_true(encounter_events[0][2][1] == MONSTER_A, "遭遇信号必须保持倍率输出的第二只怪物身份。")
		assert_eq(encounter_events[0][3], "遭遇", "遭遇提示文本必须保持原值。")
	port.call("RequestEncounter", terrain_probe, MONSTER_A, "单怪物")
	assert_eq(encounter_scaler.scale_call_count, 2, "单怪物入口也必须经过倍率桥处理。")
	assert_eq(encounter_scaler.last_monsters.size(), 1, "单个 MonsterData 必须转换为单元素数组。")
	root.free()


## 验证全部生产技能卡、战斗内嵌技能卡和卡表生成器使用 GDScript Resource。
## 返回值：无。
func test_skill_card_production_asset_switch_contract() -> void:
	var card_paths: Array[String] = _collect_tres_paths(PRODUCTION_SKILL_CARD_DIRECTORY)
	assert_eq(card_paths.size(), PRODUCTION_SKILL_CARD_COUNT, "生产技能卡数量必须保持为 69。")
	for path: String in card_paths:
		var source: String = FileAccess.get_file_as_string(path)
		assert_true(source.contains('uid="uid://d1ln6w8iaa4px" path="%s"' % PRODUCTION_SKILL_CARD_SCRIPT_PATH), "%s 必须引用 GDScript SkillCardData UID。" % path)
		assert_false(source.contains(LEGACY_SKILL_CARD_SCRIPT_PATH), "%s 不得保留旧 SkillCardData.cs 路径。" % path)
		assert_false(source.contains('script_class="SkillCardData"'), "%s 不得保留旧 C# 全局类型标头。" % path)
		assert_false(source.contains('metadata/_custom_type_script = "uid://bejho62d28qir"'), "%s 不得保留旧 C# 自定义脚本元数据。" % path)
		for field_marker: String in ["Skill = ExtResource(", "cost =", "CardTags =", "CardId =", "CardName =", "CardIcon =", "Description ="]:
			assert_true(source.contains(field_marker), "%s 必须保留序列化字段 %s。" % [path, field_marker])

		var card := ResourceLoader.load(path, "Resource", ResourceLoader.CACHE_MODE_REPLACE) as Resource
		assert_true(card != null, "%s 必须能够加载。" % path)
		if card == null:
			continue
		assert_eq(card.get_script().resource_path, PRODUCTION_SKILL_CARD_SCRIPT_PATH, "%s 必须使用生产 GDScript SkillCardData。" % path)
		assert_true(card.get("Skill") is Resource, "%s 必须保留 CombatSkillData 引用。" % path)
		assert_true(card.get("CardTags") is Array, "%s 必须保留 CardTags 数组。" % path)
		# 工具态加载非 @tool Resource 时只保证导出字段；计算属性由直接脚本测试和游戏态场景覆盖。
		assert_false(String(card.get("CardName")).strip_edges().is_empty(), "%s 必须保留卡牌名称。" % path)
		assert_true(card.get("CardIcon") is Texture2D, "%s 必须保留技能卡图标。" % path)

	var battle_source: String = FileAccess.get_file_as_string("res://scenes/battle_scenes/battle.tscn")
	assert_true(battle_source.contains('uid="uid://d1ln6w8iaa4px" path="%s"' % PRODUCTION_SKILL_CARD_SCRIPT_PATH), "战斗场景内嵌技能卡必须切换到 GDScript。")
	assert_true(battle_source.contains("starting_deck_data = Array[Resource]"), "战斗起始卡组必须使用通用 Resource 数组。")
	assert_false(battle_source.contains(LEGACY_SKILL_CARD_SCRIPT_PATH), "战斗场景不得保留旧 SkillCardData.cs 路径。")
	assert_false(battle_source.contains('metadata/_custom_type_script = "uid://bejho62d28qir"'), "战斗内嵌技能卡不得保留旧 C# 类型元数据。")
	var battle_scene := ResourceLoader.load("res://scenes/battle_scenes/battle.tscn", "PackedScene", ResourceLoader.CACHE_MODE_REPLACE) as PackedScene
	assert_true(battle_scene != null, "战斗场景必须能够加载。")
	if battle_scene != null:
		var battle := battle_scene.instantiate()
		var starting_deck: Array = battle.get("starting_deck_data")
		assert_eq(starting_deck.size(), 19, "战斗场景的 19 张起始卡顺序和数量不得改变。")
		for card: Resource in starting_deck:
			assert_eq(card.get_script().resource_path, PRODUCTION_SKILL_CARD_SCRIPT_PATH, "战斗起始卡组不得混入旧 C# SkillCardData。")
		battle.free()

	var generator_source: String = FileAccess.get_file_as_string("res://card_table/export_current_cards.py")
	assert_true(generator_source.contains('SKILL_CARD_SCRIPT = "%s"' % PRODUCTION_SKILL_CARD_SCRIPT_PATH), "卡表生成器必须写入 GDScript SkillCardData 路径。")
	assert_true(generator_source.contains('SKILL_CARD_SCRIPT_UID = "uid://d1ln6w8iaa4px"'), "卡表生成器必须写入 GDScript SkillCardData UID。")
	assert_false(generator_source.contains(LEGACY_SKILL_CARD_SCRIPT_PATH), "卡表生成器不得重新写回旧 SkillCardData.cs。")
	for directory_path: String in ["res://resources/monster", "res://resources/combat_skills"]:
		for path: String in _collect_tres_paths(directory_path):
			assert_false(FileAccess.get_file_as_string(path).contains(LEGACY_SKILL_CARD_SCRIPT_PATH), "%s 不得保留未使用的旧 SkillCardData 脚本声明。" % path)


## 收集指定目录直属的 .tres 资源，并按路径排序以保证测试结果稳定。
## 参数 directory_path：需要扫描的 res:// 目录。
## 返回值：排序后的 .tres 路径数组。
func _collect_tres_paths(directory_path: String) -> Array[String]:
	var paths: Array[String] = []
	for file_name: String in DirAccess.get_files_at(directory_path):
		if file_name.ends_with(".tres"):
			paths.append(directory_path.path_join(file_name))
	paths.sort()
	return paths


## 验证生产 Main 已切换 GameplayPort GDScript，且两个 C# 消费者只依赖 Node 协议。
## 返回值：无。
func test_gameplay_port_production_switch_contract() -> void:
	var main_scene := ResourceLoader.load("res://scenes/Main.tscn", "PackedScene", ResourceLoader.CACHE_MODE_REPLACE) as PackedScene
	assert_true(main_scene != null, "Main 生产场景必须能够加载。")
	if main_scene != null:
		var main := main_scene.instantiate()
		var port := main.get_node_or_null("Gameplay/GameplayPort")
		assert_true(port != null, "Main 必须保留 Gameplay/GameplayPort 节点。")
		if port != null:
			var port_script := port.get_script() as Script
			assert_true(port_script != null, "生产 GameplayPort 必须绑定脚本。")
			if port_script != null:
				assert_eq(port_script.resource_path, "res://core/application/gameplay_port.gd", "生产 GameplayPort 必须使用 GDScript。")
			assert_true(port.has_signal("EncounterRequested"), "生产 GameplayPort 必须保留 EncounterRequested 信号。")
			assert_true(port.has_method("GetPlayerSkillCards"), "生产 GameplayPort 必须提供稳定卡组方法。")
		main.free()
	var coordinator_source := FileAccess.get_file_as_string("res://core/gameflow/WorldInteractionCoordinator.cs")
	var presenter_source := FileAccess.get_file_as_string("res://core/gameflow/WorldCombatScenePresenter.cs")
	var executor_source := FileAccess.get_file_as_string("res://core/gameflow/TerrainInteractionExecutor.cs")
	var battle_source := FileAccess.get_file_as_string("res://scripts/battle_scripts/battle_manager.gd")
	var deck_source := FileAccess.get_file_as_string("res://scripts/card_scripts/deck_manager.gd")
	var card_source := FileAccess.get_file_as_string("res://scripts/card_scripts/skill_card.gd")
	assert_true(coordinator_source.contains("private Node _gameplayPort"), "局外协调器必须以 Node 持有 GameplayPort。")
	assert_true(coordinator_source.contains("Array<Resource> cards = battleDeck.VariantType"), "遭遇信号卡组必须进入通用 Resource 数组。")
	assert_true(coordinator_source.contains("is Resource card") and coordinator_source.contains('card.HasMethod("ApplyEffect")'), "局外协调器必须按稳定方法过滤跨语言技能卡。")
	assert_true(presenter_source.contains("Array<Resource> battleDeck"), "战斗场景 Presenter 必须接收通用技能卡 Resource 数组。")
	assert_true(battle_source.contains("starting_deck_data: Array[Resource]"), "BattleManager 必须接收通用技能卡 Resource 数组。")
	assert_true(deck_source.contains("draw_pile_data: Array[Resource]"), "DeckManager 抽牌堆必须保存通用技能卡 Resource。")
	assert_true(card_source.contains("var data: Resource"), "SkillCard 展示节点必须保存通用技能卡 Resource。")
	assert_true(coordinator_source.contains("ConvertMonsters(monsters.AsGodotArray())"), "遭遇信号怪物必须显式过滤为 Array<MonsterData>。")
	assert_true(coordinator_source.contains('_encounterManager.Call("ScaleEncounterMonsters", terrain, filteredMonsters)'), "倍率桥必须把过滤结果交给兼容 EncounterManager 协议。")
	assert_true(executor_source.contains("Node gameplayPort"), "地形执行器必须通过 Node 接受 GameplayPort。")
	assert_true(executor_source.contains("gameplayPort.Call(\"RequestEncounter\""), "地形执行器必须调用稳定 PascalCase 遭遇方法。")
	assert_false(coordinator_source.contains("GetNode<GameplayPort>"), "局外协调器不得继续强制解析 C# GameplayPort。")
