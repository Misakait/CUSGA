@tool
extends McpTestSuite

## 技能卡类别标签与分类贴图的契约套件。
##
## 锁定四件事：
## 1）类别常量与默认值（未分类 0 / 攻击 1 / 防御 2 / 状态 3）；
## 2）生产技能卡都带**显式**类别行——证明回填确实落盘，而不是被默认值悄然吞掉；
## 3）卡面脚本的类别→贴图映射指向正确的模板，并保留未分类兜底；
## 4）卡面的类别镜像常量与数据脚本的类别常量数值一致，防止两处各自演化。
##
## 环境限制：真实卡面 `SkillCard` 是非 `@tool` 的 Node2D 脚本，编辑器测试里
## `PackedScene.instantiate()` 只能得到占位实例、方法不可调用（与
## `test_run_start_skill_card_contract.gd` 记录的限制一致）。因此「贴图确实随类别切换」
## 由冒烟阶段的 `game_eval` 在真实游戏内断言，本套件只做数据契约与源码形状断言，
## 不假装测过无法在编辑器里执行的行为。

const SKILL_CARD_DATA_GD: String = "res://resources/item/card/skill_card_data.gd"
const SKILL_CARD_GD: String = "res://scripts/card_scripts/skill_card.gd"
const SKILL_CARD_DIR: String = "res://resources/skill_cards"

## 类别常量名 → 约定数值；顺序即取值约定，改动这里等于改动资产兼容协议。
const CATEGORY_ROWS: Array = [
	["CARD_CATEGORY_UNCLASSIFIED", 0],
	["CARD_CATEGORY_ATTACK", 1],
	["CARD_CATEGORY_DEFENSE", 2],
	["CARD_CATEGORY_STATUS", 3],
]

## 卡面贴图常量名 → 模板资源路径。四张贴图都必须同时「被脚本引用」且「资源真实存在」。
const FRAME_ROWS: Array = [
	["CARD_FRAME_ATTACK", "res://res/Card/skillcardboard/技能卡模板-红.png"],
	["CARD_FRAME_DEFENSE", "res://res/Card/skillcardboard/技能卡模板-绿.png"],
	["CARD_FRAME_STATUS", "res://res/Card/skillcardboard/技能卡模板-蓝.png"],
	["CARD_FRAME_UNCLASSIFIED", "res://res/skillcard/技能卡模板2.png"],
]

## 卡面镜像常量 → 数据脚本常量；两侧数值必须一致。
const MIRROR_ROWS: Array = [
	["CATEGORY_ATTACK", "CARD_CATEGORY_ATTACK"],
	["CATEGORY_DEFENSE", "CARD_CATEGORY_DEFENSE"],
	["CATEGORY_STATUS", "CARD_CATEGORY_STATUS"],
]

## 代表性生产卡：普通纯伤害卡 + 攻防数值相等的平局卡（按规则归攻击牌）。
const REPRESENTATIVE_CARDS: Array = [
	"res://resources/skill_cards/earth_phys_tuji.tres",
	"res://resources/skill_cards/test_card_2.tres",
]

## 改动前已存在的生产技能卡数量，用作「扫描确实命中生产规模」的下界证据。
const PRODUCTION_CARD_FLOOR: int = 69


## 套件名，供 `test_run(suite=...)` 定位。
##
## 返回值：固定套件名。
func suite_name() -> String:
	return "skill_card_category_contract"


## 读取文本文件。
##
## 参数 path：`res://` 路径。
## 返回值：文件正文；读取失败时返回空字符串。
func _read(path: String) -> String:
	return FileAccess.get_file_as_string(path)


## 读取脚本的常量表。
##
## 参数 path：脚本的 `res://` 路径。
## 返回值：常量名 → 值的字典；脚本不可加载时返回空字典。
func _constants_of(path: String) -> Dictionary:
	var script: Script = load(path) as Script
	if script == null:
		return {}
	return script.get_script_constant_map()


## 类别常量的取值必须与约定一致，且未分类固定在 0。
func test_category_constants_have_expected_values() -> void:
	var constants: Dictionary = _constants_of(SKILL_CARD_DATA_GD)
	assert_gt(constants.size(), 0, "技能卡数据脚本必须可加载并暴露常量。")
	for row: Array in CATEGORY_ROWS:
		assert_eq(constants.get(row[0]), row[1], "类别常量 %s 必须等于 %d。" % [row[0], row[1]])


## 类别默认值必须是未分类。
##
## 若默认值为攻击，Godot 保存资源时会省略「等于默认值」的属性行，回填结果会在
## 任何一次 Inspector 保存后消失，因此这条断言同时锁住默认值与回填的持久性前提。
func test_category_default_is_unclassified() -> void:
	var source: String = _read(SKILL_CARD_DATA_GD)
	assert_gt(source.length(), 0, "技能卡数据脚本必须可读。")
	assert_true(
		source.contains("var CardCategory: int = CARD_CATEGORY_UNCLASSIFIED"),
		"CardCategory 必须声明默认值 CARD_CATEGORY_UNCLASSIFIED。"
	)

	var script: Script = load(SKILL_CARD_DATA_GD) as Script
	assert_true(script != null, "技能卡数据脚本必须可加载。")
	if script == null:
		return
	var instance: Resource = script.new() as Resource
	assert_true(instance != null, "技能卡数据脚本必须可实例化。")
	if instance == null:
		return
	assert_eq(instance.get("CardCategory"), 0, "未配置的新卡类别必须是未分类（0）。")


## 每张生产技能卡都必须带显式类别行，且值为攻击牌。
func test_production_cards_carry_explicit_category() -> void:
	var dir: DirAccess = DirAccess.open(SKILL_CARD_DIR)
	assert_true(dir != null, "技能卡目录必须可打开：%s" % SKILL_CARD_DIR)
	if dir == null:
		return

	var checked: int = 0
	var missing: Array[String] = []
	var unexpected: Array[String] = []
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			checked += 1
			var text: String = _read(SKILL_CARD_DIR + "/" + file_name)
			if text.find("CardCategory = 1") == -1:
				missing.append(file_name)
			elif text.find("CardCategory = 0") != -1:
				# 未分类不是任何生产卡应有的结果，出现即说明回填判定被改坏。
				unexpected.append(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()

	assert_gt(
		checked,
		PRODUCTION_CARD_FLOOR - 1,
		"技能卡目录必须至少包含 %d 张生产卡，否则扫描零命中没有证据。" % PRODUCTION_CARD_FLOOR
	)
	assert_eq(unexpected.size(), 0, "以下技能卡被回填成未分类，判定规则可能已改坏：%s" % ", ".join(unexpected))
	assert_eq(missing.size(), 0, "以下技能卡缺少显式 CardCategory = 1 行：%s" % ", ".join(missing))


## 卡面脚本必须声明四张贴图常量，且四张模板资源真实存在。
func test_card_frame_mapping_targets_exist() -> void:
	var source: String = _read(SKILL_CARD_GD)
	assert_gt(source.length(), 0, "卡面脚本必须可读。")

	for row: Array in FRAME_ROWS:
		var constant_name: String = row[0]
		var path: String = row[1]
		assert_true(
			source.contains("const %s: Texture2D = preload(" % constant_name),
			"卡面脚本必须声明贴图常量 %s。" % constant_name
		)
		assert_true(source.contains(path), "贴图常量 %s 必须引用 %s。" % [constant_name, path])
		assert_true(ResourceLoader.exists(path), "贴图资源必须存在：%s" % path)

	# 换色必须发生在卡面唯一的绑定入口里，否则三个复用界面会各自演化出不同判断。
	assert_true(
		source.contains("func _resolve_card_frame(card_data) -> Texture2D:"),
		"卡面脚本必须提供类别→贴图的解析函数。"
	)
	assert_true(
		source.contains("$Sprite2D.texture = _resolve_card_frame(card_data)"),
		"init_card_data 必须把解析结果写给 Sprite2D。"
	)


## 卡面的类别镜像常量必须与数据脚本的类别常量逐项一致。
func test_face_mirror_constants_match_data_script() -> void:
	var data_constants: Dictionary = _constants_of(SKILL_CARD_DATA_GD)
	var face_constants: Dictionary = _constants_of(SKILL_CARD_GD)
	assert_gt(data_constants.size(), 0, "数据脚本常量表必须可读。")
	assert_gt(face_constants.size(), 0, "卡面脚本常量表必须可读。")
	for row: Array in MIRROR_ROWS:
		var face_name: String = row[0]
		var data_name: String = row[1]
		assert_eq(
			face_constants.get(face_name),
			data_constants.get(data_name),
			"卡面镜像常量 %s 必须与数据脚本 %s 相等。" % [face_name, data_name]
		)


## 代表性生产卡的类别必须能从资源读回，平局卡按规则归攻击。
func test_representative_cards_expose_category() -> void:
	for path: String in REPRESENTATIVE_CARDS:
		var card: Resource = load(path) as Resource
		assert_true(card != null, "代表性技能卡必须可加载：%s" % path)
		if card == null:
			continue
		assert_eq(card.get("CardCategory"), 1, "%s 的类别应为攻击牌（1）。" % path)
