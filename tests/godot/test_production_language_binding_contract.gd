@tool
extends McpTestSuite

## 生产 GDScript 语言绑定清理契约套件（战斗技能过滤 / 拖拽载荷过滤）。
##
## 背景：物品链、地形链等批次完成后，生产 GDScript 里仍残留三处「按脚本路径判定语言身份」
## 的分支：`entities/monster.gd` 的战斗技能过滤、`core/ui/slot_ui.gd` 与
## `core/ui/equipment_slot_ui.gd` 的拖拽载荷过滤。这类判定把语言身份写进了生产逻辑：
## 新增同协议资源会被静默丢弃，C# 垫片退役后判定又会静默失效。
## 本套件锁定三件事：
## 1）三处判定改为能力 / 字段协议，GDScript 与旧 C# 两侧实例被一致接受；
## 2）生产 GDScript（core / entities / resources / scripts）不得再出现 `.cs` 脚本路径字面量；
## 3）协议判定对「非本协议对象」仍返回 false，不放松过滤强度。

## 生产脚本根目录（不含 tests / addons）。
const PRODUCTION_ROOTS: Array[String] = ["res://core", "res://entities", "res://resources", "res://scripts"]
## 本批改造的三个生产脚本。
const MONSTER_GD: String = "res://entities/monster.gd"
const SLOT_UI_GD: String = "res://core/ui/slot_ui.gd"
const EQUIPMENT_SLOT_UI_GD: String = "res://core/ui/equipment_slot_ui.gd"
## 判定双方：GDScript 生产实现与旧 C# 兼容垫片（C# 侧改为惰性加载，垫片退役后对照自动收起）。
const COMBAT_SKILL_GD_SCRIPT: Script = preload("res://core/combat/skills/combat_skill_data.gd")
const COMBAT_SKILL_CS_PATH: String = "res://core/combat/skills/CombatSkillData.cs"
const ITEM_SKILL_CARD_GD_SCRIPT: Script = preload("res://resources/item/card/skill_card_data.gd")
const ITEM_SKILL_CARD_CS_PATH: String = "res://resources/item/card/SkillCardData.cs"
const DRAGGABLE_GD_SCRIPT: Script = preload("res://core/ui/draggable/draggable_data.gd")
const DRAGGABLE_CS_PATH: String = "res://core/ui/draggable/DraggableData.cs"
## C# 可选助手：C# 退役后跨语言对照按条件收起，不因 `preload` 触发解析期错误。
const CS_OPTIONAL := preload("res://tests/godot/csharp_optional.gd")
## 判定宿主：怪物与两种槽位视图。
const MONSTER_SCRIPT: Script = preload("res://entities/monster.gd")
const SLOT_UI_SCRIPT: Script = preload("res://core/ui/slot_ui.gd")
const EQUIPMENT_SLOT_UI_SCRIPT: Script = preload("res://core/ui/equipment_slot_ui.gd")
## 旧路径扫描关键字：生产脚本里不允许出现的 C# 脚本扩展名。
const LEGACY_PATH_NEEDLE: String = ".cs"
## 能力协议字面量：战斗技能必须暴露的两个方法。
const COMBAT_SKILL_PROTOCOL_LITERAL: String = "const COMBAT_SKILL_REQUIRED_METHODS: Array[StringName] = [&\"Execute\", &\"RequiresTarget\"]"
## 字段协议字面量：拖拽载荷必须暴露的来源系统字段与取值类型探测。
const DRAG_FIELD_LITERAL: String = "const DRAG_PAYLOAD_SOURCE_FIELD: StringName = &\"SourceSystem\""
const DRAG_PROBE_LITERAL: String = "typeof((value as Object).get(DRAG_PAYLOAD_SOURCE_FIELD)) == TYPE_STRING_NAME"
## 携带怪物数据判定的四个生产脚本。
const MONSTER_DATA_JUDGEMENT_PATHS: Array[String] = [
	"res://core/application/encounter_manager.gd",
	"res://core/application/gameplay_port.gd",
	"res://core/gameflow/world_interaction_coordinator.gd",
	"res://resources/encounters/gathering_encounter_result.gd",
]
## 怪物资产目录与两种怪物数据实现。
const MONSTER_DIR: String = "res://resources/monster"
const MONSTER_DATA_CS_PATH: String = "res://resources/monster/MonsterData.cs"
const MONSTER_DATA_GD_SCRIPT: Script = preload("res://resources/monster/monster_data.gd")
const GATHERING_RESULT_SCRIPT: Script = preload("res://resources/encounters/gathering_encounter_result.gd")


func suite_name() -> String:
	return "production_language_binding_contract"


# ----- 解析与扫描助手 -----

## 读取文本文件内容。
##
## 参数 path：res:// 路径。
## 返回值：文件正文；读取失败时返回空字符串。
func _read(path: String) -> String:
	return FileAccess.get_file_as_string(path)


## 去掉 GDScript 注释，保留字符串字面量与换行。
##
## 参数 text：GDScript 源码。
## 返回值：注释被移除的源码。
func _strip_gd_comments(text: String) -> String:
	var out: String = ""
	var in_string: bool = false
	var index: int = 0
	var length: int = text.length()
	while index < length:
		var character: String = text[index]
		if in_string:
			out += character
			if character == "\\" and index + 1 < length:
				out += text[index + 1]
				index += 2
				continue
			if character == "\"":
				in_string = false
			index += 1
			continue
		if character == "\"":
			in_string = true
			out += character
			index += 1
			continue
		if character == "#":
			while index < length and text[index] != "\n":
				index += 1
			continue
		out += character
		index += 1
	return out


## 递归收集指定扩展名的文件。
##
## 参数 dir_path：res:// 目录。
## 参数 extensions：扩展名数组（不含点）。
## 返回值：命中的 res:// 路径数组。
func _collect_files(dir_path: String, extensions: Array) -> Array:
	var found: Array = []
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return found
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		var full: String = dir_path + "/" + file_name
		if file_name != "." and file_name != "..":
			if dir.current_is_dir():
				found.append_array(_collect_files(full, extensions))
			elif extensions.has(full.get_extension()):
				found.append(full)
		file_name = dir.get_next()
	dir.list_dir_end()
	return found


## 单趟扫描目录树，返回去注释后仍包含关键字的文件。
##
## 参数 roots：res:// 根目录数组。
## 参数 needle：目标子串。
## 返回值：命中的 res:// 路径数组。
func _scan_roots(roots: Array, needle: String) -> Array:
	var files: Array = []
	for root: String in roots:
		files.append_array(_collect_files(root, ["gd"]))
	var hits: Array = []
	for path: String in files:
		var text: String = _strip_gd_comments(_read(path))
		if text.find(needle) != -1:
			hits.append(path)
	return hits


## 汇总各根目录的生产 GDScript 文件总数。
##
## 返回值：文件数量。
func _production_gd_count() -> int:
	var count: int = 0
	for root: String in PRODUCTION_ROOTS:
		count += _collect_files(root, ["gd"]).size()
	return count


# ----- 断言 -----

## 生产 GDScript 不得再出现 C# 脚本路径；同时自证扫描确实有产出。
##
## @return 无返回值。
func test_production_gd_has_no_csharp_script_path() -> void:
	assert_gt(_production_gd_count(), 150, "生产 GDScript 数量异常，扫描可能没有产出。")
	var hits: Array = _scan_roots(PRODUCTION_ROOTS, LEGACY_PATH_NEEDLE)
	assert_eq(hits, [], "生产 GDScript 不得出现 C# 脚本路径字面量：%s" % str(hits))
	# 扫描自证：同一个扫描器必须在测试目录扫出已知的旧路径引用，否则「零命中」没有意义。
	var probe: Array = _scan_roots(["res://tests"], LEGACY_PATH_NEEDLE)
	assert_gt(probe.size(), 0, "扫描器必须能在测试目录扫出已知的 .cs 引用（自证）。")


## 三处生产判定的源码必须使用协议而不是脚本路径或类型名。
##
## @return 无返回值。
func test_judgements_use_protocols_only() -> void:
	var monster_text: String = _strip_gd_comments(_read(MONSTER_GD))
	assert_true(monster_text.contains(COMBAT_SKILL_PROTOCOL_LITERAL), "怪物必须声明战斗技能能力协议常量。")
	assert_true(monster_text.contains("resource.has_method(method_name)"), "怪物必须按能力协议过滤技能。")
	assert_true(not monster_text.contains("resource_path"), "怪物不得再按脚本路径过滤技能。")
	assert_true(not monster_text.contains(LEGACY_PATH_NEEDLE), "怪物代码里不得再出现 C# 技能脚本路径。")

	for path: String in [SLOT_UI_GD, EQUIPMENT_SLOT_UI_GD]:
		var text: String = _strip_gd_comments(_read(path))
		assert_true(text.contains(DRAG_FIELD_LITERAL), "%s 必须声明拖拽载荷字段协议常量。" % path)
		assert_true(text.contains(DRAG_PROBE_LITERAL), "%s 必须按字段取值类型探测拖拽载荷。" % path)
		assert_true(not text.contains("resource_path"), "%s 不得再按脚本路径判定载荷。" % path)
		assert_true(not text.contains(LEGACY_PATH_NEEDLE), "%s 代码里不得再出现 C# 载荷脚本路径。" % path)


## 战斗技能判定必须同时接受 GDScript 生产技能与旧 C# 垫片，并拒绝非技能资源。
##
## @return 无返回值。
func test_combat_skill_protocol_accepts_both_implementations() -> void:
	var monster: Object = track(MONSTER_SCRIPT.new())
	assert_true(bool(monster.call("_is_combat_skill_data", COMBAT_SKILL_GD_SCRIPT.new())), "GDScript 生产技能必须被接受。")
	assert_false(bool(monster.call("_is_combat_skill_data", ITEM_SKILL_CARD_GD_SCRIPT.new())), "GDScript 物品技能卡不得被当成怪物技能。")
	assert_false(bool(monster.call("_is_combat_skill_data", Resource.new())), "普通 Resource 不得被当成战斗技能。")
	assert_false(bool(monster.call("_is_combat_skill_data", null)), "null 不得被当成战斗技能。")
	## 跨语言对照：C# 垫片退役后不再有旧实现可测，整块按条件收起。
	if CS_OPTIONAL.present_all([COMBAT_SKILL_CS_PATH, ITEM_SKILL_CARD_CS_PATH]):
		assert_true(bool(monster.call("_is_combat_skill_data", CS_OPTIONAL.script(COMBAT_SKILL_CS_PATH).new())), "旧 C# 战斗技能垫片必须被接受。")
		assert_false(bool(monster.call("_is_combat_skill_data", CS_OPTIONAL.script(ITEM_SKILL_CARD_CS_PATH).new())), "旧 C# 物品技能卡不得被当成怪物技能。")


## 拖拽载荷判定必须同时接受 GDScript 生产载荷与旧 C# 垫片，并拒绝普通对象。
##
## @return 无返回值。
func test_drag_payload_protocol_accepts_both_implementations() -> void:
	for script: Script in [SLOT_UI_SCRIPT, EQUIPMENT_SLOT_UI_SCRIPT]:
		var view: Object = track(script.new())
		assert_true(bool(view.call("_is_draggable_data", DRAGGABLE_GD_SCRIPT.new())), "%s 必须识别 GDScript 拖拽载荷。" % script.resource_path)
		assert_false(bool(view.call("_is_draggable_data", RefCounted.new())), "%s 不得把普通对象当成拖拽载荷。" % script.resource_path)
		assert_false(bool(view.call("_is_draggable_data", null)), "%s 不得把 null 当成拖拽载荷。" % script.resource_path)
		## 跨语言对照：C# 垫片退役后按条件收起。
		if CS_OPTIONAL.present(DRAGGABLE_CS_PATH):
			assert_true(bool(view.call("_is_draggable_data", CS_OPTIONAL.script(DRAGGABLE_CS_PATH).new())), "%s 必须识别旧 C# DraggableData 载荷。" % script.resource_path)


## 怪物数据判定必须按字段协议同时接受 C# 与 GDScript 实现，且不再构造旧 C# 全局类。
##
## @return 无返回值。
func test_monster_data_protocol_is_field_based() -> void:
	for path: String in MONSTER_DATA_JUDGEMENT_PATHS:
		var text: String = _strip_gd_comments(_read(path))
		assert_true(text.contains("MONSTER_DATA_REQUIRED_FIELDS"), "%s 必须声明怪物数据字段协议。" % path)
		assert_true(not text.contains("is MonsterData"), "%s 不得再按旧 C# 类型判定怪物。" % path)
		assert_true(not text.contains("MonsterData.new()"), "%s 不得再构造旧 C# 全局类。" % path)

	var host: Object = track(GATHERING_RESULT_SCRIPT.new())
	assert_true(bool(host.call("_is_monster_data", MONSTER_DATA_GD_SCRIPT.new())), "GDScript 怪物数据必须被接受。")
	assert_false(bool(host.call("_is_monster_data", ITEM_SKILL_CARD_GD_SCRIPT.new())), "物品技能卡不得被当成怪物数据。")
	assert_false(bool(host.call("_is_monster_data", Resource.new())), "普通 Resource 不得被当成怪物数据。")
	assert_false(bool(host.call("_is_monster_data", null)), "null 不得被当成怪物数据。")
	## 跨语言对照：C# 垫片退役后按条件收起。
	if CS_OPTIONAL.present(MONSTER_DATA_CS_PATH):
		assert_true(bool(host.call("_is_monster_data", CS_OPTIONAL.script(MONSTER_DATA_CS_PATH).new())), "旧 C# 怪物数据必须被接受。")

	# 真实数据面：全部怪物资产必须仍被字段协议接受，避免过滤器静默丢弃生产怪物。
	var directory: DirAccess = DirAccess.open(MONSTER_DIR)
	assert_true(directory != null, "必须能打开怪物资产目录。")
	if directory == null:
		return
	var total: int = 0
	var accepted: int = 0
	var rejected: Array[String] = []
	directory.list_dir_begin()
	var file_name: String = directory.get_next()
	while file_name != "":
		if not directory.current_is_dir() and file_name.ends_with(".tres"):
			total += 1
			var asset: Resource = load(MONSTER_DIR + "/" + file_name)
			if bool(host.call("_is_monster_data", asset)):
				accepted += 1
			else:
				rejected.append(file_name)
		file_name = directory.get_next()
	directory.list_dir_end()

	assert_gt(total, 40, "怪物资产数量异常，扫描可能没有产出。")
	assert_eq(accepted, total, "以下怪物资产被字段协议拒绝：%s" % str(rejected))
