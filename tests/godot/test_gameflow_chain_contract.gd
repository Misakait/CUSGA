@tool
extends McpTestSuite

## C# 地形交互链（resources/interaction + core/gameflow 半幅）迁移契约套件。
##
## 锁定 8 个旧 C# 类型：TerrainInteraction / TerrainInteractionBuildContext /
## WorldInteractionContext / WorldInteractionPorts（3 个端口接口）/
## TerrainInteractionExecutor / ScreenTransitionAdapter / WorldCombatScenePresenter /
## WorldViewVisibilityController。
##
## 判定：这条 C# 链是**兼容层**，其 GDScript 等价物已经存在，且集中在两处：
## 1）GDScript 交互资源的 `@export var TimeCost` + `build_ops(player, terrain, override)` 三重参数协议
##   （等价 TerrainInteraction + TerrainInteractionBuildContext）；
## 2）core/gameflow/world_interaction_coordinator.gd 的内联实现（等价 WorldInteractionContext /
##   WorldInteractionPorts / TerrainInteractionExecutor / ScreenTransitionAdapter /
##   WorldCombatScenePresenter / WorldViewVisibilityController，连日志标签都同文本）。
## 本批不新增生产脚本、不改资产，只把这些等价关系与「零生产依赖」钉成断言。
## C# 物理退役后，依赖垫片的对照断言经 CS_OPTIONAL 自动退场（见 tests/godot/csharp_optional.gd）。

## 世界交互协调器（GDScript 生产实现）。
const COORDINATOR: String = "res://core/gameflow/world_interaction_coordinator.gd"

## 迁移期 C# 可选助手：C# 退役后 C# 对照断言自动退场，GDScript 侧断言照跑。
## 说明见 tests/godot/csharp_optional.gd。
const CS_OPTIONAL := preload("res://tests/godot/csharp_optional.gd")

## 生产地形交互资源（GDScript）。
const INTERACTION_RESOURCES: Array = [
	"res://resources/interaction/farming_interaction.gd",
	"res://resources/interaction/vault_interaction.gd",
	"res://resources/interaction/gathering_interaction.gd",
	"res://resources/interaction/boss_interaction.gd",
	"res://resources/interaction/reusable_gathering_interaction.gd",
]

## 逐条契约：[名称, C# 路径, [C# 必须存在的片段], [[GDScript 路径, [必须存在的片段]], …]]。
const CHAIN_ROWS: Array = [
	[
		"TerrainInteraction",
		"res://resources/interaction/TerrainInteraction.cs",
		[
			"[GlobalClass]",
			"public abstract partial class TerrainInteraction : Resource",
			"[Export] public int TimeCost { get; set; } = 20;",
			"public abstract IReadOnlyList<TerrainOp> BuildOps(TerrainInteractionBuildContext context);",
		],
		[],
	],
	[
		"TerrainInteractionBuildContext",
		"res://resources/interaction/TerrainInteractionBuildContext.cs",
		[
			"public partial class TerrainInteractionBuildContext : RefCounted",
			"public required Node Player { get; init; }",
			"public required RefCounted Terrain { get; init; }",
			"public Node TimeSystem { get; init; }",
			"public int? EffectiveTimeCostOverride { get; init; }",
		],
		[
			[
				COORDINATOR,
				[
					"interaction.call(\"build_ops\", player, terrain, int(effective_time_cost_override))",
					"built_ops = interaction.call(\"build_ops\", player, terrain)",
				],
			],
		],
	],
	[
		"WorldInteractionContext",
		"res://resources/interaction/WorldInteractionContext.cs",
		[
			"public sealed partial class WorldInteractionContext : RefCounted",
			"public required IInteractionGameplayPort Gameplay { get; init; }",
			"public required IInteractionBoardPort Board { get; init; }",
			"public required IInteractionEncounterPort Encounters { get; init; }",
			"public required RefCounted Terrain { get; init; }",
			"public required Vector2 SourceGlobalPosition { get; init; }",
		],
		[
			[COORDINATOR, ["func _apply_gdscript_ops("]],
		],
	],
	[
		"WorldInteractionPorts",
		"res://resources/interaction/WorldInteractionPorts.cs",
		[
			"public interface IInteractionGameplayPort",
			"void RequestOpenFarmingPanel(RefCounted terrain);",
			"void RequestOpenWarehouse();",
			"void RequestEncounter(RefCounted terrain, Resource monster, string message);",
			"void RequestEncounter(RefCounted terrain, Array<Resource> monsters, string message);",
			"public interface IInteractionBoardPort",
			"void SpawnLootCards(Array drops, Vector2 spawnOrigin);",
			"void RemoveSourceCard();",
			"public interface IInteractionEncounterPort",
			"GatheringEncounterResult ResolveGatheringEncounter(StringName resourceTag);",
		],
		[
			[
				COORDINATOR,
				[
					"_gameplay_port.call(\"RequestOpenWarehouse\")",
					"_gameplay_port.call(\"RequestOpenFarmingPanel\", terrain)",
					"_gameplay_port.call(\"RequestEncounter\", terrain, monster, \"Boss Battle!\")",
					"_board_controller.call(\"SpawnLootCards\", drops, card.global_position)",
					"_board_controller.call(\"RemoveCard\", card)",
					"_encounter_manager.call(\"ResolveGatheringEncounter\", resource_tag, encounter_chance_multiplier)",
				],
			],
		],
	],
	[
		"TerrainInteractionExecutor",
		"res://core/gameflow/TerrainInteractionExecutor.cs",
		[
			"public sealed class TerrainInteractionExecutor(",
			"public void Execute(",
			"private static void ApplyOps(IReadOnlyList<TerrainOp> ops, WorldInteractionContext context)",
			"private static void ApplyGDScriptOps(",
			"private static Godot.Collections.Array ConvertDrops(Variant rawDrops)",
			"private static int ReadTotalTime(Node timeSystem)",
			"private sealed class GameplayInteractionPort(Node gameplayPort) : IInteractionGameplayPort",
			"private sealed class BoardInteractionPort(Node boardController, Node2D sourceCard) : IInteractionBoardPort",
			"private sealed class EncounterInteractionPort(",
			"private static float GetNightEncounterChanceMultiplier(Node equipment)",
		],
		[
			[
				COORDINATOR,
				[
					"func _execute_terrain_interaction(",
					"print(\"[TerrainInteractionExecutor] Click terrain: %s\" % terrain_name)",
					"\"[TerrainInteractionExecutor] Build GDScript ops from %s\"",
					"print(\"[TerrainInteractionExecutor] GDScript ops count = %d\" % raw_ops.size())",
					"func _convert_drops(raw_drops: Variant) -> Array:",
					"func _get_night_encounter_chance_multiplier(equipment: Node) -> float:",
					"func _resolve_gathering_encounter(resource_tag: StringName) -> Variant:",
				],
			],
		],
	],
	[
		"ScreenTransitionAdapter",
		"res://core/gameflow/ScreenTransitionAdapter.cs",
		[
			"public sealed class ScreenTransitionAdapter(Node awaiter, Node screenTransitions)",
			"public Task FadeOutAsync()",
			"public Task FadeInAsync()",
			"private async Task RunAsync(string methodName, string completedSignal)",
		],
		[
			[
				COORDINATOR,
				[
					"var ScreenTransitionsPath: NodePath = ^\"/root/ScreenTransitions\"",
					"func _fade_out() -> void:",
					"func _fade_in() -> void:",
					"func _run_screen_transition(method_name: String, completed_signal: StringName) -> void:",
					"_screen_transitions.connect(completed_signal, on_completed, CONNECT_ONE_SHOT)",
				],
			],
		],
	],
	[
		"WorldCombatScenePresenter",
		"res://core/gameflow/WorldCombatScenePresenter.cs",
		[
			"public async Task EnterCombatAsync(Array<Resource> battleDeck, Array<Resource> monsters)",
			"public async Task<bool> EnterCombatAndWaitForResultAsync(",
			"private async void OnBattleEnded(Node battleInstance, bool isVictory, TaskCompletionSource<bool> completion)",
			"private static Node CreateBattleInstance(Array<Resource> battleDeck, Array<Resource> monsters)",
			"private static Sprite2D DuplicateCurrentBackground(Node mapSystem)",
		],
		[
			[
				COORDINATOR,
				[
					"func _enter_combat(battle_deck: Array[Resource], monsters: Array[Resource]) -> bool:",
					"func _enter_combat_and_wait_for_result(",
					"func _on_battle_ended(is_victory: bool, battle_instance: Node) -> void:",
					"func _create_battle_instance(battle_deck: Array[Resource], monsters: Array[Resource]) -> Node:",
					"func _duplicate_current_background() -> Sprite2D:",
					"print(\"[WorldCombatScenePresenter] Entering Combat!\")",
					"print(\"[WorldCombatScenePresenter] Combat Ended! Victory: %s\" % str(is_victory))",
					"const BATTLE_SCENE_PATH: String = \"res://scenes/battle_scenes/battle.tscn\"",
				],
			],
		],
	],
	[
		"WorldViewVisibilityController",
		"res://core/gameflow/WorldViewVisibilityController.cs",
		[
			"public sealed class WorldViewVisibilityController(",
			"public void HideWorldView()",
			"public void ShowWorldView()",
			"private void SetWorldViewVisible(bool visible)",
			"private void SetCanvasItemVisible(NodePath path, bool visible)",
			"private void SetCanvasLayerVisible(NodePath path, bool visible)",
		],
		[
			[
				COORDINATOR,
				[
					"func _set_world_view_visible(visible: bool) -> void:",
					"_set_canvas_item_visible(BoardControllerPath, visible)",
					"_set_canvas_item_visible(MapSystemPath, visible)",
					"_set_canvas_layer_visible(MapCanvasLayerPath, visible)",
					"_set_canvas_layer_visible(HudLayerPath, visible)",
					"func _set_canvas_item_visible(path: NodePath, visible: bool) -> void:",
					"func _set_canvas_layer_visible(path: NodePath, visible: bool) -> void:",
				],
			],
		],
	],
]

## 生产 GDScript 扫描根目录（不含 res://tests）。
const PRODUCTION_ROOTS: Array = [
	"res://core",
	"res://entities",
	"res://resources",
	"res://scripts",
]

## 资产扫描根目录。
const ASSET_ROOTS: Array = [
	"res://scenes",
	"res://resources",
	"res://res",
]


## 返回 GodotAI 使用的稳定套件名称。
##
## @return C# 地形交互链契约套件名。
func suite_name() -> String:
	return "gameflow_chain_contract"


## 验证旧 C# 链的 8 个文件与 GDScript 等价物同时存在。
##
## @return 无返回值。
func test_chain_shape() -> void:
	for row: Array in CHAIN_ROWS:
		if CS_OPTIONAL.present(str(row[1])):
			assert_true(FileAccess.file_exists(str(row[1])), "旧 C# 链文件必须保留为兼容层：%s" % row[1])
		for carrier_row: Array in row[3]:
			assert_true(FileAccess.file_exists(str(carrier_row[0])), "GDScript 等价物必须存在：%s" % carrier_row[0])
	for gd_path: String in INTERACTION_RESOURCES:
		assert_true(FileAccess.file_exists(gd_path), "生产地形交互资源必须存在：%s" % gd_path)
		var text: String = FileAccess.get_file_as_string(gd_path)
		assert_true(
			text.contains("@export var TimeCost: int = 20"),
			"生产交互资源必须保留旧 C# 默认耗时 TimeCost = 20：%s" % gd_path
		)
		assert_true(text.contains("func build_ops("), "生产交互资源必须实现 build_ops 协议：%s" % gd_path)


## 验证 C# 链的公开面与 GDScript 等价实现逐条对应。
##
## @return 无返回值。
func test_chain_boundaries() -> void:
	for row: Array in CHAIN_ROWS:
		var name: String = str(row[0])
		# C# 对照部分：垫片退役后整段退场，下面的 GDScript 断言仍照跑。
		var cs_text: String = CS_OPTIONAL.read(str(row[1]))
		if not cs_text.is_empty():
			for needle: String in row[2]:
				assert_true(cs_text.contains(needle), "旧 C# 链必须保留既有公开面：%s → %s" % [name, needle])
		for carrier_row: Array in row[3]:
			var gd_path: String = str(carrier_row[0])
			var gd_text: String = FileAccess.get_file_as_string(gd_path)
			for needle: String in carrier_row[1]:
				assert_true(
					gd_text.contains(needle),
					"GDScript 等价实现必须保留同名入口：%s → %s" % [gd_path, needle]
				)


## 验证生产 GDScript 不依赖这 8 个 C# 类型与它们的脚本路径。
##
## @return 无返回值。
func test_no_production_gdscript_dependency() -> void:
	for row: Array in CHAIN_ROWS:
		var name: String = str(row[0])
		var cs_path: String = str(row[1])
		for root: String in PRODUCTION_ROOTS:
			assert_eq(
				_scan(root, name, [".gd"], true),
				[],
				"生产 GDScript 不得引用旧 C# 链类型：%s（%s）" % [name, root]
			)
			assert_eq(
				_scan(root, cs_path, [".gd"], false),
				[],
				"生产 GDScript 不得加载旧 C# 链脚本：%s（%s）" % [cs_path, root]
			)


## 验证资产与场景不引用这 8 个 C# 链脚本。
##
## @return 无返回值。
func test_no_asset_dependency() -> void:
	for row: Array in CHAIN_ROWS:
		var cs_path: String = str(row[1])
		for root: String in ASSET_ROOTS:
			assert_eq(
				_scan(root, cs_path, [".tscn", ".tres", ".res"], false),
				[],
				"资产不得引用旧 C# 链脚本：%s（%s）" % [cs_path, root]
			)


## 递归扫描目录，按扩展名匹配文本；code_only 为真时只匹配 .gd 的代码部分。
##
## @param directory 起始目录的 res:// 路径。
## @param needle 待匹配文本。
## @param extensions 参与匹配的扩展名列表。
## @param code_only 是否忽略 .gd 的注释与字符串字面量。
## @return 命中文件的 res:// 路径数组。
func _scan(directory: String, needle: String, extensions: Array, code_only: bool) -> Array:
	var offenders: Array = []
	var dir := DirAccess.open(directory)
	if dir == null:
		return offenders

	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if dir.current_is_dir():
			if not entry.begins_with("."):
				offenders.append_array(_scan("%s/%s" % [directory, entry], needle, extensions, code_only))
		else:
			var matched_extension: bool = false
			for extension: String in extensions:
				if entry.ends_with(extension):
					matched_extension = true
					break
			if matched_extension:
				var path := "%s/%s" % [directory, entry]
				var text: String = FileAccess.get_file_as_string(path)
				if code_only:
					for raw_line: String in text.split("\n"):
						if _strip_gd_comments_and_strings(raw_line).contains(needle):
							offenders.append(path)
							break
				elif text.contains(needle):
					offenders.append(path)
		entry = dir.get_next()

	dir.list_dir_end()
	return offenders


## 去掉一行 GDScript 的注释与字符串字面量，只保留代码部分。
##
## @param line GDScript 源码的一行。
## @return 去掉注释与字符串字面量后的代码文本。
func _strip_gd_comments_and_strings(line: String) -> String:
	var code: String = ""
	var in_string: bool = false
	var quote: String = ""
	var index: int = 0
	while index < line.length():
		var character: String = line[index]
		if in_string:
			if character == "\\":
				index += 2
				continue
			if character == quote:
				in_string = false
			index += 1
			continue
		if character == "\"" or character == "'":
			in_string = true
			quote = character
			index += 1
			continue
		if character == "#":
			break
		code += character
		index += 1
	return code
