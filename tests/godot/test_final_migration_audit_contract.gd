@tool
extends McpTestSuite

## 迁移收尾审计契约套件：剩余 C# 面逐文件分类 + 「无运行时 C# 依赖」的可重复验证。
##
## 背景：项目自有 `.cs` 共 202 个（不含 obj / bin / .godot），其中 163 个存在同目录
## 蛇形 GDScript 孪生；剩下 39 个没有同名孪生文件。这 39 个此前只有「套件级」间接覆盖，
## 没有逐文件的归属判定，因此无法在不丢功能的前提下判断「哪些可以直接删、哪些必须保留
## 到全量迁移结束」。
##
## 本套件把 39 个文件分成四类，逐条钉住等价物证据，并把分类计数固定下来：
##   protocol     —— C# 侧协议 / 接口垫片；GDScript 等价物就是被它读取的生产脚本本身。
##   inlined      —— 已按同名协议内联进 GDScript 生产实现，运行时不再实例化对应 C# 类型。
##   logic        —— 非 Resource 逻辑类；等价实现已落地在 GDScript 生产脚本里。
##   test_harness —— C# 对照测试工程，不被任何 GDScript 测试或生产代码引用。
##
## 同时把「资产 / 生产 GDScript / Autoload 三层零 C# 引用」钉成可重复断言，并附带扫描器
## 自证探针，避免「扫描器坏掉也报通过」。
##
## 边界声明：**本套件不删除任何 C#**。迁移期 C# 仍是跨语言边界的证据与垫片，删除
## `.cs` / `.csproj` / `.sln` / Autoload 需要全量迁移完成后的单独授权。

## 分类字面量：协议垫片。
const KIND_PROTOCOL: String = "protocol"
## 分类字面量：已内联进 GDScript 生产实现。
const KIND_INLINED: String = "inlined"
## 分类字面量：非 Resource 逻辑类。
const KIND_LOGIC: String = "logic"
## 分类字面量：C# 对照测试工程。
const KIND_TEST_HARNESS: String = "test_harness"
## 允许出现的分类集合。
const ALLOWED_KINDS: Array[String] = [KIND_PROTOCOL, KIND_INLINED, KIND_LOGIC, KIND_TEST_HARNESS]
## 内联宿主：四个只被协调器使用的辅助类与十个地形操作类都内联在这里。
const INLINED_HOST_GD: String = "res://core/gameflow/world_interaction_coordinator.gd"
## 旧 C# 路径扫描关键字。
const LEGACY_PATH_NEEDLE: String = ".cs"
## 资产文件扩展名（场景 / 资源 / 项目设置）。
const ASSET_EXTENSIONS: Array[String] = ["tscn", "tres", "res", "godot"]
## 生产 GDScript 根目录（刻意不含 tests / addons）。
const PRODUCTION_ROOTS: Array[String] = ["res://core", "res://entities", "res://resources", "res://scripts"]
## 项目自有 C# 与 GDScript 的统计下界，用于防止扫描器静默返回空集。
const MIN_PRODUCTION_GD_COUNT: int = 150
## 迁移期必须继续存在的 C# 工程文件（不得在迁移完成前删除）。
const MIGRATION_HOST_FILES: Array[String] = ["res://CUSGA.csproj", "res://CUSGA.sln"]
## 阶段判据：C# 工程文件存在 = 迁移期（分类表 C# 必须齐全）；不存在 = 退役期（必须清零）。
const RETIREMENT_PHASE_MARKER: String = "res://CUSGA.csproj"
## C# 可选助手：C# 全量退役后这些「迁移期保留」用例改记跳过，而不是报失败。
const CS_OPTIONAL := preload("res://tests/godot/csharp_optional.gd")
## Autoload 段最少条目数（11 个 Autoload，其中 1 个是 GodotAI 运行期助手）。
const MIN_AUTOLOAD_COUNT: int = 11
## C# 源码扩展名。
const CS_EXTENSION: String = "cs"
## 扫描时要跳过的目录名：构建产物、引擎缓存与插件目录。
const SKIPPED_DIR_NAMES: Array[String] = ["obj", "bin", ".godot", "addons"]
## 「把 C# 类型名当类型使用」的写法模板。这些写法在 C# 垫片退役后会直接解析失败，
## 因此生产 GDScript 必须为零命中：is 类型测试、as 转换、new 构造、类型注解、返回类型注解、参数类型注解。
const TYPE_POSITION_PATTERNS: Array[String] = [
	"\\bis\\s+(%s)\\b",
	"\\bas\\s+(%s)\\b",
	"\\b(%s)\\s*\\.\\s*new\\s*\\(",
	"(?:var|const)\\s+[A-Za-z_][A-Za-z0-9_]*\\s*:\\s*(%s)\\b",
	"->\\s*(%s)\\b",
	"(?:\\(|,)\\s*[A-Za-z_][A-Za-z0-9_]*\\s*:\\s*(%s)\\b",
]
## 任意标识符模板，仅用于证明「名字表 + 正则 + 文件读取」这条管线真的读到了内容。
const ANY_IDENTIFIER_PATTERNS: Array[String] = ["\\b(%s)\\b"]
## 已退役的语言身份判定谓词名；C# 物理退役后生产脚本必须零命中，本常量只用于扫描自证。
const LANGUAGE_BOUNDARY_NEEDLE: String = "_is_csharp_script_instance"
## 已退役的「按脚本扩展名判定语言」实现字面量；C# 物理退役后生产脚本必须零命中。
const LANGUAGE_EXTENSION_CHECK_LITERAL: String = "get_extension().to_lower() == \"cs\""
## `[ext_resource …]` 行里 uid 属性的前缀（带前导空格，避免与 id 属性混淆）。
const EXT_RESOURCE_UID_PREFIX: String = ' uid="'
## `[ext_resource …]` 行里 id 属性的前缀。
const EXT_RESOURCE_ID_PREFIX: String = ' id="'
## `[node …]` / `[sub_resource …]` 块里挂载脚本的行前缀。
const SCRIPT_ASSIGNMENT_PREFIX: String = 'script = ExtResource("'
## `[node …]` / `[sub_resource …]` 块里「自定义类型脚本」元数据的行前缀。
const CUSTOM_TYPE_SCRIPT_PREFIX: String = 'metadata/_custom_type_script = "'
## 扫描到的「自定义类型脚本」块数下界，用于防止扫描器静默返回空集。
const MIN_CUSTOM_TYPE_SCRIPT_BLOCKS: int = 400
## 允许保留「无法解析」的 uid 声明：目标是项目里本就不存在的文件，属已登记的遗留项。
const KNOWN_UNRESOLVABLE_UID_DECLARATIONS: Array = [
	{
		"uid": "uid://bbcxyx60210yg",
		"path": "res://scripts/new_script.gd",
		"note": "目标文件缺失（scenes/useless_scenes/useless_scene1.tscn，全仓无引用）",
	},
]

## 39 个无同目录蛇形孪生的项目自有 C# 文件及其归属分类。
## 每行：cs（C# 路径）、kind（分类）、gd（GDScript 等价物 / 内联宿主）。
const NO_TWIN_CS_CLASSIFICATION: Array = [
	# ----- 协议 / 接口垫片：C# 侧读取 GDScript 生产对象，等价物即被读取的生产脚本 -----
	{"cs": "core/inventory/ItemStackProtocol.cs", "kind": KIND_PROTOCOL, "gd": "res://resources/item/item_stack.gd"},
	{"cs": "resources/interaction/TerrainInstanceProtocol.cs", "kind": KIND_PROTOCOL, "gd": "res://resources/interaction/terrain_instance.gd"},
	{"cs": "core/combat/status/StatusEffectDataProtocol.cs", "kind": KIND_PROTOCOL, "gd": "res://core/combat/status/status_effect_data.gd"},
	{"cs": "core/combat/status/AttributeModifierDataProtocol.cs", "kind": KIND_PROTOCOL, "gd": "res://core/combat/status/attribute_modifier_data.gd"},
	{"cs": "resources/monster/MonsterDataProtocol.cs", "kind": KIND_PROTOCOL, "gd": "res://resources/monster/monster_data.gd"},
	{"cs": "core/combat/skills/CombatSkillDataProtocol.cs", "kind": KIND_PROTOCOL, "gd": "res://core/combat/skills/combat_skill_data.gd"},
	{"cs": "core/combat/effects/CardEffectProtocol.cs", "kind": KIND_PROTOCOL, "gd": "res://core/combat/effects/card_effect.gd"},
	{"cs": "core/interfaces/IDamageable.cs", "kind": KIND_PROTOCOL, "gd": "res://entities/components/damage_receiver_component.gd"},
	{"cs": "core/crafting/ICraftingInventory.cs", "kind": KIND_PROTOCOL, "gd": "res://entities/components/inventory_component.gd"},
	{"cs": "core/shop/IShopInventory.cs", "kind": KIND_PROTOCOL, "gd": "res://entities/components/inventory_component.gd"},
	{"cs": "core/shop/IPlayerWallet.cs", "kind": KIND_PROTOCOL, "gd": "res://core/autoloads/player_wallet.gd"},
	{"cs": "resources/interaction/WorldInteractionPorts.cs", "kind": KIND_PROTOCOL, "gd": INLINED_HOST_GD},
	# ----- 已内联进 GDScript 生产实现 -----
	{"cs": "resources/interaction/TerrainInteraction.cs", "kind": KIND_INLINED, "gd": INLINED_HOST_GD},
	{"cs": "resources/interaction/TerrainInteractionBuildContext.cs", "kind": KIND_INLINED, "gd": INLINED_HOST_GD},
	{"cs": "resources/interaction/WorldInteractionContext.cs", "kind": KIND_INLINED, "gd": INLINED_HOST_GD},
	{"cs": "core/gameflow/TerrainInteractionExecutor.cs", "kind": KIND_INLINED, "gd": INLINED_HOST_GD},
	{"cs": "core/gameflow/WorldViewVisibilityController.cs", "kind": KIND_INLINED, "gd": INLINED_HOST_GD},
	{"cs": "core/gameflow/ScreenTransitionAdapter.cs", "kind": KIND_INLINED, "gd": INLINED_HOST_GD},
	{"cs": "core/gameflow/WorldCombatScenePresenter.cs", "kind": KIND_INLINED, "gd": INLINED_HOST_GD},
	{"cs": "resources/interaction/operations/TerrainOp.cs", "kind": KIND_INLINED, "gd": INLINED_HOST_GD},
	{"cs": "resources/interaction/operations/CheckGatheringEncounterOp.cs", "kind": KIND_INLINED, "gd": INLINED_HOST_GD},
	{"cs": "resources/interaction/operations/EnterVaultOp.cs", "kind": KIND_INLINED, "gd": INLINED_HOST_GD},
	{"cs": "resources/interaction/operations/MarkHarvestedOp.cs", "kind": KIND_INLINED, "gd": INLINED_HOST_GD},
	{"cs": "resources/interaction/operations/MonsterSpawnOp.cs", "kind": KIND_INLINED, "gd": INLINED_HOST_GD},
	{"cs": "resources/interaction/operations/OpenFarmingPanelOp.cs", "kind": KIND_INLINED, "gd": INLINED_HOST_GD},
	{"cs": "resources/interaction/operations/PassTimeOp.cs", "kind": KIND_INLINED, "gd": INLINED_HOST_GD},
	{"cs": "resources/interaction/operations/RecordReusableGatheringOp.cs", "kind": KIND_INLINED, "gd": INLINED_HOST_GD},
	{"cs": "resources/interaction/operations/RemoveSourceCardOp.cs", "kind": KIND_INLINED, "gd": INLINED_HOST_GD},
	{"cs": "resources/interaction/operations/SpawnLootOp.cs", "kind": KIND_INLINED, "gd": INLINED_HOST_GD},
	# ----- 非 Resource 逻辑类 -----
	{"cs": "core/inventory/ItemStack.cs", "kind": KIND_LOGIC, "gd": "res://resources/item/item_stack.gd"},
	{"cs": "core/progression/UpgradeService.cs", "kind": KIND_LOGIC, "gd": "res://core/progression/player_progression.gd"},
	{"cs": "core/progression/PlayerDataPolicy.cs", "kind": KIND_LOGIC, "gd": "res://core/autoloads/player_wallet.gd + res://core/progression/player_progression.gd"},
	{"cs": "core/map/PassageGuardEdge.cs", "kind": KIND_LOGIC, "gd": "res://core/map/passage_guard_state.gd"},
	{"cs": "core/shop/ShopCatalog.cs", "kind": KIND_LOGIC, "gd": "res://resources/shop/shop_catalog.gd"},
	{"cs": "core/combat/skills/SkillTargetingType.cs", "kind": KIND_LOGIC, "gd": "res://scripts/generated/SkillTargetingType.gd"},
	{"cs": "core/application/EncounterMonsterScaler.cs", "kind": KIND_LOGIC, "gd": "res://core/application/encounter_manager.gd"},
	{"cs": "resources/encounters/MonsterStatMultiplier.cs", "kind": KIND_LOGIC, "gd": "res://core/application/encounter_manager.gd"},
	{"cs": "entities/components/ComponentLookup.cs", "kind": KIND_LOGIC, "gd": "res://tests/godot/test_status_component_contract.gd"},
	# ----- C# 对照测试工程 -----
	{"cs": "tests/CUSGA.Tests/Program.cs", "kind": KIND_TEST_HARNESS, "gd": ""},
]

## 分类应固定的行数，用于防止「表被静默改小」。
const KIND_ROW_COUNTS: Dictionary = {
	KIND_PROTOCOL: 12,
	KIND_INLINED: 17,
	KIND_LOGIC: 9,
	KIND_TEST_HARNESS: 1,
}

## 内联宿主必须暴露的方法签名，逐条对应被内联的旧 C# 类。
const INLINED_HOST_REQUIRED_SIGNATURES: Array[String] = [
	"func _execute_terrain_interaction(",
	"func _apply_gdscript_ops(",
	"func _apply_pass_time_op(",
	"func _apply_check_gathering_encounter_op(",
	"func _apply_monster_spawn_op(",
	"func _mark_terrain_harvested(",
	"func _set_world_view_visible(",
	"func _run_screen_transition(",
	"func _enter_combat_and_wait_for_result(",
	"func _duplicate_current_background(",
]

## 内联宿主不得再出现的旧 C# 依赖写法。
const INLINED_HOST_FORBIDDEN_LITERALS: Array[String] = [
	"preload(\"res://resources/interaction/operations/",
	"preload(\"res://core/gameflow/ScreenTransitionAdapter",
	"preload(\"res://core/gameflow/WorldCombatScenePresenter",
	"Op.new(",
]


func suite_name() -> String:
	return "final_migration_audit_contract"


# ----- 助手 -----

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


## 递归收集指定扩展名的文件；跳过隐藏目录（避免遍历 .godot 缓存）。
##
## 参数 dir_path：res:// 目录。
## 参数 extensions：扩展名数组（不含点）。
## 返回值：命中的 res:// 路径数组。
func _collect_files(dir_path: String, extensions: Array) -> Array:
	return _collect_files_skipping(dir_path, extensions, [])


## 递归收集指定扩展名的文件，并额外跳过给定目录名（构建产物等）。
##
## 参数 dir_path：res:// 目录。
## 参数 extensions：扩展名数组（不含点）。
## 参数 skip_dirs：需要跳过的目录名数组。
## 返回值：命中的 res:// 路径数组。
func _collect_files_skipping(dir_path: String, extensions: Array, skip_dirs: Array) -> Array:
	var found: Array = []
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return found
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if file_name != "." and file_name != ".." and not file_name.begins_with(".") and not skip_dirs.has(file_name):
			var full: String = dir_path + "/" + file_name
			if dir.current_is_dir():
				found.append_array(_collect_files_skipping(full, extensions, skip_dirs))
			elif extensions.has(full.get_extension()):
				found.append(full)
		file_name = dir.get_next()
	dir.list_dir_end()
	return found


## 去掉重复项，保持首次出现顺序。
##
## 参数 values：可能含重复项的数组。
## 返回值：去重后的数组。
func _unique(values: Array) -> Array:
	var out: Array = []
	for value: Variant in values:
		if not out.has(value):
			out.append(value)
	return out


## 去掉注释与字符串内容，保留标识符位置。
##
## 参数 text：GDScript 源码。
## 返回值：注释与字符串内容被移除的源码（字符串位置留一个空格，避免拼接歧义）。
func _strip_comments_and_strings(text: String) -> String:
	var out: String = ""
	var in_string: bool = false
	var quote: String = ""
	var index: int = 0
	var length: int = text.length()
	while index < length:
		var character: String = text[index]
		if in_string:
			if character == "\\" and index + 1 < length:
				index += 2
				continue
			if character == quote:
				in_string = false
			index += 1
			continue
		if character == "#":
			while index < length and text[index] != "\n":
				index += 1
			continue
		if character == "\"" or character == "'":
			in_string = true
			quote = character
			out += " "
			index += 1
			continue
		out += character
		index += 1
	return out


## 收集项目自有 C# 类型名（文件名即类型名，与本项目既有命名一致）。
##
## 返回值：去重排序后的类型名数组。
func _collect_csharp_type_names() -> Array:
	var names: Array = []
	for path: String in _collect_files_skipping("res://", [CS_EXTENSION], SKIPPED_DIR_NAMES):
		names.append(path.get_file().get_basename())
	names.sort()
	return _unique(names)


## 收集 GDScript 侧已声明的语言中立名称（class_name 与命名 enum）。
##
## 返回值：去重后的名字数组；这些名字允许出现在类型位置，因为两侧实现同名。
func _collect_gdscript_declared_names() -> Array:
	var class_regex: RegEx = RegEx.create_from_string("^class_name\\s+([A-Za-z_][A-Za-z0-9_]*)")
	var enum_regex: RegEx = RegEx.create_from_string("^enum\\s+([A-Za-z_][A-Za-z0-9_]*)")
	var names: Array = []
	for path: String in _collect_files_skipping("res://", ["gd"], SKIPPED_DIR_NAMES):
		for line: String in _read(path).split("\n"):
			var trimmed: String = line.strip_edges()
			for regex: RegEx in [class_regex, enum_regex]:
				var found: RegExMatch = regex.search(trimmed)
				if found != null:
					names.append(found.get_string(1))
	return _unique(names)


## 按模板编译出「名字集合」正则数组。
##
## 参数 names：参与匹配的名字数组。
## 参数 templates：含一个 %s 占位符的正则模板数组。
## 返回值：编译好的 RegEx 数组。
func _build_name_regexes(names: Array, templates: Array) -> Array:
	var regexes: Array = []
	if names.is_empty():
		return regexes
	var alternation: String = ""
	for name: String in names:
		if not alternation.is_empty():
			alternation += "|"
		alternation += name
	for template: String in templates:
		regexes.append(RegEx.create_from_string(template % alternation))
	return regexes


## 在若干 GDScript 根目录上执行「名字集合 × 模板」扫描。
##
## 参数 roots：res:// 根目录数组。
## 参数 names：参与匹配的名字数组。
## 参数 templates：正则模板数组。
## 返回值：命中描述数组（路径 → 命中片段）。
func _scan_with_patterns(roots: Array, names: Array, templates: Array) -> Array:
	var hits: Array = []
	var regexes: Array = _build_name_regexes(names, templates)
	if regexes.is_empty():
		return hits
	for root: String in roots:
		for path: String in _collect_files_skipping(root, ["gd"], SKIPPED_DIR_NAMES):
			var stripped: String = _strip_comments_and_strings(_read(path))
			for regex: RegEx in regexes:
				var found: RegExMatch = regex.search(stripped)
				if found != null:
					hits.append("%s → %s" % [path, found.get_string(0).strip_edges()])
					break
	hits.sort()
	return hits


## 扫描若干 GDScript 根目录，返回去注释后仍包含关键字的文件。
##
## 参数 roots：res:// 根目录数组。
## 参数 needle：目标子串。
## 返回值：命中的 res:// 路径数组（按路径排序，便于与固定清单比较）。
func _scan_gd_roots_containing(roots: Array, needle: String) -> Array:
	var hits: Array = []
	for root: String in roots:
		for path: String in _collect_files(root, ["gd"]):
			if _strip_gd_comments(_read(path)).contains(needle):
				hits.append(path)
	hits.sort()
	return hits


## 扫描若干 GDScript 根目录，返回去注释后仍包含 `.cs` 字面量的文件。
##
## 参数 roots：res:// 根目录数组。
## 返回值：命中的 res:// 路径数组。
func _scan_gd_roots(roots: Array) -> Array:
	return _scan_gd_roots_containing(roots, LEGACY_PATH_NEEDLE)


## 扫描资产文件（场景 / 资源 / 项目设置），返回包含 `.cs` 字面量的文件。
##
## 参数 roots：res:// 根目录数组。
## 返回值：命中的 res:// 路径数组。
func _scan_asset_roots(roots: Array) -> Array:
	var hits: Array = []
	for root: String in roots:
		for path: String in _collect_files(root, ASSET_EXTENSIONS):
			if _read(path).contains(LEGACY_PATH_NEEDLE):
				hits.append(path)
	return hits


## 建立 uid:// -> res:// 路径索引（.uid 旁车 + 场景 / 资源头部的 uid 声明）。
##
## 返回值：uid 字符串到 res:// 路径的字典。
func _build_uid_index() -> Dictionary:
	var index: Dictionary = {}
	var all_files: Array = _collect_files("res://", ["uid", "tscn", "tres", "res", "gd"])
	for path: String in all_files:
		var text: String = _read(path)
		if path.get_extension() == "uid":
			var bare: String = text.strip_edges()
			if bare.begins_with("uid://"):
				index[bare] = path.trim_suffix(".uid")
			continue
		var marker: int = text.find("uid://")
		# 只认文件头部（场景 / 资源首行）的 uid 声明，避免命中正文里的 uid 字符串。
		if marker >= 0 and marker < 256:
			var tail: String = text.substr(marker + 6)
			var end_index: int = tail.find("\"")
			var newline_index: int = tail.find("\n")
			if end_index == -1:
				end_index = tail.length()
			if newline_index != -1 and newline_index < end_index:
				continue
			index["uid://" + tail.substr(0, end_index)] = path
	return index


## 逐行解析 project.godot 的 [autoload] 段。
##
## 返回值：Autoload 名称到目标字符串（*uid://… 或 *res://…）的字典。
func _read_autoload_entries() -> Dictionary:
	var entries: Dictionary = {}
	var in_section: bool = false
	for line: String in _read("res://project.godot").split("\n"):
		var trimmed: String = line.strip_edges()
		if trimmed.begins_with("["):
			in_section = trimmed == "[autoload]"
			continue
		if not in_section or trimmed.is_empty() or trimmed.begins_with(";"):
			continue
		var separator: int = trimmed.find("=")
		if separator <= 0:
			continue
		# project.godot 的值形如 "\"*uid://xxx\""：先剥引号，再剥 Autoload 的启用星号前缀。
		var raw_target: String = trimmed.substr(separator + 1).strip_edges()
		raw_target = raw_target.trim_prefix("\"").trim_suffix("\"")
		entries[trimmed.substr(0, separator)] = raw_target.trim_prefix("*")
	return entries


## 取出 `prefix` 之后到下一个双引号为止的属性值。
##
## 参数 text：待解析的单行文本。
## 参数 prefix：形如 ` uid="` 的属性前缀。
## 返回值：属性值；找不到前缀或闭合引号时返回空字符串。
func _extract_quoted_attribute(text: String, prefix: String) -> String:
	var start: int = text.find(prefix)
	if start < 0:
		return ""
	start += prefix.length()
	var end: int = text.find('"', start)
	if end < 0:
		return ""
	return text.substr(start, end - start)


## 单文件扫描：把 `metadata/_custom_type_script` 与同一块内实际挂载的脚本 uid 做对比。
##
## 参数 lines：文件按行切分后的内容。
## 参数 ext_uids：该文件 `[ext_resource]` 的 id -> uid 映射。
## 返回值：{"blocks": int, "mismatches": Array[String], "uids": Array[String]}。
func _scan_custom_type_script_blocks(lines: PackedStringArray, ext_uids: Dictionary) -> Dictionary:
	var blocks: int = 0
	var mismatches: Array[String] = []
	var uids: Array[String] = []
	var attached: String = ""
	var declared: String = ""
	for raw_line: String in lines:
		var line: String = raw_line.strip_edges()
		# 每个 `[node …]` / `[sub_resource …]` 行开启新块，因此遇到块头时先结算上一块。
		if line.begins_with("["):
			if not declared.is_empty():
				blocks += 1
				if declared != attached:
					mismatches.append("挂载 %s / 元数据 %s" % [attached, declared])
			attached = ""
			declared = ""
			continue
		if line.begins_with(SCRIPT_ASSIGNMENT_PREFIX):
			var rest: String = line.substr(SCRIPT_ASSIGNMENT_PREFIX.length())
			var quote_end: int = rest.find('"')
			if quote_end > 0:
				var reference_id: String = rest.substr(0, quote_end)
				attached = String(ext_uids.get(reference_id, "<未知引用 %s>" % reference_id))
			continue
		if line.begins_with(CUSTOM_TYPE_SCRIPT_PREFIX):
			declared = _extract_quoted_attribute(line, CUSTOM_TYPE_SCRIPT_PREFIX)
			uids.append(declared)
	if not declared.is_empty():
		blocks += 1
		if declared != attached:
			mismatches.append("挂载 %s / 元数据 %s" % [attached, declared])
	return {"blocks": blocks, "mismatches": mismatches, "uids": uids}


# ----- 分类表契约 -----

## 分类表必须自洽：39 行、无重复、分类合法、非测试行必须有等价物。
##
## @return 无返回值。
func test_classification_table_is_complete_and_consistent() -> void:
	assert_eq(NO_TWIN_CS_CLASSIFICATION.size(), 39, "无孪生 C# 分类表必须恰好覆盖 39 个文件。")
	var seen: Dictionary = {}
	var invalid_kinds: Array[String] = []
	var missing_equivalent: Array[String] = []
	for row: Dictionary in NO_TWIN_CS_CLASSIFICATION:
		var cs_path: String = row.get("cs", "")
		var kind: String = row.get("kind", "")
		var equivalent: String = row.get("gd", "")
		assert_true(cs_path.ends_with(".cs"), "分类表的 cs 列必须是 .cs 路径：%s" % cs_path)
		assert_true(not seen.has(cs_path), "分类表出现重复条目：%s" % cs_path)
		seen[cs_path] = true
		if not ALLOWED_KINDS.has(kind):
			invalid_kinds.append("%s -> %s" % [cs_path, kind])
		if kind != KIND_TEST_HARNESS and equivalent.is_empty():
			missing_equivalent.append(cs_path)
	assert_eq(invalid_kinds, [], "出现未登记的分类：%s" % str(invalid_kinds))
	assert_eq(missing_equivalent, [], "以下非测试行缺少 GDScript 等价物：%s" % str(missing_equivalent))


## 分类行数必须与显式登记的期望一致，防止「表被静默改小」导致覆盖悄悄减少。
##
## @return 无返回值。
func test_classification_counts_are_pinned() -> void:
	var counts: Dictionary = {}
	for row: Dictionary in NO_TWIN_CS_CLASSIFICATION:
		var kind: String = row.get("kind", "")
		counts[kind] = int(counts.get(kind, 0)) + 1
	var total_pinned: int = 0
	for kind: String in KIND_ROW_COUNTS.keys():
		assert_eq(int(counts.get(kind, 0)), int(KIND_ROW_COUNTS[kind]), "分类 %s 的行数被改动。" % kind)
		total_pinned += int(KIND_ROW_COUNTS[kind])
	assert_eq(total_pinned, 39, "固定行数之和必须等于 39。")
	assert_eq(counts.size(), KIND_ROW_COUNTS.size(), "出现了登记外的新分类：%s" % str(counts.keys()))


## 分类表 39 个 C# 文件必须与当前阶段一致：迁移期必须全保留，退役期必须全清零。
##
## 阶段判据是全局单点（`CUSGA.csproj` 是否存在），不是逐文件探测：因此「只删了一半」
## 在两种模式下都会红 —— 迁移期防误删，退役期防「删了一部分就宣称完成」。
##
## @return 无返回值。
func test_classified_csharp_files_follow_phase_contract() -> void:
	var existing: Array[String] = []
	var missing: Array[String] = []
	for row: Dictionary in NO_TWIN_CS_CLASSIFICATION:
		var cs_path: String = "res://" + String(row.get("cs", ""))
		if FileAccess.file_exists(cs_path):
			existing.append(cs_path)
		else:
			missing.append(cs_path)
	if FileAccess.file_exists(RETIREMENT_PHASE_MARKER):
		assert_eq(missing, [], "迁移期不得删除分类表里的 C# 文件：%s" % str(missing))
		for host: String in MIGRATION_HOST_FILES:
			assert_true(FileAccess.file_exists(host), "迁移期不得删除 C# 工程文件：%s" % host)
		return
	assert_eq(existing, [], "C# 退役后分类表里仍留有 C# 文件：%s" % str(existing))
	for host: String in MIGRATION_HOST_FILES:
		assert_false(FileAccess.file_exists(host), "C# 退役后工程文件必须一并删除：%s" % host)


## 每个非测试行登记的 GDScript 等价物 / 内联宿主必须真实存在且是 GDScript。
##
## @return 无返回值。
func test_equivalents_exist_and_are_gdscript() -> void:
	var problems: Array[String] = []
	for row: Dictionary in NO_TWIN_CS_CLASSIFICATION:
		if String(row.get("kind", "")) == KIND_TEST_HARNESS:
			continue
		for equivalent: String in String(row.get("gd", "")).split("+"):
			var path: String = equivalent.strip_edges()
			if not path.ends_with(".gd"):
				problems.append("%s -> 非 GDScript 等价物 %s" % [String(row.get("cs", "")), path])
			elif not FileAccess.file_exists(path):
				problems.append("%s -> 等价物缺失 %s" % [String(row.get("cs", "")), path])
	assert_eq(problems, [], "等价物登记异常：%s" % str(problems))


# ----- 内联宿主契约 -----

## 内联宿主必须暴露逐条对应旧 C# 类的方法，且不得再 preload 或实例化旧 C# 辅助类型。
##
## @return 无返回值。
func test_inlined_host_exposes_named_replacements() -> void:
	var host_text: String = _strip_gd_comments(_read(INLINED_HOST_GD))
	var missing: Array[String] = []
	for signature: String in INLINED_HOST_REQUIRED_SIGNATURES:
		if not host_text.contains(signature):
			missing.append(signature)
	assert_eq(missing, [], "内联宿主缺少以下等价实现：%s" % str(missing))
	for forbidden: String in INLINED_HOST_FORBIDDEN_LITERALS:
		assert_true(not host_text.contains(forbidden), "内联宿主不得再出现旧 C# 依赖写法：%s" % forbidden)


# ----- 三层零 C# 引用 -----

## 资产层（.tscn / .tres / .res / project.godot）不得引用任何 `.cs`。
##
## @return 无返回值。
func test_assets_reference_no_csharp() -> void:
	var hits: Array = _scan_asset_roots(["res://core", "res://entities", "res://resources", "res://scenes", "res://scripts", "res://"])
	assert_eq(hits, [], "资产文件仍引用 C# 脚本：%s" % str(hits))
	# 自证：同一扫描逻辑必须能在测试目录扫出已知的 `.cs` 引用，否则「零命中」无意义。
	var probe: Array = _scan_gd_roots(["res://tests"])
	assert_gt(probe.size(), 0, "扫描器必须能在测试目录扫出已知的 .cs 引用（自证）。")


## 生产 GDScript（core / entities / resources / scripts）不得出现 `.cs` 字面量。
##
## @return 无返回值。
func test_production_gdscript_references_no_csharp() -> void:
	var hits: Array = _scan_gd_roots(PRODUCTION_ROOTS)
	assert_eq(hits, [], "生产 GDScript 仍出现 C# 脚本路径：%s" % str(hits))
	var production_files: Array = []
	for root: String in PRODUCTION_ROOTS:
		production_files.append_array(_collect_files(root, ["gd"]))
	assert_gt(production_files.size(), MIN_PRODUCTION_GD_COUNT, "生产 GDScript 数量异常，扫描可能没有产出。")


## 全部 Autoload 必须指向 GDScript 或场景，不得指向 C#；uid 形式必须能解析出真实目标。
##
## @return 无返回值。
func test_autoloads_are_not_csharp() -> void:
	var entries: Dictionary = _read_autoload_entries()
	assert_gt(entries.size(), MIN_AUTOLOAD_COUNT - 1, "Autoload 段解析结果异常，可能没有产出。")
	var uid_index: Dictionary = _build_uid_index()
	var problems: Array[String] = []
	for name: String in entries.keys():
		var target: String = String(entries[name])
		if target.contains(LEGACY_PATH_NEEDLE):
			problems.append("%s -> %s（指向 C#）" % [name, target])
			continue
		if target.begins_with("uid://"):
			if not uid_index.has(target):
				problems.append("%s -> %s（uid 无法解析）" % [name, target])
				continue
			var resolved: String = String(uid_index[target])
			if not (resolved.ends_with(".gd") or resolved.ends_with(".tscn")):
				problems.append("%s -> %s（解析为 %s）" % [name, target, resolved])
			continue
		if not (target.ends_with(".gd") or target.ends_with(".tscn")):
			problems.append("%s -> %s（非 GDScript / 场景目标）" % [name, target])
	assert_eq(problems, [], "Autoload 仍有 C# 依赖或无法解析：%s" % str(problems))


## 生产 GDScript 里不得再残留任何语言身份判定边界。
##
## 背景：物品链 / 地形链 / 拖拽载荷三处按语言身份的判定早在早期批次改为协议判定；
## 最后一处 GameplayPort 的双路分发（旧 C# 强类型信号 vs GDScript 通用 Node 信号）已随
## C# 物理退役一起删除。这里把「零语言身份判定」钉成不变量：既防止新增语言判定，
## 也防止有人再引入依赖 C# 残留的分支。
##
## @return 无返回值。
func test_no_language_boundary_remains() -> void:
	var owners: Array = _scan_gd_roots_containing(PRODUCTION_ROOTS, LANGUAGE_BOUNDARY_NEEDLE)
	assert_eq(owners, [], "C# 退役后生产 GDScript 不得再出现语言身份判定边界：%s" % str(owners))
	var extension_owners: Array = _scan_gd_roots_containing(PRODUCTION_ROOTS, LANGUAGE_EXTENSION_CHECK_LITERAL)
	assert_eq(extension_owners, [], "C# 退役后生产 GDScript 不得再按脚本扩展名判定语言：%s" % str(extension_owners))
	# 自证：同一扫描逻辑必须能在测试目录扫出已知命中，否则「零命中」无意义。
	var probe: Array = _scan_gd_roots_containing(["res://tests"], LANGUAGE_BOUNDARY_NEEDLE)
	assert_gt(probe.size(), 0, "扫描器必须能在测试目录扫出已知的语言判定字面量（自证）。")


## 生产 GDScript 不得把 C# 类型名当作类型使用（is / as / new / 类型注解）。
##
## 这类写法在 C# 垫片退役后会直接解析失败，所以必须为零命中：C# 类型仍可被读取、
## 可被协议判定，但不能再被当作「类型」出现在生产脚本的类型位置上。
##
## @return 无返回值。
func test_production_gdscript_uses_no_csharp_type_identity() -> void:
	var cs_names: Array = _collect_csharp_type_names()
	## C# 全量退役后没有 C# 类型名可对照：本用例的对照语义消失，记跳过。
	if cs_names.is_empty():
		skip(CS_OPTIONAL.SKIP_REASON)
		return
	var gd_names: Array = _collect_gdscript_declared_names()
	assert_gt(cs_names.size(), 150, "C# 类型名清单数量异常，扫描可能没有产出。")
	assert_gt(gd_names.size(), 20, "GDScript 声明名清单数量异常，扫描可能没有产出。")
	var exclusive: Array = []
	for name: String in cs_names:
		if not gd_names.has(name):
			exclusive.append(name)
	assert_gt(exclusive.size(), 100, "C# 独占类型名数量异常：%d" % exclusive.size())
	assert_true(exclusive.has("DamageEffect"), "DamageEffect 必须被登记为 C# 独占类型名。")
	assert_true(
		exclusive.has("ReusableGatheringInteraction"),
		"ReusableGatheringInteraction 必须被登记为 C# 独占类型名。"
	)

	var scan_roots: Array = []
	scan_roots.append_array(PRODUCTION_ROOTS)
	scan_roots.append("res://scenes")
	var identity_hits: Array = _scan_with_patterns(scan_roots, exclusive, TYPE_POSITION_PATTERNS)
	assert_eq(identity_hits, [], "生产 GDScript 仍把 C# 类型名当作类型使用：%s" % str(identity_hits))

	# 自证一：同一套「名字表 + 文件管线」在任意标识符模式下必须能命中，证明扫描确实读到了内容。
	var any_hits: Array = _scan_with_patterns(scan_roots, exclusive, ANY_IDENTIFIER_PATTERNS)
	assert_gt(any_hits.size(), 0, "扫描管线没有读到任何标识符，零命中不可信。")

	# 自证二：类型位置正则必须能在合成样本上命中 is / as / new / 注解四类写法。
	var probe_regexes: Array = _build_name_regexes(["MonsterData", "DamageEffect"], TYPE_POSITION_PATTERNS)
	var probe_text: String = _strip_comments_and_strings(
		"var a: MonsterData = DamageEffect.new()\nif x is MonsterData:\nvar b = y as MonsterData\nfunc f(p: MonsterData) -> MonsterData:\n"
	)
	var probe_hits: int = 0
	for regex: RegEx in probe_regexes:
		if regex.search(probe_text) != null:
			probe_hits += 1
	assert_gt(probe_hits, 3, "类型位置正则必须能在合成样本上命中四类写法（实际命中 %d 类）。" % probe_hits)

	# 自证三：去字符串必须真的生效，否则 C# 路径字符串会被误判成类型依赖。
	var string_only: String = _strip_comments_and_strings(
		"var p: String = \"res://core/combat/effects/DamageEffect.cs\"\n"
	)
	assert_true(not string_only.contains("DamageEffect"), "去字符串必须移除字符串字面量内容。")


# ----- 序列化元数据契约（自定义类型脚本 uid / uid 可解析性） -----

## 每个 `ext_resource` 声明的 `uid://` 必须能被 ResourceUID 解析。
##
## 背景：`uid://` 只是资源路径的缓存键，权威判据是运行时 `ResourceUID` 能不能解析它。
## 声明了 uid 但 ResourceUID 不认识时，Godot 会打 warning
## 「ext_resource, invalid UID ... using text path instead」并按 path 加载：行为不变，
## 但日志被噪声污染，且会掩盖真正的资源加载失败。本用例把「声明了 uid 就必须可解析」
## 钉成不变量，唯一例外是已登记的目标文件缺失项。
##
## @return 无返回值。
func test_declared_uids_are_resolvable() -> void:
	var allowed: Array = []
	for row: Dictionary in KNOWN_UNRESOLVABLE_UID_DECLARATIONS:
		allowed.append(String(row.get("uid", "")))
	var checked: int = 0
	var broken: Array[String] = []
	for path: String in _collect_files("res://", ["tscn", "tres"]):
		for raw_line: String in _read(path).split("\n"):
			var line: String = raw_line.strip_edges()
			if not line.begins_with("[ext_resource"):
				continue
			var uid: String = _extract_quoted_attribute(line, EXT_RESOURCE_UID_PREFIX)
			if uid.is_empty() or allowed.has(uid):
				continue
			checked += 1
			if ResourceUID.has_id(ResourceUID.text_to_id(uid)):
				continue
			broken.append("%s：%s" % [path, uid])
	assert_gt(checked, 1000, "扫描到的 uid 声明数量异常：%d" % checked)
	assert_eq(broken, [], "存在 ResourceUID 无法解析的 uid 声明：%s" % str(broken))
	# 自证：ResourceUID 必须能解析一个已知有效的 uid，否则上面的零命中不可信。
	assert_true(
		ResourceUID.has_id(ResourceUID.text_to_id("uid://bu272src84v8y")),
		"ResourceUID 无法解析已知有效的 uid（card_effect.gd），扫描前提不成立。"
	)

## `metadata/_custom_type_script` 必须与同一节点 / 子资源实际挂载的脚本 uid 一致。
##
## 背景：Godot 在序列化「挂载脚本不是全局类」的节点 / 子资源时会写
## `metadata/_custom_type_script`（该脚本的 uid）。C# → GDScript 迁移把挂载脚本换成 `.gd`
## 之后，这个元数据若仍指向旧 `.cs` 的 uid，就会在 C# 垫片退役后变成悬空引用。
## 因此本用例把两件事钉成不变量：① 元数据 uid 必须等于同块内 `script = ExtResource(...)`
## 指向的 uid；② 元数据 uid 必须能解析到 `.gd` / `.tscn`（即不是 C# 旁车 uid）。
##
## @return 无返回值。
func test_custom_type_script_metadata_matches_attached_script() -> void:
	var uid_index: Dictionary = _build_uid_index()
	var scanned_blocks: int = 0
	var mismatches: Array[String] = []
	var unresolved: Array[String] = []
	for path: String in _collect_files("res://", ["tscn", "tres"]):
		var lines: PackedStringArray = _read(path).split("\n")
		var ext_uids: Dictionary = {}
		for raw_line: String in lines:
			var line: String = raw_line.strip_edges()
			if not line.begins_with("[ext_resource"):
				continue
			var uid: String = _extract_quoted_attribute(line, EXT_RESOURCE_UID_PREFIX)
			var reference_id: String = _extract_quoted_attribute(line, EXT_RESOURCE_ID_PREFIX)
			if not uid.is_empty() and not reference_id.is_empty():
				ext_uids[reference_id] = uid
		var result: Dictionary = _scan_custom_type_script_blocks(lines, ext_uids)
		scanned_blocks += int(result["blocks"])
		for entry: String in result["mismatches"]:
			mismatches.append("%s：%s" % [path, entry])
		for uid: String in result["uids"]:
			var resolved: String = "<未登记>"
			if uid_index.has(uid):
				resolved = String(uid_index[uid])
			if not (resolved.ends_with(".gd") or resolved.ends_with(".tscn")):
				unresolved.append("%s -> %s（解析为 %s）" % [path, uid, resolved])
	assert_gt(scanned_blocks, MIN_CUSTOM_TYPE_SCRIPT_BLOCKS, "扫描到的自定义类型脚本块数异常：%d" % scanned_blocks)
	assert_eq(mismatches, [], "自定义类型脚本元数据与实际挂载脚本不一致：%s" % str(mismatches))
	assert_eq(unresolved, [], "自定义类型脚本元数据未解析到 GDScript：%s" % str(unresolved))

	# 自证：同一段扫描逻辑必须能在合成样本上报出「1 块 / 1 处不一致 / 1 个 uid」，
	# 否则上面的零不一致无法与「扫描器坏掉」区分。
	var probe_lines: PackedStringArray = PackedStringArray([
		"[node name=\"A\" type=\"Node\"]",
		"script = ExtResource(\"1_a\")",
		"metadata/_custom_type_script = \"uid://csharp_uid\"",
	])
	var probe: Dictionary = _scan_custom_type_script_blocks(probe_lines, {"1_a": "uid://gdscript_uid"})
	assert_eq(int(probe["blocks"]), 1, "自证样本必须被识别为 1 个块。")
	assert_eq((probe["mismatches"] as Array).size(), 1, "自证样本必须被识别出 1 处不一致。")
	assert_eq((probe["uids"] as Array).size(), 1, "自证样本必须被识别出 1 个元数据 uid。")


## `.uid` 旁车必须与运行时 ResourceUID 表自洽：只要旁车里的 uid 已被登记，它就必须指向旁车所属的文件本身。
##
## 背景：`.tscn` / `.tres` 里的 `uid=` 与 `<file>.uid` 旁车是两处独立声明，谁都不保证最新。两侧不一致时，
## 加载场景会把「场景声明的 uid」重新登记到脚本路径上，把旁车值挤成悬空值，于是同时触发
## ① 契约测试「主场景必须引用生产脚本的同一 UID」② 迁移审计「uid 无法解析」两条红灯（本批实测）。
## 本用例把「旁车值一旦被登记就必须自指」钉成不变量；尚未被编辑器扫描登记的旁车单独计数，不参与判定。
##
## @return 无返回值。
func test_uid_sidecars_match_their_owner_path() -> void:
	var checked: int = 0
	var registered: int = 0
	var conflicts: Array[String] = []
	for path: String in _collect_files_skipping("res://", ["uid"], SKIPPED_DIR_NAMES):
		checked += 1
		var text: String = _read(path).strip_edges()
		# `_collect_files_skipping` 拼接根目录时会产出 `res:///core/...`，比对前归一化为 `res://`。
		var owner: String = path.trim_suffix(".uid").replace(":///", "://")
		if not text.begins_with("uid://"):
			conflicts.append("%s：旁车内容不是 uid 文本（%s）" % [path, text])
			continue
		var uid: int = ResourceUID.text_to_id(text)
		if not ResourceUID.has_id(uid):
			continue
		registered += 1
		var resolved: String = ResourceUID.get_id_path(uid)
		if resolved != owner:
			conflicts.append("%s：%s 被登记为 %s" % [path, text, resolved])
	assert_gt(checked, 300, "扫描到的 uid 旁车数量异常：%d" % checked)
	assert_gt(registered, 100, "已登记的 uid 旁车数量异常：%d" % registered)
	assert_eq(conflicts, [], "uid 旁车与 ResourceUID 表冲突：%s" % str(conflicts))
