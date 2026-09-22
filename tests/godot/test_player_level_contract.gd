@tool
extends McpTestSuite

## PlayerLevel（core/progression/player_level.gd）等级与经验规则契约套件。
##
## 套件锁定三件事：
## 1）生产脚本形状与公开面：常量、经验曲线参数、信号、接口逐字锁定，防止数值被无声改动；
## 2）规则行为：经验累积、连续升级、满级封顶、边界输入、属性点发放与领取；
## 3）信号契约：三个信号在逐级升级与一次连升多级时的触发次数与载荷。
##
## 编辑器侧只验证纯规则：测试实例刻意不加入场景树，因此不会执行 _ready、不会解析
## SettingsManager，也不会读取本地存档——这样同一套断言在任何环境下结果一致。
## 「玩家能否真的领到属性点」属于运行链路，由主场景启动后的 game_eval 覆盖。

## 生产等级系统脚本。
const PLAYER_LEVEL_SCRIPT: GDScript = preload("res://core/progression/player_level.gd")
## 生产等级系统脚本路径。
const PLAYER_LEVEL_GD: String = "res://core/progression/player_level.gd"
## 生产等级系统脚本的 uid 旁车路径。
const PLAYER_LEVEL_GD_UID_PATH: String = "res://core/progression/player_level.gd.uid"
## 项目配置路径，用于锁定 Autoload 注册。
const PROJECT_CONFIG_PATH: String = "res://project.godot"

## 必须逐字保留的规则常量；失败信息直接指出被改动的参数，便于快速定位数值漂移。
const REQUIRED_CONSTANTS: Array[String] = [
	"const SettingsSection: String = \"player\"",
	"const LevelKey: String = \"level\"",
	"const ExperienceKey: String = \"experience\"",
	"const PersistAcrossRuns: bool = false",
	"const MinLevel: int = 1",
	"const MaxLevel: int = 50",
	"const BaseExperienceRequirement: int = 100",
	"const ExperienceRequirementStep: int = 50",
	"const AttributePointsPerLevel: int = 3",
]

## 必须逐字保留的公开信号。
const REQUIRED_SIGNALS: Array[String] = [
	"signal LevelChanged(level: int)",
	"signal ExperienceChanged(current_experience: int, required_experience: int)",
	"signal AttributePointsGranted(pending_points: int)",
]

## 必须逐字保留的公开接口。
const REQUIRED_METHODS: Array[String] = [
	"func AddExperience(amount: int) -> int:",
	"func TryLevelUp() -> bool:",
	"func AddLevels(count: int) -> int:",
	"func GetLevel() -> int:",
	"func GetExperience() -> int:",
	"func GetExperienceToNextLevel() -> int:",
	"func GetExperienceRequirement(level: int) -> int:",
	"func IsMaxLevel() -> bool:",
	"func ClaimPendingAttributePoints() -> int:",
]


## 返回 GodotAI 使用的稳定套件名称。
## 返回值：等级系统契约套件名。
func suite_name() -> String:
	return "player_level_contract"


# ----- 形状与注册 -----

## 验证生产脚本存在、带 uid 旁车、不声明 class_name 且无 TODO 占位。
## 返回值：无。
func test_production_script_shape() -> void:
	assert_true(FileAccess.file_exists(PLAYER_LEVEL_GD), "生产脚本必须存在。")
	assert_true(FileAccess.file_exists(PLAYER_LEVEL_GD_UID_PATH), "生产脚本必须带 uid 旁车。")

	var text: String = FileAccess.get_file_as_string(PLAYER_LEVEL_GD)
	assert_true(text.begins_with("extends Node"), "等级系统 Autoload 必须直接继承 Node。")
	assert_false(_declares_class_name(text), "Autoload 脚本不得声明 class_name。")
	assert_false(text.contains("TODO"), "生产脚本不得保留 TODO 占位。")
	assert_true(text.contains("func _ready() -> void:"), "必须保留启动时读取存档的时机。")

	var uid_text: String = FileAccess.get_file_as_string(PLAYER_LEVEL_GD_UID_PATH).strip_edges()
	assert_true(uid_text.begins_with("uid://"), "uid 旁车必须声明 uid。")


## 验证规则常量、信号与接口全部逐字保留。
## 返回值：无。
func test_public_surface_is_locked() -> void:
	var text: String = FileAccess.get_file_as_string(PLAYER_LEVEL_GD)

	for literal: String in REQUIRED_CONSTANTS:
		assert_true(text.contains(literal), "必须保留规则常量：%s" % literal)

	for literal: String in REQUIRED_SIGNALS:
		assert_true(text.contains(literal), "必须保留公开信号：%s" % literal)

	for literal: String in REQUIRED_METHODS:
		assert_true(text.contains(literal), "必须保留公开接口：%s" % literal)


## 验证等级系统已在 project.godot 注册为 Autoload。
## 返回值：无。
func test_autoload_registered_in_project_config() -> void:
	var config: String = FileAccess.get_file_as_string(PROJECT_CONFIG_PATH)
	assert_true(config.contains("[autoload]"), "项目配置必须保留 Autoload 段。")
	assert_true(
		config.contains("PlayerLevel=\"*res://core/progression/player_level.gd\""),
		"PlayerLevel 必须以单例形式注册到 project.godot。"
	)
	# 依赖顺序：等级系统在 _ready 中访问 SettingsManager，必须注册在其之后。
	var settings_index: int = config.find("SettingsManager=\"*res://core/autoloads/SettingsManager.gd\"")
	var level_index: int = config.find("PlayerLevel=\"*res://core/progression/player_level.gd\"")
	assert_true(settings_index >= 0 and level_index > settings_index, "等级系统必须注册在 SettingsManager 之后。")


# ----- 规则行为 -----

## 验证新档初始状态与 1 级升级需求。
## 返回值：无。
func test_initial_state() -> void:
	var level: Node = _new_player_level()
	assert_eq(int(level.call("GetLevel")), 1, "初始等级必须为 1。")
	assert_eq(int(level.call("GetExperience")), 0, "初始经验必须为 0。")
	assert_eq(int(level.get("PendingAttributePoints")), 0, "初始不得有挂起属性点。")
	assert_false(bool(level.call("IsMaxLevel")), "初始不得处于满级。")
	assert_eq(int(level.call("GetExperienceToNextLevel")), 100, "1 级升到 2 级必须需要 100 经验。")


## 验证经验未达阈值时只累积、不升级。
## 返回值：无。
func test_experience_accumulates_until_requirement_is_met() -> void:
	var level: Node = _new_player_level()
	assert_eq(int(level.call("AddExperience", 99)), 99, "未满级时获得经验必须返回实际入账值。")
	assert_eq(int(level.call("GetLevel")), 1, "经验不足 100 时不得升级。")
	assert_eq(int(level.call("GetExperience")), 99, "经验必须原样累积。")

	assert_eq(int(level.call("AddExperience", 1)), 1, "补足差额的经验必须正常入账。")
	assert_eq(int(level.call("GetLevel")), 2, "经验达到 100 必须升级到 2 级。")
	assert_eq(int(level.call("GetExperience")), 0, "升级必须扣除本级需求，余量归零。")


## 验证单次获得经验可以连续升多级并保留余量。
## 返回值：无。
func test_single_call_can_level_up_multiple_times() -> void:
	var level: Node = _new_player_level()
	# 1 级持有 1050 经验：正好够连升 5 级（100+150+200+250+300=1000），余 50 留给第 6 级。
	assert_eq(int(level.call("AddExperience", 1050)), 1050, "一次大额经验必须全部入账。")
	assert_eq(int(level.call("GetLevel")), 6, "1050 经验必须从 1 级连升到 6 级。")
	assert_eq(int(level.call("GetExperience")), 50, "连升多级后必须保留不足以再升一级的余量。")


## 验证线性经验曲线在关键等级上的取值。
## 返回值：无。
func test_experience_curve() -> void:
	var level: Node = _new_player_level()
	# 曲线 = 100 + 50 * (等级 - 1)，逐点锁定以防止公式被改成指数曲线。
	assert_eq(int(level.call("GetExperienceRequirement", 1)), 100, "1 级需求必须为 100。")
	assert_eq(int(level.call("GetExperienceRequirement", 2)), 150, "2 级需求必须为 150。")
	assert_eq(int(level.call("GetExperienceRequirement", 3)), 200, "3 级需求必须为 200。")
	assert_eq(int(level.call("GetExperienceRequirement", 49)), 2500, "49 级需求必须为 2500。")
	assert_eq(int(level.call("GetExperienceRequirement", 50)), 0, "满级不得再有升级需求。")
	# 越界等级没有下一级，必须返回 0 而不是负数或异常值。
	assert_eq(int(level.call("GetExperienceRequirement", 0)), 0, "低于最低等级时必须返回 0。")
	assert_eq(int(level.call("GetExperienceRequirement", 51)), 0, "超过满级时必须返回 0。")

	level.set("Level", 49)
	assert_eq(int(level.call("GetExperienceToNextLevel")), 2500, "GetExperienceToNextLevel 必须跟随当前等级。")


## 验证满级封顶：等级不再提升、经验不再累积、接口返回 0。
## 返回值：无。
func test_max_level_caps_progress() -> void:
	var level: Node = _new_player_level()
	assert_eq(int(level.call("AddLevels", 999)), 49, "从 1 级直接提升必须收窄到满级，返回 49。")
	assert_eq(int(level.call("GetLevel")), 50, "提升后必须正好是满级。")
	assert_true(bool(level.call("IsMaxLevel")), "50 级必须判定为满级。")
	assert_eq(int(level.call("GetExperience")), 0, "满级后不得保留本级经验。")
	assert_eq(int(level.call("GetExperienceToNextLevel")), 0, "满级不得再有升级需求。")

	assert_eq(int(level.call("AddExperience", 100)), 0, "满级后获得经验必须返回 0。")
	assert_eq(int(level.call("GetLevel")), 50, "满级后等级不得变化。")
	assert_eq(int(level.call("GetExperience")), 0, "满级后经验不得累积。")
	assert_false(bool(level.call("TryLevelUp")), "满级时 TryLevelUp 必须失败。")
	assert_eq(int(level.call("AddLevels", 1)), 0, "满级时 AddLevels 必须返回 0。")


## 验证非正数输入被忽略且不改动任何数值。
## 返回值：无。
func test_non_positive_inputs_are_ignored() -> void:
	var level: Node = _new_player_level()
	assert_eq(int(level.call("AddExperience", 0)), 0, "零经验必须返回 0。")
	assert_eq(int(level.call("AddExperience", -5)), 0, "负经验必须返回 0。")
	assert_eq(int(level.call("AddLevels", 0)), 0, "零级提升必须返回 0。")
	assert_eq(int(level.call("AddLevels", -3)), 0, "负级提升必须返回 0。")
	assert_eq(int(level.call("GetLevel")), 1, "非法输入不得改变等级。")
	assert_eq(int(level.call("GetExperience")), 0, "非法输入不得改变经验。")
	assert_eq(int(level.get("PendingAttributePoints")), 0, "非法输入不得发放属性点。")


## 验证 TryLevelUp 只在经验足够时消耗经验升级。
## 返回值：无。
func test_try_level_up_requires_enough_experience() -> void:
	var level: Node = _new_player_level()
	assert_false(bool(level.call("TryLevelUp")), "零经验时不得升级。")

	# 直接构造「差一点」的边界状态，绕开 AddExperience 的自动升级。
	level.set("CurrentExperience", 99)
	assert_false(bool(level.call("TryLevelUp")), "经验差 1 点时不得升级。")
	assert_eq(int(level.call("GetExperience")), 99, "升级失败不得扣除经验。")

	level.set("CurrentExperience", 100)
	assert_true(bool(level.call("TryLevelUp")), "经验恰好达标时必须升级。")
	assert_eq(int(level.call("GetLevel")), 2, "升级后等级必须 +1。")
	assert_eq(int(level.call("GetExperience")), 0, "升级必须扣除本级需求。")


# ----- 属性点 -----

## 验证每级发放固定属性点，领取后清零且可重复领取。
## 返回值：无。
func test_attribute_points_are_granted_and_claimable() -> void:
	var level: Node = _new_player_level()
	assert_eq(int(level.call("ClaimPendingAttributePoints")), 0, "未升级时领取必须返回 0。")

	assert_eq(int(level.call("AddLevels", 1)), 1, "直接提升一级必须成功。")
	assert_eq(int(level.get("PendingAttributePoints")), 3, "每提升一级必须挂起 3 点属性点。")
	assert_eq(int(level.call("ClaimPendingAttributePoints")), 3, "领取必须返回全部挂起点数。")
	assert_eq(int(level.get("PendingAttributePoints")), 0, "领取后挂起点数必须清零。")
	assert_eq(int(level.call("ClaimPendingAttributePoints")), 0, "重复领取必须返回 0。")

	assert_eq(int(level.call("AddLevels", 2)), 2, "直接提升两级必须成功。")
	assert_eq(int(level.call("ClaimPendingAttributePoints")), 6, "连升两级必须累计挂起 6 点。")

	# 通过经验升级同样必须发放属性点。
	level.set("CurrentExperience", int(level.call("GetExperienceToNextLevel")))
	assert_true(bool(level.call("TryLevelUp")), "经验升级必须成功。")
	assert_eq(int(level.call("ClaimPendingAttributePoints")), 3, "经验升级同样必须发放属性点。")


# ----- 信号契约 -----

## 验证三个信号在单级升级时的触发次数与载荷。
## 返回值：无。
func test_signals_on_single_level_up() -> void:
	var level: Node = _new_player_level()
	# 逐级收集三类信号载荷，避免只断言次数而漏掉参数错误。
	var levels: Array = []
	var experiences: Array = []
	var points: Array = []
	level.connect("LevelChanged", func(new_level: int) -> void: levels.append(new_level))
	level.connect(
		"ExperienceChanged",
		func(current: int, required: int) -> void: experiences.append([current, required])
	)
	level.connect("AttributePointsGranted", func(pending: int) -> void: points.append(pending))

	level.call("AddExperience", 100)
	assert_eq(levels, [2], "升一级必须只发出一次 LevelChanged，且携带新等级。")
	assert_eq(experiences, [[0, 150]], "升级后必须发出 ExperienceChanged，携带归零经验与 2 级需求。")
	assert_eq(points, [3], "升级后必须发出 AttributePointsGranted，携带挂起总数 3。")


## 验证一次连升多级时逐级发出 LevelChanged，而发点只汇总一次。
## 返回值：无。
func test_signals_on_multi_level_up() -> void:
	var level: Node = _new_player_level()
	# 逐级收集等级信号，用于断言连升的每一次提升都被播报。
	var levels: Array = []
	# 汇总收集发点信号，用于断言一次结算只播报一次总数。
	var points: Array = []
	level.connect("LevelChanged", func(new_level: int) -> void: levels.append(new_level))
	level.connect("AttributePointsGranted", func(pending: int) -> void: points.append(pending))

	level.call("AddExperience", 1050)
	assert_eq(levels, [2, 3, 4, 5, 6], "连升 5 级必须逐级发出 LevelChanged。")
	assert_eq(points, [15], "一次结算只应发出一次 AttributePointsGranted，携带累计 15 点。")


# ----- 辅助 -----

## 构造一个不进入场景树的等级系统实例。
##
## 刻意不调用 add_child：这样 _ready 不会执行，实例不会去解析 SettingsManager 或读取本地存档，
## 断言结果因此不受运行环境影响。
##
## 返回类型固定为 Node：等级系统脚本未声明 class_name，因此脚本自定义的信号与字段一律用
## 字符串形式的 connect / call / get 动态协议访问，而不是点号属性访问。这样既绕开了
## 「从 Variant 推断类型」的报错，也不依赖脚本类型在编译期可见。
##
## 返回值：已纳入测试释放跟踪的 PlayerLevel 实例。
func _new_player_level() -> Node:
	return track(PLAYER_LEVEL_SCRIPT.new()) as Node


## 判断脚本全文是否声明了 class_name。
## 参数 text GDScript 全文。
## 返回值：声明了 class_name 时返回 true。
func _declares_class_name(text: String) -> bool:
	for raw_line: String in text.split("\n"):
		if raw_line.strip_edges().begins_with("class_name"):
			return true

	return false
