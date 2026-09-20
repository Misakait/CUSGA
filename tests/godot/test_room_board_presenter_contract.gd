@tool
extends McpTestSuite

## RoomBoardPresenter 生产迁移契约套件。
##
## 套件锁定五件事：房间棋盘表现层改为 GDScript 生产实现且导出面逐字等价旧 C#、Main.tscn 完成脚本
## 切换、跨语言边界全部走稳定方法/字段协议、旧 C# 垫片保留完整实现作为兼容输入、资产层不再引用旧
## 脚本。“进入房间能否真的清空并生成地形卡”由运行中的游戏经 game_eval 验证，本套件只做静态核对。
## C# 物理退役后，依赖垫片的对照断言经 CS_OPTIONAL 自动退场（见 tests/godot/csharp_optional.gd）。

## 本批生产脚本与旁车 UID。
const PRESENTER_GD: String = "res://core/map/room_board_presenter.gd"
const PRESENTER_GD_UID: String = "res://core/map/room_board_presenter.gd.uid"
## 旧 C# 垫片；全量迁移完成前必须保留完整实现，不能掏空。
const PRESENTER_CS: String = "res://core/map/RoomBoardPresenter.cs"

## 迁移期 C# 可选助手：C# 退役后 C# 对照断言自动退场，GDScript 侧断言照跑。
## 说明见 tests/godot/csharp_optional.gd。
const CS_OPTIONAL := preload("res://tests/godot/csharp_optional.gd")

## 主场景与必须保持原值的资产 id。
const MAIN_SCENE: String = "res://scenes/Main.tscn"
const MAIN_SCENE_SCRIPT_ID: String = "1_elqb8"

## 必须逐字保留在 GDScript 生产脚本里的 4 个导出。
const GD_EXPORTS: Array[String] = [
	"@export var MapSystemPath: NodePath = NodePath(\"\")",
	"@export var BoardControllerPath: NodePath = NodePath(\"\")",
	"@export var TerrainStorePath: NodePath = NodePath(\"\")",
	"@export var HideHarvestedTerrain: bool = true",
]

## 生产脚本必须提供的函数面。
const GD_FUNCTIONS: Array[String] = [
	"func _ready() -> void:",
	"func _exit_tree() -> void:",
	"func _on_room_entered(room_pos: Vector2i, room_scene: Node2D) -> void:",
	"func _read_total_time() -> int:",
	"func _create_initial_room_layout(room_pos: Vector2i, room_scene: Node2D) -> void:",
	"func _create_layout_generator() -> RefCounted:",
	"func _read_terrain_data(terrain: RefCounted) -> Resource:",
	"func _read_interaction(terrain_data: Resource) -> Resource:",
	"func _read_harvested(terrain: RefCounted) -> bool:",
	"func _read_board_position(terrain: RefCounted) -> Vector2:",
]

## 旧 C# 垫片必须继续提供的公开导出与方法。
const CS_MEMBERS: Array[String] = [
	"public NodePath MapSystemPath { get; set; }",
	"public NodePath BoardControllerPath { get; set; }",
	"public NodePath TerrainStorePath { get; set; }",
	"public bool HideHarvestedTerrain { get; set; } = true;",
	"private void OnRoomEntered(Vector2I roomPos, Node2D roomScene)",
	"private int ReadTotalTime()",
	"private void CreateInitialRoomLayout(Vector2I roomPos, Node2D roomScene)",
	"private static RefCounted CreateLayoutGenerator()",
]

## 必须两侧逐字一致的日志与报错文本。
const SHARED_TEXTS: Array[String] = [
	"[RoomBoardPresenter] Enter room ",
	"RoomBoardPresenter.MapSystemPath 未设置。",
	"RoomBoardPresenter.BoardControllerPath 未设置。",
	"RoomBoardPresenter.TerrainStorePath 未设置。",
	"MapSystem 缺少信号",
	"缺少地形布局生成器脚本：",
]


## 返回 GodotAI 使用的稳定套件名称。
##
## @return 房间棋盘表现层契约套件名。
func suite_name() -> String:
	return "room_board_presenter_contract"


## 验证生产脚本形状、UID 旁车与 GDScript 书写约定。
##
## @return 无返回值。
func test_production_script_shape() -> void:
	for path: String in [PRESENTER_GD, PRESENTER_GD_UID]:
		assert_true(FileAccess.file_exists(path), "契约文件必须存在：%s" % path)

	var presenter: String = FileAccess.get_file_as_string(PRESENTER_GD)
	assert_true(presenter.begins_with("extends Node"), "房间棋盘表现层必须直接继承 Node。")
	assert_false(_declares_class_name(presenter), "房间棋盘表现层不得声明 class_name，避免与兼容垫片重名。")
	assert_false(presenter.contains("TODO"), "生产脚本不得保留 TODO 占位。")
	# 回归：Godot 4 的整型向量类型是 Vector2i，写成 Vector2I 会在游戏启动时报解析错误。
	assert_false(presenter.contains("Vector2I"), "Godot 类型名必须写成 Vector2i，不得写成 Vector2I。")
	# 回归：路径常量必须是 NodePath，传 StringName 会在运行时触发 Parser Error。
	assert_false(presenter.contains("_PATH: StringName = "), "节点路径常量不得声明为 StringName。")
	assert_true(
		presenter.contains("const TIME_SYSTEM_PATH: NodePath = ^\"/root/TimeSystem\""),
		"时间 Autoload 路径常量必须是 NodePath 字面量。"
	)

	for literal: String in GD_EXPORTS:
		assert_true(presenter.contains(literal), "必须保留导出声明：%s" % literal)

	for literal: String in GD_FUNCTIONS:
		assert_true(presenter.contains(literal), "生产脚本缺少入口：%s" % literal)

	var uid_text: String = FileAccess.get_file_as_string(PRESENTER_GD_UID).strip_edges()
	assert_true(uid_text.begins_with("uid://"), "旁车 UID 必须是 uid:// 形式。")
	assert_true(
		FileAccess.get_file_as_string(MAIN_SCENE).contains(uid_text),
		"主场景必须引用生产脚本的同一 UID。"
	)


## 验证主场景完成脚本切换且保留原有节点结构与导出值。
##
## @return 无返回值。
func test_main_scene_switched_to_gdscript() -> void:
	var scene: String = FileAccess.get_file_as_string(MAIN_SCENE)
	assert_true(
		scene.contains("path=\"%s\" id=\"%s\"" % [PRESENTER_GD, MAIN_SCENE_SCRIPT_ID]),
		"主场景必须复用原 ext_resource id 指向 GDScript 生产脚本。"
	)
	assert_false(scene.contains("RoomBoardPresenter.cs"), "主场景不得继续引用旧 C# 房间棋盘表现层。")
	for literal: String in [
		'[node name="RoomBoardPresenter" type="Node" parent="BoardSystem"',
		'MapSystemPath = NodePath("../../MapSystem")',
		'BoardControllerPath = NodePath("../BoardController")',
		'TerrainStorePath = NodePath("../../RuntimeState/RoomTerrainStore")',
	]:
		assert_true(scene.contains(literal), "主场景序列化内容必须保持：%s" % literal)


## 验证跨语言边界全部走稳定方法/字段协议。
##
## @return 无返回值。
func test_cross_language_protocols() -> void:
	var presenter: String = FileAccess.get_file_as_string(PRESENTER_GD)
	for snippet: String in [
		"call(\"HasRoom\"",
		"call(\"CreateRoomLayout\"",
		"call(\"GetRoomTerrainsOrEmpty\"",
		"call(\"ClearAllCards\")",
		"call(\"SpawnTerrainCard\"",
		"room_terrain_layout_generator.gd",
		"call(\"Generate\"",
	]:
		assert_true(presenter.contains(snippet), "跨语言协议片段缺失：%s" % snippet)

	# 地形实例已迁移，配置/采集状态/显示位置必须按字段协议读取。
	for snippet: String in [
		'terrain.get("TerrainData")',
		'terrain.get("IsHarvested")',
		'terrain.get("BoardPosition")',
		'terrain_data.get("InteractionBehavior")',
		'room_scene.get("terrain_profile")',
		'_time_system.get("TotalTimePassed")',
	]:
		assert_true(presenter.contains(snippet), "字段协议片段缺失：%s" % snippet)

	# 可重复采集刷新必须同时接受旧 C# 方法名与生产 GDScript 方法名。
	assert_true(presenter.contains("has_method(\"RefreshIfReady\")"), "必须兼容旧 C# 刷新入口。")
	assert_true(presenter.contains("has_method(\"refresh_if_ready\")"), "必须兼容 GDScript 刷新入口。")

	# 时间系统已是 GDScript Autoload，不得退回 C# 静态单例。
	assert_false(presenter.contains("TimeSystem.Instance"), "不得依赖 C# TimeSystem 静态单例。")
	assert_true(
		presenter.contains("const TIME_SYSTEM_PATH: NodePath = ^\"/root/TimeSystem\""),
		"必须按 Autoload 路径取时间系统。"
	)


## 验证旧 C# 垫片仍是完整实现，没有被掏空成空壳。
##
## @return 无返回值。
func test_legacy_shim_stays_complete() -> void:
	if not CS_OPTIONAL.present(PRESENTER_CS):
		skip(CS_OPTIONAL.SKIP_REASON)
		return
	var legacy: String = FileAccess.get_file_as_string(PRESENTER_CS)
	assert_true(
		legacy.contains("public partial class RoomBoardPresenter : Node"),
		"旧 C# 垫片必须保留原类型声明。"
	)
	for literal: String in CS_MEMBERS:
		assert_true(legacy.contains(literal), "旧 C# 垫片不得删除实现：%s" % literal)


## 验证两侧共享同一套日志与报错文本，避免迁移后诊断信息漂移。
##
## @return 无返回值。
func test_shared_log_and_error_texts() -> void:
	var presenter: String = FileAccess.get_file_as_string(PRESENTER_GD)
	var legacy: String = CS_OPTIONAL.read(PRESENTER_CS)

	for literal: String in SHARED_TEXTS:
		assert_true(presenter.contains(literal), "GDScript 生产脚本缺少文本：%s" % literal)
		if not legacy.is_empty():
			assert_true(legacy.contains(literal), "旧 C# 垫片缺少文本：%s" % literal)

	assert_true(
		presenter.contains("\"[RoomBoardPresenter] Enter room %s, scene=%s\""),
		"房间进入日志格式必须与旧 C# 对齐。"
	)


## 验证资产层不再残留旧 C# 房间棋盘表现层引用。
##
## @return 无返回值。
func test_no_legacy_csharp_script_in_assets() -> void:
	for directory: String in ["res://scenes", "res://resources"]:
		var offenders: Array[String] = _grep_asset_references(directory, "RoomBoardPresenter.cs")
		assert_eq(offenders, [] as Array[String], "资产不得继续引用旧 C# 表现层：%s" % str(offenders))


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
