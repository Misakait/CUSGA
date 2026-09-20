@tool
extends McpTestSuite

## WorldInteractionCoordinator 生产迁移契约套件。
##
## 套件锁定六件事：局外世界交互协调器改为 GDScript 生产实现且导出面/信号面逐字等价旧 C#、
## Main.tscn 完成最后一个 C# 场景脚本切换、地形交互与战斗过场等内联实现按稳定协议工作、
## 四个只被协调器使用的 C# 辅助类继续作为完整垫片保留、两端共享同一套日志与报错文本、
## 资产层不再引用旧脚本。“点击地形能否真的走完交互序列”由运行中的游戏经 game_eval 验证。
## C# 物理退役后，依赖垫片的对照断言经 CS_OPTIONAL 自动退场（见 tests/godot/csharp_optional.gd）。

## 本批生产脚本与旁车 UID。
const COORDINATOR_GD: String = "res://core/gameflow/world_interaction_coordinator.gd"
const COORDINATOR_GD_UID: String = "res://core/gameflow/world_interaction_coordinator.gd.uid"
## 旧 C# 协调器垫片；全量迁移完成前必须保留完整实现。
const COORDINATOR_CS: String = "res://core/gameflow/WorldInteractionCoordinator.cs"

## 迁移期 C# 可选助手：C# 退役后 C# 对照断言自动退场，GDScript 侧断言照跑。
## 说明见 tests/godot/csharp_optional.gd。
const CS_OPTIONAL := preload("res://tests/godot/csharp_optional.gd")

## 本批被内联复刻的四个 C# 辅助类垫片。
const LEGACY_PADS: Array[String] = [
	COORDINATOR_CS,
	"res://core/gameflow/WorldCombatScenePresenter.cs",
	"res://core/gameflow/TerrainInteractionExecutor.cs",
	"res://core/gameflow/WorldViewVisibilityController.cs",
	"res://core/gameflow/ScreenTransitionAdapter.cs",
	"res://resources/interaction/operations/PassTimeOp.cs",
	"res://resources/interaction/operations/CheckGatheringEncounterOp.cs",
]

## 地形操作族（C# 兼容层）与 GDScript 生产执行词汇。
const TERRAIN_EXECUTOR_CS: String = "res://core/gameflow/TerrainInteractionExecutor.cs"
const OP_FAMILY_CS: Array[String] = [
	"res://resources/interaction/operations/TerrainOp.cs",
	"res://resources/interaction/operations/CheckGatheringEncounterOp.cs",
	"res://resources/interaction/operations/EnterVaultOp.cs",
	"res://resources/interaction/operations/MarkHarvestedOp.cs",
	"res://resources/interaction/operations/MonsterSpawnOp.cs",
	"res://resources/interaction/operations/OpenFarmingPanelOp.cs",
	"res://resources/interaction/operations/PassTimeOp.cs",
	"res://resources/interaction/operations/RecordReusableGatheringOp.cs",
	"res://resources/interaction/operations/RemoveSourceCardOp.cs",
	"res://resources/interaction/operations/SpawnLootOp.cs",
]

## 生产地形交互资源（全部是 GDScript 且实现 build_ops）。
const GD_INTERACTIONS: Array[String] = [
	"res://resources/interaction/boss_interaction.gd",
	"res://resources/interaction/farming_interaction.gd",
	"res://resources/interaction/gathering_interaction.gd",
	"res://resources/interaction/reusable_gathering_interaction.gd",
	"res://resources/interaction/vault_interaction.gd",
]

## 操作词汇逐条对照：[描述 type, GDScript 生产副作用片段, 旧 C# 提供方, 旧 C# 同类副作用片段]。
const OP_VOCABULARY: Array = [
	[
		"pass_time",
		"print(\"[PassTimeOp] Pass time %d\" % amount)",
		"res://resources/interaction/operations/PassTimeOp.cs",
		"GD.Print($\"[PassTimeOp] Pass time {Amount}\")",
	],
	[
		"spawn_loot",
		"\"SpawnLootCards\", drops, card.global_position",
		"res://resources/interaction/operations/SpawnLootOp.cs",
		"context.Board.SpawnLootCards(Drops, context.SourceGlobalPosition)",
	],
	[
		"mark_harvested",
		"terrain.set(\"IsHarvested\", true)",
		"res://resources/interaction/operations/MarkHarvestedOp.cs",
		"TerrainInstanceProtocol.SetBool(context.Terrain, \"IsHarvested\", true)",
	],
	[
		"check_gathering_encounter",
		"Checking gathering encounter for tag: %s",
		"res://resources/interaction/operations/CheckGatheringEncounterOp.cs",
		"Checking gathering encounter for tag: {GatheringTag}",
	],
	[
		"record_reusable_gathering",
		"record_successful_harvest",
		"res://resources/interaction/operations/RecordReusableGatheringOp.cs",
		"RecordSuccessfulHarvest(",
	],
	[
		"enter_vault",
		"_gameplay_port.call(\"RequestOpenWarehouse\")",
		"res://resources/interaction/operations/EnterVaultOp.cs",
		"context.Gameplay.RequestOpenWarehouse()",
	],
	[
		"open_farming_panel",
		"_gameplay_port.call(\"RequestOpenFarmingPanel\", terrain)",
		"res://resources/interaction/operations/OpenFarmingPanelOp.cs",
		"context.Gameplay.RequestOpenFarmingPanel(context.Terrain)",
	],
	[
		"spawn_monster",
		"_gameplay_port.call(\"RequestEncounter\", terrain, monster, \"Boss Battle!\")",
		"res://resources/interaction/operations/MonsterSpawnOp.cs",
		"context.Gameplay.RequestEncounter(context.Terrain, Monster, \"Boss Battle!\")",
	],
	[
		"remove_source_card",
		"\"RemoveCard\", card",
		TERRAIN_EXECUTOR_CS,
		"boardController.Call(\"RemoveCard\", sourceCard)",
	],
]

## 主场景与必须保持原值的资产 id。
const MAIN_SCENE: String = "res://scenes/Main.tscn"
const MAIN_SCENE_SCRIPT_ID: String = "7_nxtc6"

## 必须逐字保留在 GDScript 生产脚本里的 9 个导出。
const GD_EXPORTS: Array[String] = [
	"@export var BoardControllerPath: NodePath = NodePath(\"\")",
	"@export var GameplayPortPath: NodePath = NodePath(\"\")",
	"@export var BackpackFlyTargetPath: NodePath = NodePath(\"\")",
	"@export var EncounterManagerPath: NodePath = NodePath(\"\")",
	"@export var HoldInteractionControllerPath: NodePath = NodePath(\"WorldHoldInteractionController\")",
	"@export var WorldRootPath: NodePath = NodePath(\"../..\")",
	"@export var MapSystemPath: NodePath = NodePath(\"../../MapSystem\")",
	"@export var MapCanvasLayerPath: NodePath = NodePath(\"../../MapSystem/CanvasLayer\")",
	"@export var HudLayerPath: NodePath = NodePath(\"../../UI/HUDLayer\")",
]

## 必须逐字保留的 2 个信号声明。
const GD_SIGNALS: Array[String] = [
	"signal PassageGuardEncounterFinished(is_victory: bool)",
	"signal WorldHoldCompleted(owner: Node)",
]

## 必须保留的稳定信号名与路径常量。
const GD_STABLE_NAMES: Array[String] = [
	"const ENCOUNTER_REQUESTED_SIGNAL: StringName = &\"EncounterRequested\"",
	"const TIME_CHANGED_SIGNAL: StringName = &\"TimeChanged\"",
	"const BOARD_CARD_CLICKED_SIGNAL: StringName = &\"CardClicked\"",
	"const BOARD_CARD_PRESSED_SIGNAL: StringName = &\"CardPressed\"",
	"const BOARD_CARD_RELEASED_SIGNAL: StringName = &\"CardReleased\"",
	"const BOARD_CARD_SPAWNED_SIGNAL: StringName = &\"CardSpawned\"",
	"const BATTLE_ENDED_SIGNAL: StringName = &\"battle_ended\"",
	"const TIME_SYSTEM_PATH: NodePath = ^\"/root/TimeSystem\"",
	"var ScreenTransitionsPath: NodePath = ^\"/root/ScreenTransitions\"",
]

## 生产脚本必须提供的函数面。
const GD_FUNCTIONS: Array[String] = [
	"func _ready() -> void:",
	"func _exit_tree() -> void:",
	"func _unhandled_input(event: InputEvent) -> void:",
	"func _on_encounter_requested(",
	"func RequestPassageGuardEncounter(monsters: Array) -> void:",
	"func ScaleEncounterMonsters(terrain: Variant, monsters: Array) -> Array:",
	"func BeginWorldHoldForMap(owner: Node, action_point_cost: int, progress_target: Node) -> void:",
	"func CancelWorldHoldFor(owner: Node) -> void:",
	"func _on_board_card_clicked(card: Node2D) -> void:",
	"func _on_board_card_pressed(card: Node2D) -> void:",
	"func _on_board_card_released(card: Node2D) -> void:",
	"func _on_board_card_spawned(card: Node2D) -> void:",
	"func _on_time_changed(",
	"func _complete_terrain_hold(",
	"func _execute_terrain_interaction(",
	"func _apply_gdscript_ops(",
	"func _enter_combat(battle_deck: Array[Resource], monsters: Array[Resource]) -> bool:",
	"func _on_battle_ended(is_victory: bool, battle_instance: Node) -> void:",
	"func _run_screen_transition(method_name: String, completed_signal: StringName) -> void:",
]

## 旧 C# 垫片必须继续提供的公开与私有成员。
const CS_MEMBERS: Array[String] = [
	"public partial class WorldInteractionCoordinator : Node",
	"[Signal] public delegate void PassageGuardEncounterFinishedEventHandler(bool isVictory);",
	"[Signal] public delegate void WorldHoldCompletedEventHandler(Node owner);",
	"public async void RequestPassageGuardEncounter(Array<Resource> monsters)",
	"public Array<Resource> ScaleEncounterMonsters(",
	"public void BeginWorldHoldForMap(Node owner, int actionPointCost, Node progressTarget)",
	"public void CancelWorldHoldFor(Node owner)",
	"private void DisconnectBoardSignal(StringName signal, Callable callback)",
	"private Node GetGameplayPlayer()",
	"private Node GetGameplayEquipment()",
]

## 必须两侧逐字一致的日志与报错文本。
const SHARED_TEXTS: Array[String] = [
	"RequestPassageGuardEncounter: monsters = ",
	"GameplayPort 缺少 EncounterRequested 信号，无法转发局外遭遇。",
	"WorldInteractionCoordinator 未找到 TimeSystem Autoload。",
	"TimeSystem 缺少 TimeChanged 信号，无法刷新可重复采集状态。",
	"WorldInteractionCoordinator 未找到 WorldHoldInteractionController，无法开始局外长按。",
	"[TerrainInteractionExecutor] Click terrain: ",
	"[TerrainInteractionExecutor] Build GDScript ops from ",
	"GDScript 地形交互的 build_ops 必须返回 Array[Dictionary]。",
	"GDScript 地形交互返回了非 Dictionary 操作，已跳过。",
	"未知 GDScript 地形操作类型：",
	"未实现 BuildOps 或 build_ops，无法执行。",
	"[PassTimeOp] Pass time ",
	"Checking gathering encounter for tag: ",
	"[WorldCombatScenePresenter] Entering Combat!",
	"[WorldCombatScenePresenter] Combat Ended! Victory: ",
	"无法加载战斗背景解析器：",
	"战斗背景解析器缺少 DuplicateCurrentBackground 协议。",
]


## 旧 C# 私有助手名到 GDScript 等价助手名的映射。
const PRIVATE_HELPER_PAIRS: Dictionary = {
	"GetGameplayPlayer": "_get_gameplay_player",
	"GetGameplayEquipment": "_get_gameplay_equipment",
	"GetPlayerSkillCards": "_get_player_skill_cards",
	"GetCurrentTotalTime": "_get_current_total_time",
	"GetTerrainInteraction": "_get_terrain_interaction",
	"GetInteractionActionPointCost": "_get_interaction_action_point_cost",
	"GetReusableEffectiveTimeCost": "_get_reusable_effective_time_cost",
	"RefreshReusableGatheringCard": "_refresh_reusable_gathering_card",
	"TryGetHoldableTerrain": "_try_get_holdable_terrain",
	"CompleteTerrainHold": "_complete_terrain_hold",
}


## 返回 GodotAI 使用的稳定套件名称。
##
## @return 局外世界交互协调器契约套件名。
func suite_name() -> String:
	return "world_interaction_coordinator_contract"


## 验证生产脚本形状、UID 旁车与 GDScript 书写约定。
##
## @return 无返回值。
func test_production_script_shape() -> void:
	## C# 物理退役后旧协调器垫片已删除，契约文件只要求生产脚本与旁车 UID。
	for path: String in [COORDINATOR_GD, COORDINATOR_GD_UID]:
		assert_true(FileAccess.file_exists(path), "契约文件必须存在：%s" % path)

	var coordinator: String = FileAccess.get_file_as_string(COORDINATOR_GD)
	assert_true(coordinator.begins_with("extends Node"), "世界交互协调器必须直接继承 Node。")
	assert_false(_declares_class_name(coordinator), "世界交互协调器不得声明 class_name，避免与兼容垫片重名。")
	assert_false(coordinator.contains("TODO"), "生产脚本不得保留 TODO 占位。")
	# 回归：Godot 4 的整型向量类型是 Vector2i，写成 Vector2I 会在游戏启动时报解析错误。
	assert_false(coordinator.contains("Vector2I"), "Godot 类型名必须写成 Vector2i，不得写成 Vector2I。")
	# 回归：节点路径常量必须是 NodePath，只有信号名才用 StringName。
	assert_false(coordinator.contains("_PATH: StringName = "), "节点路径常量不得声明为 StringName。")

	for literal: String in GD_EXPORTS:
		assert_true(coordinator.contains(literal), "必须保留导出声明：%s" % literal)
	for literal: String in GD_SIGNALS:
		assert_true(coordinator.contains(literal), "必须保留信号声明：%s" % literal)
	for literal: String in GD_STABLE_NAMES:
		assert_true(coordinator.contains(literal), "必须保留稳定协议名称：%s" % literal)
	for literal: String in GD_FUNCTIONS:
		assert_true(coordinator.contains(literal), "生产脚本缺少入口：%s" % literal)

	var uid_text: String = FileAccess.get_file_as_string(COORDINATOR_GD_UID).strip_edges()
	assert_true(uid_text.begins_with("uid://"), "旁车 UID 必须是 uid:// 形式。")
	assert_true(
		FileAccess.get_file_as_string(MAIN_SCENE).contains(uid_text),
		"主场景必须引用生产脚本的同一 UID。"
	)


## 验证主场景完成最后一个 C# 场景脚本切换，且序列化导出值不变。
##
## @return 无返回值。
func test_main_scene_switched_to_gdscript() -> void:
	var scene: String = FileAccess.get_file_as_string(MAIN_SCENE)
	assert_true(
		scene.contains("path=\"%s\" id=\"%s\"" % [COORDINATOR_GD, MAIN_SCENE_SCRIPT_ID]),
		"主场景必须复用原 ext_resource id 指向 GDScript 生产脚本。"
	)
	assert_false(scene.contains("WorldInteractionCoordinator.cs"), "主场景不得继续引用旧 C# 世界交互协调器。")
	for literal: String in [
		'[node name="WorldInteractionCoordinator" type="Node" parent="Gameplay"',
		'BoardControllerPath = NodePath("../../BoardSystem/BoardController")',
		'GameplayPortPath = NodePath("../GameplayPort")',
		'BackpackFlyTargetPath = NodePath("../../UI/HUDLayer/HUDRoot/BackpackButton/BackpackFlyTarget")',
		'EncounterManagerPath = NodePath("../EncounterManager")',
		'[node name="WorldHoldInteractionController" type="Node" parent="Gameplay/WorldInteractionCoordinator"',
		'script = ExtResource("19_world_hold")',
	]:
		assert_true(scene.contains(literal), "主场景必须保留原有节点与序列化值：%s" % literal)


## 验证公开协议方法名在两侧完全一致，私有助手按 snake_case 一一对应。
##
## @return 无返回值。
func test_protocol_faces_match_legacy_shim() -> void:
	var coordinator: String = FileAccess.get_file_as_string(COORDINATOR_GD)
	var legacy: String = CS_OPTIONAL.read(COORDINATOR_CS)

	for public_name: String in [
		"RequestPassageGuardEncounter",
		"ScaleEncounterMonsters",
		"BeginWorldHoldForMap",
		"CancelWorldHoldFor",
	]:
		assert_true(coordinator.contains(public_name), "生产脚本必须保留公开协议名：%s" % public_name)
		if not legacy.is_empty():
			assert_true(legacy.contains(public_name), "旧 C# 垫片必须保留公开协议名：%s" % public_name)

	if legacy.is_empty():
		return
	for legacy_name: String in PRIVATE_HELPER_PAIRS.keys():
		var gd_name: String = str(PRIVATE_HELPER_PAIRS[legacy_name])
		assert_true(legacy.contains(legacy_name), "旧 C# 垫片必须保留私有助手：%s" % legacy_name)
		assert_true(coordinator.contains(gd_name), "生产脚本必须有等价助手：%s" % gd_name)


## 验证跨语言边界全部走稳定信号名、方法名与字段名，且内联实现保留双语言分支。
##
## @return 无返回值。
func test_cross_language_boundaries() -> void:
	var coordinator: String = FileAccess.get_file_as_string(COORDINATOR_GD)

	# 棋盘控制器与 GameplayPort 只按 Node 协议持有，不出现任何具体 C# 类型。
	for literal: String in [
		"var _board_controller: Node = null",
		"var _gameplay_port: Node = null",
		"var _encounter_manager: Node = null",
		"var _time_system: Node = null",
		"var _hold_interaction_controller: Node = null",
		"_board_controller.call(\"SpawnLootCards\", drops, card.global_position)",
		"_board_controller.call(\"GetActiveCardsSnapshot\")",
		"_board_controller.call(\"RemoveCard\", card)",
		"card.call(\"SetInteractionDisabled\", not _can_harvest(interaction, terrain, total_time_passed))",
		"card.call(\"PlayFlyTo\", target, Callable(self, \"_on_loot_fly_finished\").bind(card))",
		"_gameplay_port.call(\"RequestOpenWarehouse\")",
		"_gameplay_port.call(\"RequestOpenFarmingPanel\", terrain)",
		"_encounter_manager.call(\"ResolveGatheringEncounter\", resource_tag, encounter_chance_multiplier)",
		"_encounter_manager.call(\"ScaleEncounterMonsters\", terrain, filtered_monsters)",
		"_time_system.call(\"PassTime\", amount)",
		"_time_system.get(\"TotalTimePassed\")",
		"_gameplay_port.get(\"Player\")",
		"player.get(\"Equipment\")",
		"terrain.get(\"TerrainData\")",
		"terrain_data.get(\"InteractionBehavior\")",
		"interaction.get(\"TimeCost\")",
		"_hold_interaction_controller.call(",
		"\"begin_hold\",",
		"_hold_interaction_controller.call(\"cancel_hold_for\", owner)",
		"_hold_interaction_controller.call(\"cancel_active_hold\")",
	]:
		assert_true(coordinator.contains(literal), "生产脚本必须保留跨语言协议片段：%s" % literal)

	# 可重复采集交互只按方法协议兼容两种实现：不再出现语言身份判定，
	# 因而 C# 垫片退役后本脚本不必再改，也不会解析失败。
	for literal: String in [
		"const REUSABLE_GATHERING_CS_METHODS: Array[StringName] = [",
		"&\"GetEffectiveTimeCost\"",
		"&\"CanHarvest\"",
		"const REUSABLE_GATHERING_GD_METHODS: Array[StringName] = [",
		"&\"get_effective_time_cost\"",
		"&\"can_harvest\"",
		"const REUSABLE_GATHERING_TIME_COST_INDEX: int = 0",
		"const REUSABLE_GATHERING_CAN_HARVEST_INDEX: int = 1",
		"_resolve_reusable_gathering_method(interaction, REUSABLE_GATHERING_TIME_COST_INDEX)",
		"_resolve_reusable_gathering_method(interaction, REUSABLE_GATHERING_CAN_HARVEST_INDEX)",
	]:
		assert_true(coordinator.contains(literal), "可重复采集分支必须按方法协议兼容两种实现：%s" % literal)
	assert_true(
		not coordinator.contains("is ReusableGatheringInteraction"),
		"可重复采集分支不得再按 C# 类型名判定语言身份（删 C# 后会解析失败）。"
	)

	# 怪物过滤统一走跨语言协议，避免只认旧 C# 类型而丢弃 GDScript 怪物。
	assert_true(
		coordinator.contains("MONSTER_DATA_REQUIRED_FIELDS"),
		"怪物过滤必须声明跨语言字段协议。"
	)
	assert_true(
		coordinator.contains("if not present.has(field):"),
		"怪物过滤必须按字段协议同时接受两侧怪物数据。"
	)
	assert_false(coordinator.contains("is MonsterData"), "怪物过滤不得再绑定旧 C# 类型名。")
	assert_false(coordinator.contains("Array<MonsterData>"), "生产脚本不得使用旧 C# 强类型怪物数组。")

	# 过场按稳定方法名与完成信号名驱动，且先连接再发起，避免极短动画丢信号。
	assert_true(
		coordinator.contains("_run_screen_transition(\"fade_out\", &\"fade_complete\")"),
		"淡出必须等待 fade_complete 信号。"
	)
	assert_true(
		coordinator.contains("_run_screen_transition(\"fade_in\", &\"fade_in_complete\")"),
		"淡入必须等待 fade_in_complete 信号。"
	)
	assert_true(
		coordinator.contains("_screen_transitions.connect(completed_signal, on_completed, CONNECT_ONE_SHOT)"),
		"过场完成信号必须先建立一次性连接再发起动画。"
	)


## 验证旧 C# 垫片仍是完整实现，没有被掏空成空壳。
##
## @return 无返回值。
func test_legacy_shims_stay_complete() -> void:
	if not CS_OPTIONAL.present_all(LEGACY_PADS + [COORDINATOR_CS]):
		skip(CS_OPTIONAL.SKIP_REASON)
		return
	var legacy: String = FileAccess.get_file_as_string(COORDINATOR_CS)
	for literal: String in CS_MEMBERS:
		assert_true(legacy.contains(literal), "旧 C# 垫片不得删除实现：%s" % literal)

	for path: String in LEGACY_PADS:
		assert_true(FileAccess.file_exists(path), "被内联复刻的 C# 垫片必须保留：%s" % path)

	assert_true(
		FileAccess.get_file_as_string(LEGACY_PADS[1]).contains("public sealed class WorldCombatScenePresenter("),
		"战斗场景过场垫片必须保留完整实现。"
	)
	assert_true(
		FileAccess.get_file_as_string(LEGACY_PADS[2]).contains("public sealed class TerrainInteractionExecutor("),
		"地形交互执行器垫片必须保留完整实现。"
	)
	assert_true(
		FileAccess.get_file_as_string(LEGACY_PADS[3]).contains("public sealed class WorldViewVisibilityController("),
		"世界视图可见性垫片必须保留完整实现。"
	)
	assert_true(
		FileAccess.get_file_as_string(LEGACY_PADS[4]).contains("public sealed class ScreenTransitionAdapter(Node awaiter, Node screenTransitions)"),
		"过场适配器垫片必须保留完整实现。"
	)


## 验证两侧共享同一套日志与报错文本，避免迁移后诊断信息漂移。
##
## @return 无返回值。
func test_shared_log_and_error_texts() -> void:
	var coordinator: String = FileAccess.get_file_as_string(COORDINATOR_GD)
	var pad_sources: Array[String] = []
	for path: String in LEGACY_PADS:
		pad_sources.append(CS_OPTIONAL.read(path))

	for literal: String in SHARED_TEXTS:
		assert_true(coordinator.contains(literal), "GDScript 生产脚本缺少文本：%s" % literal)
		if pad_sources.is_empty() or pad_sources[0].is_empty():
			continue
		var found: bool = false
		for source: String in pad_sources:
			if source.contains(literal):
				found = true
				break
		assert_true(found, "旧 C# 垫片集合缺少同文本：%s" % literal)


## 验证 GDScript 消费方仍只按稳定方法名与信号名调用协调器。
##
## @return 无返回值。
func test_consumers_use_stable_names() -> void:
	var passage_guard: String = FileAccess.get_file_as_string(
		"res://scripts/map_scripts/passage_guard_controller.gd"
	)
	var map_button: String = FileAccess.get_file_as_string("res://scripts/map_scripts/map_button/map_button.gd")
	var gameplay_port: String = FileAccess.get_file_as_string("res://core/application/gameplay_port.gd")

	for literal: String in [
		"RequestPassageGuardEncounter",
		"PassageGuardEncounterFinished",
	]:
		assert_true(passage_guard.contains(literal), "通道驻守控制器必须按稳定协议名调用：%s" % literal)

	for literal: String in [
		"BeginWorldHoldForMap",
		"CancelWorldHoldFor",
		"WorldHoldCompleted",
	]:
		assert_true(map_button.contains(literal), "地图按钮必须按稳定协议名调用：%s" % literal)

	assert_true(gameplay_port.contains("../WorldInteractionCoordinator"), "GameplayPort 必须按同级节点名解析倍率桥。")
	assert_true(gameplay_port.contains("ScaleEncounterMonsters"), "GameplayPort 必须按方法协议调用倍率入口。")


## 验证资产层不再残留旧 C# 世界交互协调器引用。
##
## @return 无返回值。
func test_no_legacy_csharp_script_in_assets() -> void:
	for directory: String in ["res://scenes", "res://resources"]:
		var offenders: Array[String] = _grep_asset_references(directory, "WorldInteractionCoordinator.cs")
		assert_eq(offenders, [] as Array[String], "资产不得继续引用旧 C# 协调器：%s" % str(offenders))


## 判断脚本文本是否声明 class_name。
##
## @param text GDScript 全文。
## @return 存在顶层 class_name 声明时返回 true。
func _declares_class_name(text: String) -> bool:
	for raw_line: String in text.split("\n"):
		var line: String = raw_line.strip_edges()
		if line.begins_with("class_name "):
			return true

	return false


## 递归扫描资产目录中的旧 C# 脚本引用。
##
## @param directory 起始目录的 res:// 路径。
## @param needle 待匹配的旧脚本文件名片段。
## @return 命中的资产路径数组。
func _grep_asset_references(directory: String, needle: String) -> Array[String]:
	var offenders: Array[String] = []
	var dir := DirAccess.open(directory)
	if dir == null:
		return offenders

	var base: String = directory.trim_suffix("/")
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if dir.current_is_dir():
			if not entry.begins_with("."):
				offenders.append_array(_grep_asset_references("%s/%s" % [base, entry], needle))
		elif entry.ends_with(".tscn") or entry.ends_with(".tres"):
			var path := "%s/%s" % [base, entry]
			if FileAccess.get_file_as_string(path).contains(needle):
				offenders.append(path)
		entry = dir.get_next()

	dir.list_dir_end()
	return offenders

## 验证地形操作族是 C#-only 兼容层，且 GDScript 生产路径逐条等价（本批新增）。
##
## 生产地形交互资源全部是 GDScript：它们返回「操作描述 Dictionary」，由
## world_interaction_coordinator.gd 内联执行，运行时不会实例化任何 C# TerrainOp。
## 本用例把两侧的操作词汇与副作用逐条对上，并证明资产层不再引用该族。
##
## @return 无返回值。
func test_terrain_op_family_boundary() -> void:
	var coordinator: String = FileAccess.get_file_as_string(COORDINATOR_GD)

	# 1) 旧 C# 操作族必须完整保留（兼容层，全量迁移完成前不得删除）。
	assert_eq(OP_FAMILY_CS.size(), 10, "旧 C# 操作族必须是 10 个文件。")
	# C# 操作族对照：垫片退役后整段退场，下面的 GDScript 断言仍照跑。
	for path: String in OP_FAMILY_CS:
		if not CS_OPTIONAL.present(path):
			continue
		assert_true(FileAccess.file_exists(path), "旧 C# 操作族文件必须保留：%s" % path)
		var source: String = FileAccess.get_file_as_string(path)
		assert_true(
			source.contains("Apply(WorldInteractionContext context)")
			or source.contains("abstract void Apply"),
			"旧 C# 操作必须保留 Apply 入口：%s" % path
		)

	# 2) GDScript 生产词汇与旧 C# 操作逐条对应。
	for row: Array in OP_VOCABULARY:
		var op_type: String = str(row[0])
		assert_true(coordinator.contains("\"%s\":" % op_type), "生产词汇必须保留：%s" % op_type)
		assert_true(coordinator.contains(str(row[1])), "GDScript 副作用必须保留：%s" % op_type)
		var legacy: String = CS_OPTIONAL.read(str(row[2]))
		if not legacy.is_empty():
			assert_true(legacy.contains(str(row[3])), "旧 C# 同类副作用必须保留：%s" % op_type)

	# 3) 未知操作类型必须硬失败，且两侧文本一致。
	assert_true(coordinator.contains("未知 GDScript 地形操作类型"), "GDScript 必须拒绝未知操作。")
	var executor_text: String = CS_OPTIONAL.read(TERRAIN_EXECUTOR_CS)
	if not executor_text.is_empty():
		assert_true(
			executor_text.contains("未知 GDScript 地形操作类型"),
			"旧 C# 必须拒绝未知操作。"
		)

	# 4) 生产交互资源全部实现 build_ops，旧 C# 交互链只提供 BuildOps。
	for path: String in GD_INTERACTIONS:
		assert_true(
			FileAccess.get_file_as_string(path).contains("func build_ops"),
			"生产交互资源必须实现 build_ops：%s" % path
		)

	# 5) 资产层不再引用 C# 操作族与 C# 交互资源（运行期不可达的证据）。
	var needles: Array[String] = [
		"operations/",
		"BossInteraction.cs",
		"FarmingInteraction.cs",
		"GatheringInteraction.cs",
		"ReusableGatheringInteraction.cs",
		"VaultInteraction.cs",
	]
	for directory: String in ["res://scenes", "res://resources", "res://res", "res://items"]:
		for needle: String in needles:
			var offenders: Array[String] = _grep_asset_references(directory, needle)
			assert_eq(
				offenders,
				[] as Array[String],
				"资产不得引用旧 C# 地形交互链（%s / %s）：%s" % [directory, needle, str(offenders)]
			)
