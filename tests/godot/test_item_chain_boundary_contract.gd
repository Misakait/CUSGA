@tool
extends McpTestSuite

## 物品链边界契约套件（C# 垫片 ↔ GDScript 生产实现）。
##
## 现状：物品数据家族（ItemData / BaseCardData / ResourceCardData / SkillCardData / ToolData /
## EquipmentData / EquipmentSetData / SetBonusTier）、ItemStack 与商店链（ShopCatalog /
## ShopFailureReason / ShopService / ShopTradeBridge）在生产侧全部已是 GDScript：player.tscn、
## Main.tscn、Shop.tscn 与全部物品资产都只绑定 .gd 脚本，旧 C# 类型只被未迁移的 C# 代码与
## tests/CUSGA.Tests 对照用例消费。
## 本套件锁定四件事：
## 1）C# 垫片与 GDScript 生产脚本的导出字段名 / 顺序与关键默认值一致；
## 2）跨语言容器弱化只允许出现在明确登记的位置（强类型数组/字典会在反序列化阶段拒收 GDScript 资源）；
## 3）商店目录、商店场景与全部物品资产只绑定 GDScript；
## 4）生产 GDScript 不得再按旧 C# 脚本路径分支（出战卡组的技能卡判定已改为字段协议）。

## 物品数据家族：[标签, C# 垫片路径, GDScript 生产路径, [导出字段名（按原顺序）]]。
const ITEM_CLASS_ROWS: Array = [
	["ItemData", "res://resources/item/ItemData.cs", "res://resources/item/item_data.gd", ["MaxStackSize", "ItemTags", "BuyPrice", "SellPrice"]],
	["BaseCardData", "res://resources/item/BaseCardData.cs", "res://resources/item/base_card_data.gd", ["CardId", "CardName", "CardIcon", "Description"]],
	["ResourceCardData", "res://resources/item/card/ResourceCardData.cs", "res://resources/item/card/resource_card_data.gd", []],
	["SkillCardData", "res://resources/item/card/SkillCardData.cs", "res://resources/item/card/skill_card_data.gd", ["Skill", "cost", "CardTags", "CardCategory"]],
	["ToolData", "res://resources/item/tool/ToolData.cs", "res://resources/item/tool/tool_data.gd", ["TargetGatheringTag", "YieldGrowth", "GatheringTimeReduction"]],
	["EquipmentData", "res://resources/item/equipment/EquipmentData.cs", "res://resources/item/equipment/equipment_data.gd", ["ValidSlots", "SetType", "AttributeBonuses", "GrantedTags"]],
	["EquipmentSetData", "res://resources/item/equipment/EquipmentSetData.cs", "res://resources/item/equipment/equipment_set_data.gd", ["SetType", "Tiers"]],
	["SetBonusTier", "res://resources/item/equipment/SetBonusTier.cs", "res://resources/item/equipment/set_bonus_tier.gd", ["RequiredPieces", "AttributeBonuses", "GrantedTags"]],
	["ShopCatalog", "res://core/shop/ShopCatalog.cs", "res://resources/shop/shop_catalog.gd", ["Goods", "AlsoIncludeEveryPricedItem", "DefaultBuyPrice"]],
]

## GDScript 侧必须原样保留的导出声明（含默认值）。
const GD_EXPORT_SNIPPETS: Array = [
	["res://resources/item/base_card_data.gd", ["@export var CardId: StringName = &\"\"", "@export var CardName: String = \"\"", "@export var CardIcon: Texture2D", "@export_multiline var Description: String = \"\""]],
	["res://resources/item/item_data.gd", ["@export var MaxStackSize: int = 99", "@export var ItemTags: Array[StringName] = []", "@export var BuyPrice: int = 0", "@export var SellPrice: int = 0"]],
	["res://resources/item/card/skill_card_data.gd", ["@export var Skill: Resource", "@export var cost: int = 10", "@export var CardTags: Array[String] = []", "@export_enum(\"未分类\", \"攻击\", \"防御\", \"状态\") var CardCategory: int = CARD_CATEGORY_UNCLASSIFIED"]],
	["res://resources/item/tool/tool_data.gd", ["@export var TargetGatheringTag: StringName = &\"\"", "@export var YieldGrowth: int = 0", "@export_range(0, 999, 1, \"or_greater\") var GatheringTimeReduction: int = 0"]],
	["res://resources/item/equipment/equipment_data.gd", ["@export var ValidSlots: Array[int] = []", "@export var SetType: int = 0", "@export var AttributeBonuses: Dictionary = {}", "@export var GrantedTags: Array[StringName] = []"]],
	["res://resources/item/equipment/equipment_set_data.gd", ["@export var SetType: int = 0", "@export var Tiers: Array[Resource] = []"]],
	["res://resources/item/equipment/set_bonus_tier.gd", ["@export var RequiredPieces: int = 0", "@export var AttributeBonuses: Dictionary = {}", "@export var GrantedTags: Array[StringName] = []"]],
	["res://resources/shop/shop_catalog.gd", ["@export var Goods: Array[Resource] = []", "@export var AlsoIncludeEveryPricedItem: bool = false", "@export_range(0, 999999, 1, \"or_greater\") var DefaultBuyPrice: int = 100"]],
]

## C# 垫片侧必须原样保留的默认值声明。
const CS_EXPORT_SNIPPETS: Array = [
	["res://resources/item/ItemData.cs", ["[Export] public int MaxStackSize { get; set; } = 99;", "[Export] public int BuyPrice { get; set; } = 0;", "[Export] public int SellPrice { get; set; } = 0;"]],
	["res://resources/item/card/SkillCardData.cs", ["[Export] public Resource Skill { get; set; }", "[Export] public int cost = 10;"]],
	["res://core/shop/ShopCatalog.cs", ["public Godot.Collections.Array<ItemData> Goods { get; set; } = [];", "public bool AlsoIncludeEveryPricedItem { get; set; } = false;", "public int DefaultBuyPrice { get; set; } = 100;"]],
]

## 允许的跨语言容器弱化（C# 强类型 → GDScript 通用类型）。
const CONTAINER_WEAKENING_CS_ROWS: Array = [
	["res://resources/item/equipment/EquipmentData.cs", "Array<EquipmentSlot> ValidSlots"],
	["res://resources/item/equipment/EquipmentData.cs", "Dictionary<AttributeType, Vector2I> AttributeBonuses"],
	["res://resources/item/equipment/EquipmentSetData.cs", "Array<SetBonusTier> Tiers"],
	["res://resources/item/equipment/SetBonusTier.cs", "Dictionary<AttributeType, float> AttributeBonuses"],
	["res://core/shop/ShopCatalog.cs", "Godot.Collections.Array<ItemData> Goods"],
]

## 弱化后的 GDScript 出口类型。
const CONTAINER_WEAKENING_GD_ROWS: Array = [
	["res://resources/item/equipment/equipment_data.gd", "@export var ValidSlots: Array[int] = []"],
	["res://resources/item/equipment/equipment_data.gd", "@export var AttributeBonuses: Dictionary = {}"],
	["res://resources/item/equipment/equipment_set_data.gd", "@export var Tiers: Array[Resource] = []"],
	["res://resources/item/equipment/set_bonus_tier.gd", "@export var AttributeBonuses: Dictionary = {}"],
	["res://resources/shop/shop_catalog.gd", "@export var Goods: Array[Resource] = []"],
]

## 物品链生产 GDScript；这些文件里不得出现跨语言强类型容器。
const ITEM_CHAIN_GD_PATHS: Array = [
	"res://resources/item/base_card_data.gd",
	"res://resources/item/item_data.gd",
	"res://resources/item/item_data_compat.gd",
	"res://resources/item/item_stack.gd",
	"res://resources/item/card/resource_card_data.gd",
	"res://resources/item/card/skill_card_data.gd",
	"res://resources/item/tool/tool_data.gd",
	"res://resources/item/equipment/equipment_data.gd",
	"res://resources/item/equipment/equipment_data_compat.gd",
	"res://resources/item/equipment/equipment_set_data.gd",
	"res://resources/item/equipment/set_bonus_tier.gd",
	"res://resources/shop/shop_catalog.gd",
	"res://core/shop/shop_trade_bridge.gd",
]

## 一旦出现在 GDScript 出口或读取代码里，就会在反序列化 / 赋值阶段拒收另一侧资源。
const FORBIDDEN_GD_TYPES: Array = [
	"Array[ItemData]",
	"Array[BaseCardData]",
	"Array[ResourceCardData]",
	"Array[SkillCardData]",
	"Array[ToolData]",
	"Array[EquipmentData]",
	"Array[EquipmentSetData]",
	"Array[SetBonusTier]",
	"Array[EquipmentSlot]",
	"Array<ItemData>",
	"Array<SkillCardData>",
	"Dictionary[AttributeType",
	"Dictionary<AttributeType",
]

## 商店失败原因：[成员名, 数值]。
const SHOP_FAILURE_ROWS: Array = [
	["None", 0],
	["InvalidItem", 1],
	["InvalidQuantity", 2],
	["NotEnoughGold", 3],
	["NotEnoughSpace", 4],
	["MissingItem", 5],
	["NotConfigured", 6],
]

## scripts/shop/shop_control.gd 里的具名镜像常量。
const SHOP_FAILURE_MIRROR_SNIPPETS: Array = [
	"const FAILURE_NONE := 0",
	"const FAILURE_INVALID_ITEM := 1",
	"const FAILURE_INVALID_QUANTITY := 2",
	"const FAILURE_NOT_ENOUGH_GOLD := 3",
	"const FAILURE_NOT_ENOUGH_SPACE := 4",
	"const FAILURE_MISSING_ITEM := 5",
	"const FAILURE_NOT_CONFIGURED := 6",
]

## 物品链的旧 C# 脚本路径；生产 GDScript 一律不得引用。
const LEGACY_CS_PATHS: Array = [
	"resources/item/ItemData.cs",
	"resources/item/BaseCardData.cs",
	"resources/item/card/ResourceCardData.cs",
	"resources/item/card/SkillCardData.cs",
	"resources/item/tool/ToolData.cs",
	"resources/item/equipment/EquipmentData.cs",
	"resources/item/equipment/EquipmentSetData.cs",
	"resources/item/equipment/SetBonusTier.cs",
	"core/inventory/ItemStack.cs",
	"core/inventory/ItemStackProtocol.cs",
	"core/shop/ShopCatalog.cs",
	"core/shop/ShopService.cs",
	"core/shop/ShopTradeBridge.cs",
	"core/shop/ShopFailureReason.cs",
	"core/shop/IPlayerWallet.cs",
	"core/shop/IShopInventory.cs",
	"resources/debug/DebugItemStackEntry.cs",
	"resources/debug/DebugGeneratedEquipmentEntry.cs",
	"resources/debug/DebugLoadoutData.cs",
]

## 生产根目录（不含 tests）。
const PRODUCTION_ROOTS: Array = ["res://core", "res://entities", "res://resources", "res://scripts"]
## C# 可选助手：C# 缺席时安全收起跨语言对照，避免解析期错误与「空源文假通过」。
const CS_OPTIONAL := preload("res://tests/godot/csharp_optional.gd")


func suite_name() -> String:
	return "item_chain_boundary_contract"


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


## 解析 C# `[Export]` 属性与字段的声明顺序。
##
## 参数 text：C# 源码。
## 返回值：按出现顺序排列的字段名数组。
func _csharp_export_names(text: String) -> Array:
	var names: Array = []
	var regex := RegEx.new()
	if regex.compile("\\[Export[^\\]]*\\]\\s*public\\s+[A-Za-z0-9_<>,.\\s\\[\\]]+?\\s+([A-Za-z_][A-Za-z0-9_]*)\\s*(?:\\{|=[^;]*;)") != OK:
		return names
	for match_result: RegExMatch in regex.search_all(text):
		names.append(match_result.get_string(1))
	return names


## 解析 GDScript `@export` 变量的声明顺序。
##
## 参数 text：GDScript 源码。
## 返回值：按出现顺序排列的字段名数组。
func _gd_export_names(text: String) -> Array:
	var names: Array = []
	var source: String = _strip_gd_comments(text)
	var regex := RegEx.new()
	if regex.compile("@export[^\\n]*?\\bvar\\s+([A-Za-z_][A-Za-z0-9_]*)") != OK:
		return names
	for match_result: RegExMatch in regex.search_all(source):
		names.append(match_result.get_string(1))
	return names


## 判断对象是否暴露指定属性。
##
## 参数 target：被检查对象。
## 参数 property_name：属性名。
## 返回值：属性列表中存在该名字时为 true。
func _has_property(target: Object, property_name: String) -> bool:
	for info in target.get_property_list():
		if info is Dictionary and str(info.get("name", "")) == property_name:
			return true
	return false


## 递归收集目录下指定扩展名的文件。
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


## 在目录树里查找包含指定文本的文件。
##
## 参数 dir_path：res:// 目录。
## 参数 needle：目标子串；空字符串表示匹配全部。
## 参数 extensions：扩展名数组（不含点）。
## 参数 strip_comments：为 true 时先去掉 GDScript 注释。
## 返回值：命中的 res:// 路径数组。
func _scan(dir_path: String, needle: String, extensions: Array, strip_comments: bool = false) -> Array:
	var hits: Array = []
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return hits
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		var full: String = dir_path + "/" + file_name
		if file_name != "." and file_name != "..":
			if dir.current_is_dir():
				hits.append_array(_scan(full, needle, extensions, strip_comments))
			elif extensions.has(full.get_extension()):
				var text: String = _read(full)
				if strip_comments:
					text = _strip_gd_comments(text)
				if needle == "" or text.find(needle) != -1:
					hits.append(full)
		file_name = dir.get_next()
	dir.list_dir_end()
	return hits


# ----- 字段与默认值 -----

## C# 垫片与 GDScript 生产脚本的导出字段名与顺序必须一致。
func test_export_field_parity() -> void:
	var gd_parsed_total: int = 0
	for row: Array in ITEM_CLASS_ROWS:
		var label: String = row[0]
		## C# 源文对照：C# 退役后 read() 返回空串，C# 侧解析断言按条件收起。
		var cs_text: String = CS_OPTIONAL.read(row[1])
		var gd_text: String = _read(row[2])
		assert_gt(gd_text.length(), 0, "%s 的 GDScript 生产脚本必须存在且可读。" % label)
		var gd_names: Array = _gd_export_names(gd_text)
		assert_eq(gd_names, row[3], "%s 的 GDScript 导出字段名与顺序必须与登记表一致。" % label)
		gd_parsed_total += gd_names.size()
		if not cs_text.is_empty():
			var cs_names: Array = _csharp_export_names(cs_text)
			assert_eq(cs_names, row[3], "%s 的 C# 导出字段名与顺序必须与登记表一致。" % label)
	assert_gt(gd_parsed_total, 20, "解析器必须确实读到 GDScript 导出字段，否则数组相等没有证据。")


## GDScript 与 C# 两侧的关键默认值必须原样保留。
func test_export_defaults_survive() -> void:
	for row: Array in GD_EXPORT_SNIPPETS:
		var gd_text: String = _read(row[0])
		assert_gt(gd_text.length(), 0, "%s 必须可读。" % row[0])
		for snippet: String in row[1]:
			assert_true(gd_text.contains(snippet), "%s 必须保留：%s" % [row[0], snippet])
	for row: Array in CS_EXPORT_SNIPPETS:
		## C# 源文对照：C# 退役后 read() 返回空串，整条 C# 默认值对照按条件收起。
		var cs_text: String = CS_OPTIONAL.read(row[0])
		if cs_text.is_empty():
			continue
		for snippet: String in row[1]:
			assert_true(cs_text.contains(snippet), "%s 必须保留：%s" % [row[0], snippet])


# ----- 跨语言容器弱化 -----

## 强类型容器只允许出现在登记的 C# 垫片位置，GDScript 侧必须使用通用类型。
func test_container_weakening_is_registered_only() -> void:
	for row: Array in CONTAINER_WEAKENING_CS_ROWS:
		## C# 源文对照：C# 退役后 read() 返回空串，整条强类型容器对照按条件收起。
		var cs_text: String = CS_OPTIONAL.read(row[0])
		if cs_text.is_empty():
			continue
		assert_true(cs_text.contains(row[1]), "%s 的强类型容器必须仍是登记的形态：%s" % [row[0], row[1]])
	for row: Array in CONTAINER_WEAKENING_GD_ROWS:
		var gd_text: String = _read(row[0])
		assert_gt(gd_text.length(), 0, "%s 必须可读。" % row[0])
		assert_true(gd_text.contains(row[1]), "%s 必须使用通用容器：%s" % [row[0], row[1]])
	for path: String in ITEM_CHAIN_GD_PATHS:
		var text: String = _strip_gd_comments(_read(path))
		assert_gt(text.length(), 0, "%s 必须可读，否则零命中没有证据。" % path)
		for token: String in FORBIDDEN_GD_TYPES:
			assert_true(not text.contains(token), "%s 不得声明跨语言强类型容器 %s。" % [path, token])


# ----- 商店链 -----

## 商店失败原因的数值必须在 C#、GDScript 枚举与 UI 镜像常量三处一致。
func test_shop_failure_reason_parity() -> void:
	## C# 源文对照：C# 退役后 read() 返回空串，C# 枚举镜像断言按条件收起。
	var cs_text: String = CS_OPTIONAL.read("res://core/shop/ShopFailureReason.cs")
	var gd_text: String = _read("res://core/shop/shop_failure_reason.gd")
	var service_text: String = _read("res://core/shop/shop_service.gd")
	var control_text: String = _read("res://scripts/shop/shop_control.gd")
	assert_gt(gd_text.length(), 0, "shop_failure_reason.gd 必须可读。")
	assert_gt(service_text.length(), 0, "shop_service.gd 必须可读。")
	assert_gt(control_text.length(), 0, "shop_control.gd 必须可读。")
	for row: Array in SHOP_FAILURE_ROWS:
		var expected: String = "%s = %d" % [row[0], row[1]]
		if not cs_text.is_empty():
			assert_true(cs_text.contains(expected), "C# 枚举必须保留 %s。" % expected)
		assert_true(gd_text.contains(expected), "GDScript 枚举镜像必须保留 %s。" % expected)
		assert_true(service_text.contains(expected), "shop_service.gd 内嵌枚举必须保留 %s。" % expected)
	for snippet: String in SHOP_FAILURE_MIRROR_SNIPPETS:
		assert_true(control_text.contains(snippet), "shop_control.gd 必须保留镜像常量：%s" % snippet)


## 商店场景、目录资产与商品都必须只绑定 GDScript。
func test_shop_scene_and_catalog_bind_gdscript() -> void:
	var scene_text: String = _read("res://scenes/Shop/Shop.tscn")
	assert_gt(scene_text.length(), 0, "Shop.tscn 必须可读。")
	for snippet: String in [
		"res://scripts/shop/shop_control.gd",
		"res://core/shop/shop_trade_bridge.gd",
		"res://resources/shop/shop_catalog.tres",
	]:
		assert_true(scene_text.contains(snippet), "商店场景必须绑定 %s。" % snippet)
	assert_true(not scene_text.contains(".cs\""), "商店场景不得绑定 C# 脚本。")
	var catalog: Resource = load("res://resources/shop/shop_catalog.tres")
	assert_true(catalog != null, "商店目录资产必须可加载。")
	assert_eq(
		(catalog.get_script() as Script).resource_path,
		"res://resources/shop/shop_catalog.gd",
		"商店目录必须使用 GDScript 目录脚本。"
	)
	var goods: Array = catalog.get("Goods")
	assert_gt(goods.size(), 40, "商店目录必须仍挂着全部商品（自证数量，避免空目录也通过）。")
	var csharp_goods: int = 0
	var null_goods: int = 0
	for entry in goods:
		if entry == null:
			null_goods += 1
			continue
		var entry_script: Script = entry.get_script()
		if entry_script != null and String(entry_script.resource_path).ends_with(".cs"):
			csharp_goods += 1
	assert_eq(null_goods, 0, "商店目录不得出现空商品。")
	assert_eq(csharp_goods, 0, "商店商品不得再来自 C# 脚本。")
	assert_eq(catalog.get("AlsoIncludeEveryPricedItem"), false, "默认不得自动上架全部定价物品。")
	assert_eq(catalog.get("DefaultBuyPrice"), 100, "兜底买价必须保持 100。")


# ----- 物品资产与脚本绑定 -----

## 全部物品资产不得再引用 C# 脚本。
func test_item_assets_use_gdscript_scripts() -> void:
	var files: Array = _collect_files("res://items", ["tres"])
	assert_gt(files.size(), 40, "物品资产目录必须确实有产出（自证扫描有效）。")
	for path: String in files:
		var text: String = _read(path)
		assert_gt(text.length(), 0, "%s 必须可读。" % path)
		assert_true(not text.contains(".cs\""), "%s 不得引用 C# 脚本。" % path)


## 生产 GDScript 不得再引用物品链的旧 C# 路径。
func test_production_has_no_item_chain_csharp_dependency() -> void:
	var files: Array = []
	for root: String in PRODUCTION_ROOTS:
		files.append_array(_collect_files(root, ["gd"]))
	assert_gt(files.size(), 200, "生产 GDScript 扫描必须确实有产出，否则零命中没有证据。")
	var hits: Array = []
	for path: String in files:
		var text: String = _strip_gd_comments(_read(path))
		for legacy_path: String in LEGACY_CS_PATHS:
			if text.find(legacy_path) != -1:
				hits.append("%s -> %s" % [path, legacy_path])
	assert_eq(hits, [], "生产 GDScript 不得引用物品链旧 C# 路径：%s" % str(hits))
	var proof: Array = _scan("res://entities", "item_stack.gd", ["gd"])
	assert_gt(proof.size(), 0, "扫描器必须能扫到已知的 GDScript 物品脚本引用，否则零命中没有证据。")


# ----- 跨语言运行协议 -----

## 出战卡组的技能卡判定必须只依赖 Skill 字段协议，同时接受两种语言的技能卡。
func test_skill_card_predicate_is_language_neutral() -> void:
	var deck_path: String = "res://entities/components/battle_deck_component.gd"
	var deck_text: String = _read(deck_path)
	assert_gt(deck_text.length(), 0, "battle_deck_component.gd 必须可读。")
	assert_true(
		not _strip_gd_comments(deck_text).contains("SkillCardData.cs"),
		"出战卡组不得再按旧 C# 脚本路径分支。"
	)
	var deck_script: GDScript = load(deck_path)
	assert_true(deck_script != null, "battle_deck_component.gd 必须可加载。")
	var deck: Node = deck_script.new()
	assert_true(deck != null, "出战卡组组件必须可实例化。")
	var gd_card: Resource = load("res://resources/skill_cards/earth_magic_houtufenglingmai.tres")
	var plain_item: Resource = load("res://items/items/leaf.tres")
	## 兼容技能卡：迁移期是旧 C# 垫片，C# 退役后是等价的生产 GDScript 技能卡。
	var legacy_script: Script = CS_OPTIONAL.script_or(
		"res://resources/item/card/SkillCardData.cs",
		"res://resources/item/card/skill_card_data.gd"
	)
	assert_true(gd_card != null and plain_item != null and legacy_script != null, "测试夹具必须可加载。")
	var legacy_card: Resource = legacy_script.new()
	assert_true(legacy_card != null, "兼容 SkillCardData 必须仍可实例化。")
	legacy_card.set("Skill", gd_card)
	assert_true(deck.call("_can_store_item", gd_card), "GDScript 技能卡必须可进出战卡组。")
	assert_true(deck.call("_can_store_item", legacy_card), "兼容 SkillCardData 输入必须仍可进出战卡组。")
	assert_true(not deck.call("_can_store_item", plain_item), "普通物品不得进出战卡组。")
	assert_true(not deck.call("_can_store_item", null), "空物品不得进出战卡组。")
	deck.free()


## item_stack.gd 必须满足旧 C# ItemStackProtocol 依赖的成员与语义。
func test_item_stack_protocol_members() -> void:
	var stack_script: GDScript = load("res://resources/item/item_stack.gd")
	assert_true(stack_script != null, "item_stack.gd 必须可加载。")
	var stack: RefCounted = stack_script.new()
	assert_true(stack != null, "item_stack.gd 必须可实例化。")
	assert_true(stack.has_method("SetItem") and stack.has_method("Clear"), "旧 C# 协议依赖的两个方法必须存在。")
	for property_name: String in ["Item", "Amount", "IsEmpty", "IsFull", "AvailableSpace", "RolledAttributes"]:
		assert_true(_has_property(stack, property_name), "item_stack.gd 必须暴露稳定属性 %s。" % property_name)
	var item: Resource = load("res://items/items/leaf.tres")
	assert_true(item != null, "测试物品必须可加载。")
	stack.call("SetItem", item, 3)
	assert_eq(stack.get("Amount"), 3, "SetItem 必须写入数量。")
	assert_eq(stack.get("Item"), item, "堆叠必须保留原始物品资源身份。")
	assert_true(not bool(stack.get("IsEmpty")), "SetItem 后必须非空。")
	var overflow: int = int(stack.call("Add", 1000))
	assert_gt(overflow, 0, "超过堆叠上限的部分必须原样返回。")
	stack.call("Clear")
	assert_true(bool(stack.get("IsEmpty")) and stack.get("Item") == null, "Clear 必须清空物品与数量。")
	## C# 协议读取器的源文对照：C# 退役后 read() 返回空串，整块按条件收起而不是假通过。
	var protocol_text: String = CS_OPTIONAL.read("res://core/inventory/ItemStackProtocol.cs")
	if not protocol_text.is_empty():
		for snippet: String in [
			"SetItemMethod = \"SetItem\"",
			"ClearMethod = \"Clear\"",
			"ItemProperty = \"Item\"",
			"AmountProperty = \"Amount\"",
			"IsEmptyProperty = \"IsEmpty\"",
		]:
			assert_true(protocol_text.contains(snippet), "C# 协议读取器必须仍读取：%s" % snippet)
