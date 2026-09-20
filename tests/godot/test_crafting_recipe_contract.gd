@tool
extends McpTestSuite

## Crafting / 物品链边界契约套件（C# 垫片 ↔ GDScript 生产实现）。
##
## 现状：生产侧早已全量切到 GDScript（player.tscn 用 crafting_component.gd + crafting_recipe.gd +
## recipe_book_data.gd，Main.tscn / crafting_ui.tscn 用 crafting_ui.gd）；旧 C# 的
## CraftingRecipe / CraftingIngredient / RecipeBookData / CraftingComponent / CraftingService / CraftingUI
## 保留为兼容垫片，只被未迁移的 C# 代码与 C# 测试工程消费。
## 本套件锁定三件事：
## 1）两侧序列化字段名与默认值一致（改字段名会同时破坏 .tres 反序列化）；
## 2）同名旧资产（`*_recipe.tres`）与生产资产（`*_recipe_gd.tres`）的配方数据逐条相等；
## 3）生产场景、生产资产与生产 GDScript 一律不得引用 crafting 相关的 .cs 脚本。

const RECIPE_CS: String = "res://resources/recipe/CraftingRecipe.cs"
const INGREDIENT_CS: String = "res://resources/recipe/CraftingIngredient.cs"
const RECIPE_BOOK_CS: String = "res://resources/recipe/RecipeBookData.cs"
const RECIPE_GD: String = "res://resources/recipe/crafting_recipe.gd"
const INGREDIENT_GD: String = "res://resources/recipe/crafting_ingredient.gd"
const RECIPE_BOOK_GD: String = "res://resources/recipe/recipe_book_data.gd"

## 3 条字段契约：[名称, C# 路径, GDScript 路径, [字段名, ...], [C# 必须存在的片段, ...]]。
const FIELD_ROWS: Array = [
	[
		"CraftingRecipe",
		RECIPE_CS,
		RECIPE_GD,
		["RecipeName", "Inputs", "OutputItem", "OutputAmount"],
		[
			"[GlobalClass]",
			"public partial class CraftingRecipe : Resource",
			"[Export] public string RecipeName { get; set; }",
			"[Export] public Array<CraftingIngredient> Inputs { get; set; } = [];",
			"[Export] public ItemData OutputItem { get; set; }",
			"[Export] public int OutputAmount { get; set; } = 1;",
		],
	],
	[
		"CraftingIngredient",
		INGREDIENT_CS,
		INGREDIENT_GD,
		["RequiredItem", "Amount"],
		[
			"[GlobalClass]",
			"public partial class CraftingIngredient : Resource",
			"[Export] public ItemData RequiredItem { get; set; }",
			"[Export] public int Amount { get; set; } = 1;",
		],
	],
	[
		"RecipeBookData",
		RECIPE_BOOK_CS,
		RECIPE_BOOK_GD,
		["Recipes"],
		[
			"[GlobalClass]",
			"public partial class RecipeBookData : Resource",
			"[Export] public Array<CraftingRecipe> Recipes { get; set; } = [];",
		],
	],
]

## 旧路径配方资产与其 GDScript 生产资产；两侧都必须使用 GDScript 脚本且数据逐条相等。
const RECIPE_PAIRS: Array = [
	["res://resources/recipe/res/torch_recipe.tres", "res://resources/recipe/res/torch_recipe_gd.tres"],
	["res://resources/recipe/res/stone_axe_recipe.tres", "res://resources/recipe/res/stone_axe_recipe_gd.tres"],
]

## 允许继续引用 .cs 的生产资产；两个旧配方资产已切换到 GDScript 脚本，因此这里为空。
## 迁移期若出现新的例外，必须在此显式登记并写明理由。
const LEGACY_ASSET_ALLOWLIST: Array = []

## crafting 相关的旧 C# 脚本路径；C# 物理退役后，C# 侧对照断言经 CS_OPTIONAL 自动退场
## （见 tests/godot/csharp_optional.gd），GDScript 侧字段与资产断言照跑。
const LEGACY_CS_PATHS: Array = [
	"resources/recipe/CraftingRecipe.cs",
	"resources/recipe/CraftingIngredient.cs",
	"resources/recipe/RecipeBookData.cs",
	"entities/components/CraftingComponent.cs",
	"core/crafting/CraftingService.cs",
	"core/ui/crafting/CraftingUI.cs",
]

## 生产根目录（不含 tests）。
const PRODUCTION_ROOTS: Array = ["res://core", "res://entities", "res://resources", "res://scripts", "res://scenes"]

## 迁移期 C# 可选助手：C# 退役后 C# 对照断言自动退场，GDScript 侧断言照跑。
## 说明见 tests/godot/csharp_optional.gd。
const CS_OPTIONAL := preload("res://tests/godot/csharp_optional.gd")


func suite_name() -> String:
	return "crafting_recipe_contract"


# ----- 解析与扫描助手 -----

## 读取文本文件内容。
##
## 参数 path：res:// 路径。
## 返回值：文件正文；读取失败时返回空字符串。
func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
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


## 解析 C# `[Export] public TYPE NAME { get; set; }` 的字段名顺序。
##
## 参数 text：C# 源码。
## 返回值：按源码顺序排列的字段名数组。
func _csharp_export_names(text: String) -> Array:
	var out: Array = []
	var marker: String = "[Export] public "
	for line: String in text.split("\n"):
		var trimmed: String = line.strip_edges()
		if not trimmed.begins_with(marker):
			continue
		var rest: String = trimmed.substr(marker.length())
		var space_index: int = rest.find(" ")
		if space_index == -1:
			continue
		var after_type: String = rest.substr(space_index + 1)
		out.append(after_type.split(" ")[0])
	return out


## 解析 GDScript `@export ... var NAME: TYPE` 的字段名顺序。
##
## 参数 text：GDScript 源码。
## 返回值：按源码顺序排列的字段名数组。
func _gd_export_names(text: String) -> Array:
	var out: Array = []
	for line: String in _strip_gd_comments(text).split("\n"):
		var trimmed: String = line.strip_edges()
		if not trimmed.begins_with("@export"):
			continue
		var var_index: int = trimmed.find("var ")
		if var_index == -1:
			continue
		var rest: String = trimmed.substr(var_index + 4)
		var name_end: int = rest.find(":")
		if name_end == -1:
			continue
		out.append(rest.substr(0, name_end))
	return out


## 递归扫描指定扩展名的文件里是否出现目标文本。
##
## 参数 directory：起始目录。
## 参数 needle：目标文本；空字符串表示「列出全部匹配扩展名的文件」（Godot 的 String.find("") 返回 -1）。
## 参数 extensions：扩展名白名单（不含点）。
## 参数 code_only：为真时先去掉 GDScript 注释再匹配。
## 返回值：命中的文件路径数组。
func _scan(directory: String, needle: String, extensions: Array, code_only: bool = false) -> Array:
	var hits: Array = []
	var dir: DirAccess = DirAccess.open(directory)
	if dir == null:
		return hits
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		var full: String = directory.path_join(entry)
		if dir.current_is_dir():
			if not entry.begins_with(".") and entry != "addons" and entry != "obj":
				hits.append_array(_scan(full, needle, extensions, code_only))
		elif extensions.has(entry.get_extension()):
			var text: String = FileAccess.get_file_as_string(full)
			if code_only:
				text = _strip_gd_comments(text)
			if needle == "" or text.find(needle) != -1:
				hits.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
	return hits


## 把配方资源压成可比较的快照（名称、产出、材料顺序与材料条目字段）。
##
## 参数 recipe：配方资源。
## 返回值：字段与顺序都稳定的字典；任一字段缺失时写入 null 以外不会崩溃。
func _recipe_snapshot(recipe: Resource) -> Dictionary:
	var inputs: Array = []
	var raw_inputs: Variant = recipe.get("Inputs")
	if raw_inputs is Array:
		for entry in raw_inputs:
			if entry == null or not (entry is Resource):
				inputs.append({"path": "", "amount": null})
				continue
			var item: Resource = entry.get("RequiredItem")
			inputs.append({
				"path": item.resource_path if item != null else "",
				"amount": entry.get("Amount"),
			})
	var output: Resource = recipe.get("OutputItem")
	return {
		"name": recipe.get("RecipeName"),
		"output_amount": recipe.get("OutputAmount"),
		"output_path": output.resource_path if output != null else "",
		"inputs": inputs,
	}


# ----- 字段契约 -----

## 两侧字段名与默认值必须一致，且 C# 垫片的导出面完整。
func test_field_parity_between_csharp_and_gdscript() -> void:
	for row: Array in FIELD_ROWS:
		var label: String = row[0]
		var cs_text: String = CS_OPTIONAL.read(row[1])
		var gd_text: String = _read(row[2])
		assert_true(ResourceLoader.exists(row[2]), "%s 的 GDScript 生产脚本必须存在。" % label)
		assert_eq(_gd_export_names(gd_text), row[3], "%s 的 GDScript 导出字段必须与旧 C# 同名同序。" % label)
		# C# 对照部分：垫片退役后整段退场，上面的 GDScript 断言仍照跑。
		if not cs_text.is_empty():
			assert_true(ResourceLoader.exists(row[1]), "%s 的旧 C# 垫片必须保留。" % label)
			assert_eq(_csharp_export_names(cs_text), row[3], "%s 的 C# 导出字段必须保持原顺序。" % label)
			for needle: String in row[4]:
				assert_true(cs_text.contains(needle), "%s 的 C# 垫片必须保留：%s" % [label, needle])
	var ingredient_defaults: Resource = (load(INGREDIENT_GD) as GDScript).new()
	assert_eq(ingredient_defaults.get("Amount"), 1, "材料数量默认值必须沿用旧 C# 的 1。")
	assert_eq(ingredient_defaults.get("RequiredItem"), null, "材料物品默认必须为空。")
	var recipe_defaults: Resource = (load(RECIPE_GD) as GDScript).new()
	assert_eq(recipe_defaults.get("RecipeName"), "", "配方名默认必须为空字符串。")
	assert_eq(recipe_defaults.get("OutputAmount"), 1, "配方产出数量默认必须为 1。")
	assert_eq(recipe_defaults.get("OutputItem"), null, "配方产出物品默认必须为空。")
	assert_eq((recipe_defaults.get("Inputs") as Array).size(), 0, "配方材料默认必须为空数组。")
	var book_defaults: Resource = (load(RECIPE_BOOK_GD) as GDScript).new()
	assert_eq((book_defaults.get("Recipes") as Array).size(), 0, "配方书默认必须为空数组。")


# ----- 资产数据一致性 -----

## 旧路径配方资产与其 GDScript 生产资产的数据必须逐条相等，且不得因跨语言强转而丢字段。
func test_legacy_and_gd_recipe_assets_match() -> void:
	for pair: Array in RECIPE_PAIRS:
		var legacy: Resource = load(pair[0])
		var migrated: Resource = load(pair[1])
		assert_true(legacy != null, "%s 必须仍可加载（兼容输入）。" % pair[0])
		assert_true(migrated != null, "%s 必须可加载。" % pair[1])
		if legacy == null or migrated == null:
			continue
		assert_eq(
			(legacy.get_script() as Script).resource_path,
			RECIPE_GD,
			"%s 必须使用 GDScript 配方脚本，否则 C# 强类型垫片会拒收已迁移物品资源。" % pair[0]
		)
		assert_true(legacy.get("OutputItem") != null, "%s 的产出物品不得因跨语言强转而丢失。" % pair[0])
		var legacy_inputs: Array = legacy.get("Inputs")
		assert_gt(legacy_inputs.size(), 0, "%s 的材料条目不得因跨语言强转而丢失。" % pair[0])
		for entry in legacy_inputs:
			assert_true(entry.get("RequiredItem") != null, "%s 的材料物品不得因跨语言强转而丢失。" % pair[0])
		assert_eq(
			(migrated.get_script() as Script).resource_path,
			RECIPE_GD,
			"%s 必须使用 GDScript 配方脚本。" % pair[1]
		)
		assert_eq(
			_recipe_snapshot(migrated),
			_recipe_snapshot(legacy),
			"%s 与 %s 的配方数据必须完全一致（名称 / 材料顺序 / 数量 / 产出）。" % [pair[1], pair[0]]
		)
		var inputs: Array = migrated.get("Inputs")
		for entry in inputs:
			assert_eq(
				(entry.get_script() as Script).resource_path,
				INGREDIENT_GD,
				"%s 的材料条目必须使用 GDScript 材料脚本。" % pair[1]
			)


# ----- 生产引用边界 -----

## 生产场景与生产 GDScript 不得引用 crafting 的 .cs；旧配方资产是唯一例外。
func test_production_scenes_avoid_csharp_crafting_scripts() -> void:
	var asset_hits: Array = []
	for legacy_path: String in LEGACY_CS_PATHS:
		asset_hits.append_array(_scan("res://scenes", legacy_path, ["tscn", "tres", "res"]))
		asset_hits.append_array(_scan("res://resources", legacy_path, ["tscn", "tres", "res"]))
	for hit: String in asset_hits:
		assert_true(
			LEGACY_ASSET_ALLOWLIST.has(hit),
			"生产资产不得引用 crafting 的旧 C# 脚本：%s" % hit
		)
	# 自证扫描有效：同一批 roots / 扩展名下必须能扫出已知存在的 GDScript 配方引用，
	# 否则上面的“零命中”可能只是扫描器没有产出。
	var proof_hits: Array = []
	for root: String in ["res://scenes", "res://resources"]:
		proof_hits.append_array(_scan(root, "crafting_recipe.gd", ["tscn", "tres", "res"]))
	assert_gt(proof_hits.size(), 0, "资产扫描器必须能扫到已知的 GDScript 配方引用，否则零命中没有证据。")
	var code_hits: Array = []
	for root: String in PRODUCTION_ROOTS:
		for legacy_path: String in LEGACY_CS_PATHS:
			code_hits.append_array(_scan(root, legacy_path, ["gd"], true))
	assert_eq(code_hits, [], "生产 GDScript 不得加载 crafting 的旧 C# 路径：%s" % str(code_hits))
	var player: String = _read("res://scenes/player_scenes/player.tscn")
	assert_true(player.contains(RECIPE_BOOK_GD), "玩家配方书必须使用 GDScript Resource。")
	assert_true(player.contains(RECIPE_GD), "玩家配方必须使用 GDScript 配方脚本。")
	assert_true(
		player.contains("res://entities/components/crafting_component.gd"),
		"玩家合成组件必须使用 GDScript 实现。"
	)
	assert_true(
		_read("res://scenes/crafting/crafting_ui.tscn").contains("res://core/ui/crafting/crafting_ui.gd"),
		"合成界面场景必须使用 GDScript 实现。"
	)


## 统计子串出现次数。
##
## 参数 text：源码正文。
## 参数 needle：目标子串。
## 返回值：出现次数。
func _count_occurrences(text: String, needle: String) -> int:
	return text.split(needle).size() - 1
