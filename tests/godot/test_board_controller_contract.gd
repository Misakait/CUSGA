@tool
extends McpTestSuite

## BoardController 生产迁移契约套件。
##
## 套件锁定五件事：棋盘控制器改为 GDScript 生产实现且公开面逐字等价旧 C#、Main.tscn 完成脚本切换、
## 三个 C# 消费方降级为 Node 方法协议、旧 C# 垫片保留完整实现作为兼容输入、全项目生产 C# 不再引用
## BoardController 具体类型。“卡牌能否真的生成、点击能否真的转发、移除能否真的清索引”由运行中的
## 游戏经 game_eval 验证，本套件只做静态契约与资产引用核对。
## C# 物理退役后，依赖垫片的对照断言经 tests/godot/csharp_optional.gd 自动退场。

## 本批生产脚本与旁车 UID。
const CONTROLLER_GD: String = "res://core/board/board_controller.gd"
const CONTROLLER_GD_UID: String = "res://core/board/board_controller.gd.uid"
## 旧 C# 垫片；全量迁移完成前必须保留完整实现，不能掏空。
const CONTROLLER_CS: String = "res://core/board/BoardController.cs"
## 两侧共用同一份状态脚本。
const CARD_STATE_GD: String = "res://core/board/board_card_state.gd"

## 主场景与必须保持原值的资产 id。
const MAIN_SCENE: String = "res://scenes/Main.tscn"
const MAIN_SCENE_SCRIPT_ID: String = "2_0bbpv"
const MAIN_CARD_VIEW_SCENE_ID: String = "4_vcsgt"

## 已降级为稳定 Node 方法协议的消费方；世界交互协调器已切换为 GDScript 生产实现。
const CONSUMER_SCRIPTS: Array[String] = [
	"res://core/map/RoomBoardPresenter.cs",
	"res://core/gameflow/TerrainInteractionExecutor.cs",
	"res://core/gameflow/world_interaction_coordinator.gd",
]

## 迁移期 C# 消费方垫片路径（与 CONSUMER_SCRIPTS 前两项一致），C# 退役后不再要求存在。
const CONSUMER_CS: Array[String] = [
	"res://core/map/RoomBoardPresenter.cs",
	"res://core/gameflow/TerrainInteractionExecutor.cs",
]

## 迁移期 C# 可选助手：C# 退役后 C# 对照断言自动退场，GDScript 侧断言照跑。
## 说明见 tests/godot/csharp_optional.gd。
const CS_OPTIONAL := preload("res://tests/godot/csharp_optional.gd")

## 房间棋盘表现层已切换为 GDScript，同样只经 Node 方法协议访问棋盘控制器。
const PRESENTER_GD: String = "res://core/map/room_board_presenter.gd"

## 必须逐字保留在 GDScript 生产脚本里的 7 个信号声明。
const GD_SIGNALS: Array[String] = [
	"signal CardSpawned(card: Node2D)",
	"signal CardRemoved(card: Node2D)",
	"signal CardClicked(card: Node2D)",
	"signal CardPressed(card: Node2D)",
	"signal CardReleased(card: Node2D)",
	"signal CardHoverStarted(card: Node2D)",
	"signal CardHoverEnded(card: Node2D)",
]

## 必须逐字保留在 GDScript 生产脚本里的 4 个导出。
const GD_EXPORTS: Array[String] = [
	"@export var CardViewScene: PackedScene = null",
	"@export var CardsRootPath: NodePath = NodePath(\"\")",
	"@export var ScatterRadiusMin: float = 40.0",
	"@export var ScatterRadiusMax: float = 90.0",
]

## 公开方法必须两侧同名；这里逐字锁定 GDScript 侧签名。
const GD_PUBLIC_METHODS: Array[String] = [
	"func _ready() -> void:",
	"func _exit_tree() -> void:",
	"func SpawnTerrainCard(terrain_instance: RefCounted, global_position: Vector2) -> Node2D:",
	"func SpawnLootCard(stack: RefCounted, global_position: Vector2) -> Node2D:",
	"func SpawnLootCards(stacks: Array, spawn_origin: Vector2) -> void:",
	"func RemoveCard(card: Node2D) -> void:",
	"func ClearAllCards() -> void:",
	"func TryGetTerrainCardByLocalGrid(grid_pos: Vector2i) -> Node2D:",
	"func GetTerrainCardByLocalGridOrNull(grid_pos: Vector2i) -> Node2D:",
	"func HasTerrainCardAtLocalGrid(grid_pos: Vector2i) -> bool:",
	"func GetActiveCardsSnapshot() -> Array[Node2D]:",
]

## 旧 C# 垫片必须继续提供的公开方法签名。
const CS_PUBLIC_METHODS: Array[String] = [
	"public override void _Ready()",
	"public override void _ExitTree()",
	"public Node2D SpawnTerrainCard(RefCounted terrainInstance, Vector2 globalPosition)",
	"public Node2D SpawnLootCard(RefCounted stack, Vector2 globalPosition)",
	"public void SpawnLootCards(Godot.Collections.Array stacks, Vector2 spawnOrigin)",
	"public void RemoveCard(Node2D card)",
	"public void ClearAllCards()",
	"public bool TryGetTerrainCardByLocalGrid(Vector2I gridPos, out Node2D card)",
	"public Node2D GetTerrainCardByLocalGridOrNull(Vector2I gridPos)",
	"public bool HasTerrainCardAtLocalGrid(Vector2I gridPos)",
	"public IReadOnlyList<Node2D> GetActiveCardsSnapshot()",
]

## 必须两侧逐字一致的运行日志片段。
const LOG_TEXTS: Array[String] = [
	"[BoardController] Spawn terrain card at ",
	"Removing card: ",
	"Removed card: ",
	"Card clicked: ",
]

## 必须两侧逐字一致的报错文本。
const ERROR_TEXTS: Array[String] = [
	"BoardController.CardViewScene 未设置。",
	"已经存在地形卡。",
	"未知棋盘卡状态，无法初始化视图。",
	"TerrainInstance.TerrainData 不能为空。",
	"LootStack 必须提供非空 Item、正 Amount 与 IsEmpty 属性。",
	"无法加载棋盘卡状态脚本：",
]


## 返回 GodotAI 使用的稳定套件名称。
##
## @return 棋盘控制器契约套件名。
func suite_name() -> String:
	return "board_controller_contract"


## 验证生产脚本形状、UID 旁车与 GDScript 书写约定。
##
## @return 无返回值。
func test_production_script_shape() -> void:
	for path: String in [CONTROLLER_GD, CONTROLLER_GD_UID, CARD_STATE_GD]:
		assert_true(FileAccess.file_exists(path), "契约文件必须存在：%s" % path)

	var controller: String = FileAccess.get_file_as_string(CONTROLLER_GD)
	assert_true(controller.begins_with("extends Node2D"), "棋盘控制器必须直接继承 Node2D。")
	assert_false(_declares_class_name(controller), "棋盘控制器不得声明 class_name，避免与兼容垫片重名。")
	assert_false(controller.contains("TODO"), "生产脚本不得保留 TODO 占位。")
	assert_false(controller.contains("ClassDB"), "生产脚本不得通过反射类型库绕过协议。")
	# 回归：Godot 的整型向量类型是 Vector2i，写成 Vector2I 会在游戏启动时
	# 触发 “Could not find type Vector2I” 的解析错误并卡在 break 状态。
	assert_false(controller.contains("Vector2I"), "Godot 类型名必须写成 Vector2i，不得写成 Vector2I。")
	assert_true(
		controller.contains("BOARD_CARD_STATE_SCRIPT: GDScript = preload(\"%s\")" % CARD_STATE_GD),
		"棋盘控制器必须通过 GDScript 状态脚本创建卡牌状态。"
	)
	# 回归：路径常量必须是 NodePath。get_node() 只接受 NodePath，
	# 传 StringName 会在运行时触发 Parser Error。
	assert_false(controller.contains("_PATH: StringName = "), "节点路径常量不得声明为 StringName。")
	assert_true(
		controller.contains("@export var CardsRootPath: NodePath = NodePath(\"\")"),
		"卡牌根路径必须使用 NodePath 导出。"
	)

	for literal: String in GD_SIGNALS:
		assert_true(controller.contains(literal), "必须保留信号声明：%s" % literal)

	for literal: String in GD_EXPORTS:
		assert_true(controller.contains(literal), "必须保留导出声明：%s" % literal)

	var uid_text: String = FileAccess.get_file_as_string(CONTROLLER_GD_UID).strip_edges()
	assert_true(uid_text.begins_with("uid://"), "旁车 UID 必须是 uid:// 形式。")
	assert_true(
		FileAccess.get_file_as_string(MAIN_SCENE).contains(uid_text),
		"主场景必须引用生产脚本的同一 UID。"
	)


## 验证公开方法面在两种语言之间逐字对应。
##
## @return 无返回值。
func test_public_surface_matches_legacy_csharp() -> void:
	var controller: String = FileAccess.get_file_as_string(CONTROLLER_GD)

	for literal: String in GD_PUBLIC_METHODS:
		assert_true(controller.contains(literal), "GDScript 生产脚本缺少公开入口：%s" % literal)

	# C# 对照部分：垫片退役后整段退场，上面的 GDScript 断言仍照跑。
	var legacy: String = CS_OPTIONAL.read(CONTROLLER_CS)
	if legacy.is_empty():
		return
	for literal: String in CS_PUBLIC_METHODS:
		assert_true(legacy.contains(literal), "旧 C# 垫片缺少公开入口：%s" % literal)

	var gd_names: Array[String] = _extract_gd_public_function_names(controller)
	var cs_names: Array[String] = _extract_cs_public_method_names(legacy)
	assert_eq(gd_names, cs_names, "两侧公开方法名集合必须完全一致，否则跨语言调用会静默失效。")


## 验证主场景完成脚本切换且保留原有节点结构与导出值。
##
## @return 无返回值。
func test_main_scene_switched_to_gdscript() -> void:
	var scene: String = FileAccess.get_file_as_string(MAIN_SCENE)
	assert_true(
		scene.contains("path=\"%s\" id=\"%s\"" % [CONTROLLER_GD, MAIN_SCENE_SCRIPT_ID]),
		"主场景必须复用原 ext_resource id 指向 GDScript 生产脚本。"
	)
	assert_false(scene.contains("BoardController.cs"), "主场景不得继续引用旧 C# 棋盘控制器。")
	assert_true(
		scene.contains("CardViewScene = ExtResource(\"%s\")" % MAIN_CARD_VIEW_SCENE_ID),
		"卡牌视图预制体必须保持原 ext_resource 引用。"
	)
	assert_true(scene.contains("CardsRootPath = NodePath(\"CardsRoot\")"), "卡牌根路径导出值不得改变。")
	assert_true(
		scene.contains("[node name=\"CardsRoot\" type=\"Node2D\" parent=\"BoardSystem/BoardController\""),
		"卡牌根节点结构不得改变。"
	)


## 验证三个 C# 消费方只经稳定 Node 方法协议访问棋盘控制器。
##
## @return 无返回值。
func test_csharp_consumers_use_node_protocol() -> void:
	# GDScript 侧生产消费方必须始终存在。
	assert_true(FileAccess.file_exists(PRESENTER_GD), "消费方文件必须存在：%s" % PRESENTER_GD)
	assert_true(
		FileAccess.file_exists(CONSUMER_SCRIPTS[2]),
		"消费方文件必须存在：%s" % CONSUMER_SCRIPTS[2]
	)
	var presenter_gd: String = FileAccess.get_file_as_string(PRESENTER_GD)
	assert_true(
		presenter_gd.contains("_board_controller: Node"),
		"GDScript 房间展示层必须以 Node 持有棋盘控制器。"
	)
	assert_true(presenter_gd.contains("call(\"ClearAllCards\")"), "GDScript 清空棋盘必须走方法协议。")
	assert_true(
		presenter_gd.contains("call(\"SpawnTerrainCard\""),
		"GDScript 生成地形卡必须走方法协议。"
	)

	var coordinator: String = FileAccess.get_file_as_string(CONSUMER_SCRIPTS[2])
	assert_true(
		coordinator.contains("var _board_controller: Node = null"),
		"世界交互协调器必须以 Node 持有棋盘控制器。"
	)
	assert_true(coordinator.contains("connect(BOARD_CARD_CLICKED_SIGNAL"), "卡牌点击必须按稳定信号名连接。")
	assert_true(coordinator.contains("_disconnect_board_signal("), "退出时必须成对解除信号连接。")
	assert_true(
		coordinator.contains("call(\"GetActiveCardsSnapshot\")"),
		"可重复采集刷新必须走方法协议读取快照。"
	)
	assert_true(coordinator.contains("call(\"RemoveCard\""), "拾取后移除卡牌必须走方法协议。")

	# C# 侧消费方对照：垫片退役后整段退场。
	if not CS_OPTIONAL.present_all(CONSUMER_CS):
		return
	for path: String in CONSUMER_CS:
		assert_true(FileAccess.file_exists(path), "消费方文件必须存在：%s" % path)

	var presenter: String = FileAccess.get_file_as_string(CONSUMER_CS[0])
	assert_true(
		presenter.contains("GetNode<Node>(BoardControllerPath)"),
		"房间展示层必须以 Node 持有棋盘控制器。"
	)
	assert_true(presenter.contains("Call(\"ClearAllCards\")"), "清空棋盘必须走方法协议。")
	assert_true(presenter.contains("Call(\"SpawnTerrainCard\""), "生成地形卡必须走方法协议。")

	var executor: String = FileAccess.get_file_as_string(CONSUMER_CS[1])
	assert_true(executor.contains("Node boardController"), "地形执行器必须以 Node 持有棋盘控制器。")
	assert_true(executor.contains("Call(\"SpawnLootCards\""), "批量掉落必须走方法协议。")
	assert_true(executor.contains("Call(\"RemoveCard\""), "移除卡牌必须走方法协议。")

	# 全项目生产 C# 必须彻底摆脱棋盘控制器具体类型。
	var pattern := RegEx.new()
	pattern.compile("\\bBoardController\\b")
	for path: String in _list_project_csharp_files("res://"):
		if path == CONTROLLER_CS:
			continue
		var text: String = FileAccess.get_file_as_string(path)
		assert_false(
			pattern.search(text) != null,
			"生产 C# 不得继续出现 BoardController 具体类型：%s" % path
		)


## 验证旧 C# 垫片仍是完整实现，没有被掏空成空壳。
##
## @return 无返回值。
func test_legacy_shim_stays_complete() -> void:
	if not CS_OPTIONAL.present(CONTROLLER_CS):
		skip(CS_OPTIONAL.SKIP_REASON)
		return
	var legacy: String = FileAccess.get_file_as_string(CONTROLLER_CS)
	assert_true(
		legacy.contains("public partial class BoardController : Node2D"),
		"旧 C# 垫片必须保留原类型声明。"
	)
	for literal: String in [
		"private void SpawnSingleLootWithScatter(",
		"private Node2D SpawnCard(",
		"private static RefCounted CreateTerrainState(",
		"private static RefCounted CreateLootState(",
		"private static RefCounted CreateState(",
		"private void ConnectCardSignals(",
		"private void DisconnectCardSignals(",
		"private Vector2 RandomDirection()",
		"private static void DisconnectSignal(",
	]:
		assert_true(legacy.contains(literal), "旧 C# 垫片不得删除实现：%s" % literal)


## 验证两侧共享同一套日志与报错文本，避免迁移后诊断信息漂移。
##
## @return 无返回值。
func test_shared_log_and_error_texts() -> void:
	var controller: String = FileAccess.get_file_as_string(CONTROLLER_GD)
	var legacy: String = CS_OPTIONAL.read(CONTROLLER_CS)

	for literal: String in LOG_TEXTS:
		assert_true(controller.contains(literal), "GDScript 生产脚本缺少日志文本：%s" % literal)
		if not legacy.is_empty():
			assert_true(legacy.contains(literal), "旧 C# 垫片缺少日志文本：%s" % literal)

	for literal: String in ERROR_TEXTS:
		assert_true(controller.contains(literal), "GDScript 生产脚本缺少报错文本：%s" % literal)
		if not legacy.is_empty():
			assert_true(legacy.contains(literal), "旧 C# 垫片缺少报错文本：%s" % literal)


## 验证资产层不再残留旧 C# 棋盘控制器引用。
##
## @return 无返回值。
func test_no_legacy_csharp_script_in_assets() -> void:
	for directory: String in ["res://scenes", "res://resources"]:
		var offenders: Array[String] = _grep_asset_references(directory, "BoardController.cs")
		assert_eq(offenders, [] as Array[String], "资产不得继续引用旧 C# 棋盘控制器：%s" % str(offenders))


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


## 提取 GDScript 生产脚本的公开函数名，并归一化为可比较形式。
##
## @param text GDScript 全文。
## @return 归一化后的公开函数名数组。
func _extract_gd_public_function_names(text: String) -> Array[String]:
	var names: Array[String] = []
	var pattern := RegEx.new()
	if pattern.compile("func ([A-Za-z_][A-Za-z0-9_]*)\\(") != OK:
		return names

	for found: RegExMatch in pattern.search_all(text):
		var name: String = found.get_string(1)
		if name.begins_with("_"):
			# 生命周期回调在两种语言的书写风格不同，这里按等价公开面对齐后比较。
			if name == "_ready":
				names.append("ready")
			elif name == "_exit_tree":
				names.append("exittree")
			continue
		names.append(_normalize_method_name(name))

	names.sort()
	return names


## 提取旧 C# 垫片的公开方法名，用于与 GDScript 侧做同名核对。
##
## @param text C# 全文。
## @return 归一化后的公开方法名数组，已排除信号委托生成的 EventHandler。
func _extract_cs_public_method_names(text: String) -> Array[String]:
	var names: Array[String] = []
	var pattern := RegEx.new()
	if pattern.compile("public\\s+(?:override\\s+)?[\\w<>\\[\\]\\., ]+?\\s([A-Za-z_][A-Za-z0-9_]*)\\(") != OK:
		return names

	for found: RegExMatch in pattern.search_all(text):
		var name: String = found.get_string(1)
		if name.ends_with("EventHandler"):
			continue
		names.append(_normalize_method_name(name))

	names.sort()
	return names


## 归一化方法名，忽略两种语言的命名风格差异。
##
## @param name 原始方法名。
## @return 去掉下划线并小写后的方法名。
func _normalize_method_name(name: String) -> String:
	return name.replace("_", "").to_lower()


## 递归列出工程 C# 源码，跳过 addons、tests 与点目录。
##
## @param directory 起始目录的 res:// 路径。
## @return 命中的 .cs 文件路径数组。
func _list_project_csharp_files(directory: String) -> Array[String]:
	var files: Array[String] = []
	var dir := DirAccess.open(directory)
	if dir == null:
		return files

	# DirAccess 返回的目录路径可能自带尾随斜杠，这里统一去掉，避免拼出 res:/// 形式。
	var base: String = directory.trim_suffix("/")
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if dir.current_is_dir():
			if not entry.begins_with(".") and entry != "addons" and entry != "tests":
				files.append_array(_list_project_csharp_files("%s/%s" % [base, entry]))
		elif entry.ends_with(".cs"):
			files.append("%s/%s" % [base, entry])
		entry = dir.get_next()

	dir.list_dir_end()
	return files


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

	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if dir.current_is_dir():
			if not entry.begins_with("."):
				offenders.append_array(_grep_asset_references("%s/%s" % [directory, entry], needle))
		elif entry.ends_with(".tscn") or entry.ends_with(".tres"):
			var path := "%s/%s" % [directory, entry]
			if FileAccess.get_file_as_string(path).contains(needle):
				offenders.append(path)
		entry = dir.get_next()

	dir.list_dir_end()
	return offenders
