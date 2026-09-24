@tool
extends McpTestSuite

## 跨运行存档系统的契约套件。
##
## 套件锁定五件事：
## 1）**形状与装配顺序**：`SaveManager` 是 `[autoload]` 第一项且排在全部参与者之前。
##    这条顺序不是风格问题：参与者在自己 `_ready()` 里注册时会**同步**拿到存档，顺序被改就会
##    退化成延迟分发，`Main.tscn` 的 `RunStartInitializer` 会在存档生效前消费掉带入栏。
## 2）**协议校验**：缺方法的参与者被拒绝注册，而不是等到关窗存档时才发现少了个方法。
## 3）**编解码**：物品身份、数量、洗炼属性、槽位序号逐一往返；`null` 空槽位、
##    未知物品、脏洗炼属性键这三种情况必须能分辨，且都不让整档作废。
## 4）**文件层**：版本不符 / 非法 JSON / `data` 非字典一律回退默认值并保留现场；
##    主档坏了要能从 `.bak` 恢复；写入必须原子（不残留 `.tmp`、`.bak` 等于上一版）。
## 5）**自动存档**：防抖只写一次、分发期间不产生回声落盘、`run` 作用域不落进跨运行文件。
##
## 编辑器侧只跑纯行为：夹具刻意**不加入场景树**，因此不触发 `_ready`、也不解析任何 autoload
## （`test_run` 环境没有 autoload）。`SaveManager` 的读盘用公开的 `load_from_disk()` 显式驱动。
## 「真实游戏里读档是否早于开局带入」属于运行时序，由主场景启动后的 `game_eval` 覆盖。

## 存档层生产脚本。
const SAVE_MANAGER_SCRIPT: GDScript = preload("res://core/save/save_manager.gd")
## 存档层生产脚本路径。
const SAVE_MANAGER_PATH: String = "res://core/save/save_manager.gd"
## 槽位编解码生产脚本。
const SAVE_SLOT_CODEC: GDScript = preload("res://core/save/save_slot_codec.gd")
## 槽位编解码生产脚本路径。
const SAVE_SLOT_CODEC_PATH: String = "res://core/save/save_slot_codec.gd"
## 仓库参与者生产脚本。
const WAREHOUSE_COMPONENT_SCRIPT: GDScript = preload(
	"res://entities/components/warehouse_inventory_component.gd"
)
## 仓库参与者生产脚本路径。
const WAREHOUSE_COMPONENT_PATH: String = "res://entities/components/warehouse_inventory_component.gd"
## 带入栏参与者生产脚本。
const ITEMS_CONTROL_SCRIPT: GDScript = preload("res://core/autoloads/ItemsControl.gd")
## 带入栏参与者生产脚本路径。
const ITEMS_CONTROL_PATH: String = "res://core/autoloads/ItemsControl.gd"
## 钱包参与者生产脚本。
const PLAYER_WALLET_SCRIPT: GDScript = preload("res://core/autoloads/player_wallet.gd")
## 钱包参与者生产脚本路径。
const PLAYER_WALLET_PATH: String = "res://core/autoloads/player_wallet.gd"
## 容量升级参与者生产脚本。
const PLAYER_PROGRESSION_SCRIPT: GDScript = preload("res://core/progression/player_progression.gd")
## 容量升级参与者生产脚本路径。
const PLAYER_PROGRESSION_PATH: String = "res://core/progression/player_progression.gd"
## 物品堆叠生产脚本，用于构造编解码夹具。
const ITEM_STACK_SCRIPT: GDScript = preload("res://resources/item/item_stack.gd")
## 项目配置路径。
const PROJECT_CONFIG_PATH: String = "res://project.godot"

## 测试专用存档目录；绝不指向真实存档，避免测试覆盖玩家进度。
const TEST_SAVE_DIRECTORY: String = "user://test_save_system"
## 测试专用存档主文件。
const TEST_SAVE_PATH: String = "user://test_save_system/game_save.json"

## 参与者必须实现的完整协议方法；与 SaveManager.PARTICIPANT_METHODS 同值。
const REQUIRED_PROTOCOL_METHODS: Array[String] = [
	"save_key",
	"save_scope",
	"save_change_signals",
	"capture_save_data",
	"apply_save_data",
]

## 存档全部产物后缀，用于清理与断言。
const ALL_SUFFIXES: Array[String] = ["", ".bak", ".tmp", ".corrupt"]


## 档位桩：只实现存档协议，不实现任何玩法规则。
##
## 之所以能用桩：存档层与玩法之间唯一的边就是这 5 个方法 + 声明的信号，桩能覆盖这条边的
## 全部行为（注册、采集、分发、回声抑制、作用域分流）。
class StubParticipant extends Node:
	## 用于验证「分发期间的变更信号不会触发落盘」。
	signal stub_changed(amount: int)

	## `save_key()` 返回值。
	var Key: String = "stub"
	## `save_scope()` 返回值。
	var Scope: String = "global"
	## `save_change_signals()` 返回值。
	var DeclaredSignals: Array = []
	## 被采集的状态。
	var State: Dictionary = {}
	## `apply_save_data()` 被调用的次数。
	var ApplyCount: int = 0
	## 最近一次 `apply_save_data()` 收到的载荷。
	var LastPayload: Dictionary = {}
	## 置位时 `apply_save_data()` 返回 false，用于验证分发失败的诊断。
	var RejectApply: bool = false
	## 置位时 `apply_save_data()` 会发出自己的变更信号，用于验证回声抑制。
	var EmitOnApply: bool = false

	func save_key() -> String:
		return Key

	func save_scope() -> String:
		return Scope

	func save_change_signals() -> Array:
		return DeclaredSignals

	func capture_save_data() -> Dictionary:
		return State.duplicate(true)

	## 用载荷**替换**自身状态（不等价于增量合并），与真实参与者的「先清空再写入」一致。
	func apply_save_data(data: Dictionary) -> bool:
		ApplyCount += 1
		LastPayload = data.duplicate(true)
		if RejectApply:
			return false
		State = data.duplicate(true)
		if EmitOnApply:
			stub_changed.emit(1)
		return true


## 缺方法的参与者桩：用于验证注册期协议校验。
class IncompleteParticipant extends Node:
	func save_key() -> String:
		return "incomplete"


## 带 `save_scope()` 返回非法值的参与者桩。
class BadScopeParticipant extends Node:
	func save_key() -> String:
		return "bad_scope"

	func save_scope() -> String:
		return "nowhere"

	func save_change_signals() -> Array:
		return []

	func capture_save_data() -> Dictionary:
		return {}

	func apply_save_data(_data: Dictionary) -> bool:
		return true


## 物品夹具：具备 `ItemData` 协议的最小字段集合，另带 `AttributeBonuses` 供洗炼属性白名单使用。
class StubItem extends Resource:
	@export var CardId: StringName = &""
	@export var CardName: String = ""
	@export var MaxStackSize: int = 99
	@export var ItemTags: Array[StringName] = []
	@export var BuyPrice: int = 0
	@export var SellPrice: int = 0
	@export var AttributeBonuses: Dictionary = {}


## 清理测试目录，避免上一次运行的残留影响本轮。
##
## @param _ctx 运行上下文，未使用。
## @return 无返回值。
func suite_setup(_ctx: Dictionary) -> void:
	_cleanup_test_files()


## 每个用例开跑前清理一次。
##
## 为什么必须逐用例清理而不是只在套件级清理一次：多个用例共用同一个临时路径，
## 前一个用例写下的存档会让后一个用例的「无存档」前置条件失效——那是最容易掩盖真问题的
## 假通过（也会让「首次写入不得产生备份」这类断言失去意义）。
##
## @return 无返回值。
func setup() -> void:
	_cleanup_test_files()


## 清理测试目录，避免把夹具留在用户存档目录里。
##
## @return 无返回值。
func suite_teardown() -> void:
	_cleanup_test_files()


## 本套件名；必须与转发壳文件名一致，便于按 suite 名单独运行。
##
## @return 套件名。
func suite_name() -> String:
	return "save_system_contract"


# ----- 组 1：形状与装配顺序 -----

## 验证生产脚本、uid 旁车与「不注册全局类名」。
##
## @return 无返回值。
func test_production_scripts_exist_with_uid_sidecars() -> void:
	for path: String in [SAVE_MANAGER_PATH, SAVE_SLOT_CODEC_PATH]:
		assert_true(FileAccess.file_exists(path), "生产脚本必须存在：%s" % path)
		assert_true(FileAccess.file_exists(path + ".uid"), "%s 必须带 uid 旁车。" % path)
		assert_eq(
			_registered_global_class_names(path),
			[] as Array[String],
			"%s 不得注册 class_name：项目里同名全局类型会与迁移期垫片冲突。" % path
		)


## 验证 `SaveManager` 是 `[autoload]` 第一项，且排在全部参与者之前。
##
## @return 无返回值。
func test_save_manager_is_first_autoload_before_participants() -> void:
	var order: Array[String] = _read_autoload_order()
	assert_gt(order.size(), 0, "project.godot 必须保留 [autoload] 段。")
	if order.is_empty():
		return

	assert_eq(order[0], "SaveManager", "[autoload] 第一项必须是 SaveManager。")
	assert_eq(
		_resolve_autoload_path("SaveManager"),
		SAVE_MANAGER_PATH,
		"SaveManager 必须指向存档层生产脚本。"
	)

	var manager_index: int = order.find("SaveManager")
	for participant_name: String in [
		"GlobalEventBus",
		"ItemsControl",
		"GlobalWarehouse",
		"PlayerProgression",
		"PlayerWallet",
	]:
		var participant_index: int = order.find(participant_name)
		assert_gt(participant_index, -1, "%s 必须仍然注册为 Autoload。" % participant_name)
		assert_true(
			manager_index >= 0 and manager_index < participant_index,
			"SaveManager 必须注册在 %s 之前：注册即应用依赖它先于参与者就绪。" % participant_name
		)


## 验证四个参与者脚本都实现了完整的存档协议。
##
## @return 无返回值。
func test_participants_implement_full_protocol() -> void:
	# 作用域期望值直接取自存档层的常量，锁定「参与者字面量与 SaveManager 常量同值」。
	# 参与者刻意不引用该常量（那会让 test_run 环境解析失败），因此这条同值关系只能靠断言保证。
	var expected_scope: String = String(
		SAVE_MANAGER_SCRIPT.get_script_constant_map()["SCOPE_GLOBAL"]
	)
	var expected_methods: Array = SAVE_MANAGER_SCRIPT.get_script_constant_map()["PARTICIPANT_METHODS"]
	assert_eq(
		expected_methods,
		REQUIRED_PROTOCOL_METHODS,
		"本套件维护的协议方法表必须与 SaveManager.PARTICIPANT_METHODS 同值。"
	)

	for entry: Array in [
		[WAREHOUSE_COMPONENT_SCRIPT, "warehouse"],
		[ITEMS_CONTROL_SCRIPT, "carry"],
		[PLAYER_WALLET_SCRIPT, "player_wallet"],
		[PLAYER_PROGRESSION_SCRIPT, "player_progression"],
	]:
		var script: GDScript = entry[0]
		var expected_key: String = entry[1]

		var instance: Node = script.new()
		track(instance)
		for method_name: String in REQUIRED_PROTOCOL_METHODS:
			assert_true(
				instance.has_method(method_name),
				"%s 必须实现存档协议方法 %s。" % [expected_key, method_name]
			)
		assert_eq(
			String(instance.call("save_key")),
			expected_key,
			"参与者的存档键必须稳定为 %s。" % expected_key
		)
		assert_eq(
			String(instance.call("save_scope")),
			expected_scope,
			"%s 必须声明局外作用域。" % expected_key
		)


# ----- 组 2：协议校验 -----

## 验证缺方法的参与者被拒绝注册且不进入注册表。
##
## @return 无返回值。
func test_register_rejects_incomplete_participant() -> void:
	var manager: Node = _new_manager()
	var incomplete: Node = IncompleteParticipant.new()
	track(incomplete)

	assert_false(
		bool(manager.call("register_participant", incomplete)),
		"缺少协议方法的参与者必须被拒绝注册。"
	)
	assert_false(
		bool(manager.call("is_registered", "incomplete")),
		"被拒绝的参与者不得进入注册表。"
	)
	assert_eq(
		manager.call("get_registered_keys"),
		[] as Array[String],
		"注册表必须保持为空。"
	)


## 验证非法作用域的参与者被拒绝注册。
##
## @return 无返回值。
func test_register_rejects_unknown_scope() -> void:
	var manager: Node = _new_manager()
	var bad_scope: Node = BadScopeParticipant.new()
	track(bad_scope)

	assert_false(
		bool(manager.call("register_participant", bad_scope)),
		"save_scope() 只接受 global / run，其它值必须被拒绝。"
	)


## 验证同一存档键被重复注册时旧参与者被替换，且旧参与者声明的信号被断开。
##
## 为什么值得单独一条：这条路径是为「每局重建的 run 参与者」预留的——新一局会创建新实例并用
## 同一个键重新注册。如果旧实例的信号没被断开，上一局的残影参与者会继续把落盘请求打进来；
## 它已经不在注册表里，采集时被忽略、请求却照发，表现为「什么都没改却一直在写盘」。
##
## @return 无返回值。
func test_duplicate_key_replaces_participant_and_detaches_old_signals() -> void:
	var manager: Node = _new_manager()
	var first: Node = _make_stub("dup", "global", {"value": 1})
	first.set("DeclaredSignals", ["stub_changed"])
	assert_true(bool(manager.call("register_participant", first)), "第一次注册必须成功。")

	var second: Node = _make_stub("dup", "global", {"value": 2})
	second.set("DeclaredSignals", ["stub_changed"])
	assert_true(
		bool(manager.call("register_participant", second)),
		"同键重复注册必须被接受（替换语义）。"
	)
	assert_eq(
		manager.call("get_registered_keys"),
		["dup"] as Array[String],
		"同键重复注册不得在注册表里留下两个条目。"
	)

	# 分发只应到达新参与者。
	assert_true(bool(manager.call("apply", {"global": {"dup": {"value": 9}}})), "应用必须成功。")
	assert_eq(int(second.get("ApplyCount")), 2, "新参与者必须收到注册补发与显式 apply。")
	assert_eq(
		int(first.get("ApplyCount")),
		1,
		"旧参与者不得再收到分发（只保留它自己注册时那一次）。"
	)

	# 旧信号必须已经断开：它不再能产生落盘请求。
	manager.set("_dirty", false)
	first.emit_signal("stub_changed", 1)
	assert_false(bool(manager.get("_dirty")), "旧参与者声明的信号必须已被断开。")
	second.emit_signal("stub_changed", 1)
	assert_true(bool(manager.get("_dirty")), "新参与者的信号必须仍然连着。")


# ----- 组 3：编解码 -----

## 验证槽位编解码往返：物品身份、数量、洗炼属性、槽位序号与空槽位。
##
## @return 无返回值。
func test_slot_codec_round_trip() -> void:
	var catalog: Dictionary = _build_catalog()
	var lookup: Callable = _build_lookup(catalog)
	var sword: Resource = catalog[&"iron_sword"]

	var stacks: Array = []
	var occupied: RefCounted = ITEM_STACK_SCRIPT.new()
	occupied.call("SetItem", sword, 2)
	# 洗炼属性必须在 SetItem 之后写入：SetItem 语义上会清空 RolledAttributes（与生产水合顺序一致）。
	var rolled: Dictionary = occupied.get("RolledAttributes")
	rolled[0] = 15
	rolled[4] = 7
	stacks.append(occupied)
	stacks.append(ITEM_STACK_SCRIPT.new())
	var tail: RefCounted = ITEM_STACK_SCRIPT.new()
	tail.call("SetItem", catalog[&"wood_01"], 3)
	stacks.append(tail)

	var entries: Array = []
	for stack: Variant in stacks:
		entries.append(SAVE_SLOT_CODEC.call("stack_to_entry", stack))
	var encoded: Array = SAVE_SLOT_CODEC.call("encode_slots", entries)

	assert_eq(encoded.size(), 3, "编码后的槽位数量必须与输入一致。")
	assert_eq(
		(encoded[0] as Dictionary).get("card_id"),
		"iron_sword",
		"物品身份只落 CardId。"
	)
	assert_eq((encoded[0] as Dictionary).get("amount"), 2, "数量必须落盘。")
	_assert_dict_eq(
		(encoded[0] as Dictionary).get("rolled"),
		{"0": 15, "4": 7},
		"洗炼属性必须以字符串化的属性枚举为键落盘"
	)
	assert_eq(encoded[1], null, "空槽位必须编码为 null，且不省略下标。")
	assert_eq((encoded[2] as Dictionary).get("card_id"), "wood_01", "槽位顺序必须保持。")

	var decoded: Dictionary = SAVE_SLOT_CODEC.call("decode_slots", encoded, 3, lookup)
	assert_true(bool(decoded.get("ok")), "结构完整的槽位数组必须解码成功。")
	assert_eq(int(decoded.get("skipped")), 0, "正常存档不得有被跳过的槽位。")
	_assert_decoded_entry(decoded, 0, "ok", sword, 2, {0: 15, 4: 7})
	assert_eq(
		String(((decoded.get("entries") as Array)[1] as Dictionary).get("status")),
		"empty",
		"null 槽位必须解码为 empty，而不是 skipped。"
	)
	_assert_decoded_entry(decoded, 2, "ok", catalog[&"wood_01"], 3, {})


## 验证未知物品只跳过该槽位、计数加一，其余槽位照常水合。
##
## @return 无返回值。
func test_decode_skips_unknown_item_without_failing_document() -> void:
	var catalog: Dictionary = _build_catalog()
	var lookup: Callable = _build_lookup(catalog)
	var saved_slots: Array = [
		{"card_id": "wood_01", "amount": 1},
		{"card_id": "deleted_item", "amount": 5},
		null,
	]

	var decoded: Dictionary = SAVE_SLOT_CODEC.call("decode_slots", saved_slots, 3, lookup)
	assert_true(bool(decoded.get("ok")), "个别物品缺失不得让整份槽位数组作废。")
	assert_eq(int(decoded.get("skipped")), 1, "未知物品必须计入跳过数。")
	_assert_decoded_entry(decoded, 0, "ok", catalog[&"wood_01"], 1, {})
	assert_eq(
		String(((decoded.get("entries") as Array)[1] as Dictionary).get("status")),
		"skipped",
		"未知物品的槽位必须标记为 skipped。"
	)
	assert_contains(
		String(((decoded.get("entries") as Array)[1] as Dictionary).get("reason")),
		"deleted_item",
		"跳过原因必须带上无法解析的 card_id，便于诊断。"
	)
	assert_eq(
		String(((decoded.get("entries") as Array)[2] as Dictionary).get("status")),
		"empty",
		"合法空槽位仍必须解码为 empty。"
	)


## 验证洗炼属性校验：声明了 `AttributeBonuses` 的物品按声明求交集，未声明的只做类型校验。
##
## 这条区分是 2026-09-24 运行期验证后收紧的：原先无条件求交集，导致普通物品（没有
## `AttributeBonuses`）上的洗炼属性被**全部销毁**。「无法判断」不等于「非法」——类型歧义
## 已经由「整型键解析 + 数值校验」覆盖，白名单只应在真的能判断时才生效。
##
## @return 无返回值。
func test_decode_scopes_rolled_keys_by_declared_bonuses() -> void:
	var catalog: Dictionary = _build_catalog()
	var lookup: Callable = _build_lookup(catalog)
	var saved_slots: Array = [
		{"card_id": "iron_sword", "amount": 1, "rolled": {"0": 12, "9": 99, "bad": 3, "4": "x"}},
		{"card_id": "wood_01", "amount": 2, "rolled": {"0": 5, "2": 8, "bad": 1}},
	]

	var decoded: Dictionary = SAVE_SLOT_CODEC.call("decode_slots", saved_slots, 2, lookup)
	assert_true(bool(decoded.get("ok")), "脏洗炼属性不得让整份槽位数组作废。")

	# 铁剑声明了 {0, 4}：0 合法；9 不在声明内；"bad" 不是整数键；4 的值不是数值。
	_assert_dict_eq(
		((decoded.get("entries") as Array)[0] as Dictionary).get("rolled"),
		{0: 12},
		"声明了 AttributeBonuses 的物品必须按声明求交集"
	)
	assert_eq(
		int(((decoded.get("entries") as Array)[0] as Dictionary).get("rolled_dropped")),
		3,
		"被丢弃的洗炼属性键必须计数（9 / bad / 4）"
	)
	# 普通物品没有 AttributeBonuses：没有可依据的白名单，因此保留合法的整数键，只丢 "bad"。
	_assert_dict_eq(
		((decoded.get("entries") as Array)[1] as Dictionary).get("rolled"),
		{0: 5, 2: 8},
		"未声明 AttributeBonuses 的物品不得被销毁洗炼属性"
	)
	assert_eq(
		int(decoded.get("rolled_dropped")),
		4,
		"累计丢弃数必须包含普通物品上那个非整数键。"
	)


## 验证存档槽位数多于当前容量时不截断，交回调用方扩容。
##
## @return 无返回值。
func test_decode_slots_never_truncates_extra_saved_slots() -> void:
	var catalog: Dictionary = _build_catalog()
	var lookup: Callable = _build_lookup(catalog)
	var saved_slots: Array = []
	for index: int in 5:
		saved_slots.append({"card_id": "wood_01", "amount": index + 1})

	var decoded: Dictionary = SAVE_SLOT_CODEC.call("decode_slots", saved_slots, 2, lookup)
	assert_eq(
		(decoded.get("entries") as Array).size(),
		5,
		"存档槽位数多于当前容量时必须全部解码，由调用方扩容，否则会静默丢物品。"
	)
	assert_eq(
		int(((decoded.get("entries") as Array)[4] as Dictionary).get("amount")),
		5,
		"高序号槽位的内容必须保留。"
	)


## 验证非数组的 slots 被判定为结构不可用。
##
## @return 无返回值。
func test_decode_slots_rejects_non_array_structure() -> void:
	var decoded: Dictionary = SAVE_SLOT_CODEC.call("decode_slots", {"nope": 1}, 3, Callable())
	assert_false(bool(decoded.get("ok")), "slots 不是数组时结构必须判定为不可用。")
	assert_gt(
		(decoded.get("reasons") as Array).size(),
		0,
		"结构不可用时必须给出可诊断原因。"
	)


# ----- 组 4：文件层 -----

## 验证文件不存在时以默认值启动。
##
## @return 无返回值。
func test_missing_save_file_yields_defaults() -> void:
	var manager: Node = _new_manager()
	assert_false(bool(manager.call("has_save")), "无存档文件时 has_save() 必须为 false。")
	assert_eq(
		String(manager.call("get_last_load_error")),
		"",
		"没有存档不算错误，不得留下失败原因。"
	)

	var wallet: Node = PLAYER_WALLET_SCRIPT.new()
	track(wallet)
	manager.call("register_participant", wallet)
	assert_eq(
		int(wallet.get("Gold")),
		int(PLAYER_WALLET_SCRIPT.get_script_constant_map()["DefaultGold"]),
		"无存档时钱包必须保持默认金币。"
	)


## 验证非法 JSON 回退默认值并保留损坏现场。
##
## @return 无返回值。
func test_corrupt_json_falls_back_and_preserves_corrupt_file() -> void:
	_write_text(TEST_SAVE_PATH, "{ this is not json")

	var manager: Node = _new_manager()
	assert_false(bool(manager.call("has_save")), "非法 JSON 必须回退默认值。")
	assert_gt(
		String(manager.call("get_last_load_error")).length(),
		0,
		"非法 JSON 必须留下可诊断的失败原因。"
	)
	assert_eq(
		_read_text(String(manager.call("get_corrupt_file_path"))),
		"{ this is not json",
		"损坏内容必须原样保留为 .corrupt，供人工排查。"
	)
	assert_false(
		FileAccess.file_exists(TEST_SAVE_PATH + ".bak"),
		"损坏内容绝不能被写进 .bak——那会毁掉唯一的自动恢复来源。"
	)


## 验证版本不符被判定为无法读取。
##
## @return 无返回值。
func test_version_mismatch_is_rejected() -> void:
	var version: int = int(SAVE_MANAGER_SCRIPT.get_script_constant_map()["FORMAT_VERSION"])
	_write_text(
		TEST_SAVE_PATH,
		JSON.stringify({
			"format_version": version + 1,
			"data": {"global": {}, "run": {}},
		})
	)

	var manager: Node = _new_manager()
	assert_false(bool(manager.call("has_save")), "版本不符必须回退默认值。")
	assert_contains(
		String(manager.call("get_last_load_error")),
		"format_version",
		"失败原因必须点明是版本问题。"
	)


## 验证 `data` 不是字典时被判定为损坏。
##
## @return 无返回值。
func test_non_dictionary_data_is_rejected() -> void:
	var version: int = int(SAVE_MANAGER_SCRIPT.get_script_constant_map()["FORMAT_VERSION"])
	_write_text(
		TEST_SAVE_PATH,
		JSON.stringify({"format_version": version, "data": []})
	)

	var manager: Node = _new_manager()
	assert_false(bool(manager.call("has_save")), "data 不是对象时必须回退默认值。")
	assert_contains(
		String(manager.call("get_last_load_error")),
		"data",
		"失败原因必须点明是 data 结构问题。"
	)


## 验证主档损坏时能从 `.bak` 恢复。
##
## @return 无返回值。
func test_recovers_from_backup_when_primary_is_corrupt() -> void:
	_write_text(TEST_SAVE_PATH, _valid_document({"player_wallet": {"gold": 777}}))
	_write_text(TEST_SAVE_PATH + ".bak", _valid_document({"player_wallet": {"gold": 777}}))
	_write_text(TEST_SAVE_PATH, "corrupted beyond repair")

	var manager: Node = _new_manager()
	assert_true(bool(manager.call("has_save")), "主档损坏但 .bak 有效时必须恢复成功。")
	var loaded: Dictionary = manager.call("get_loaded_data")
	var global_data: Dictionary = loaded.get("global", {}) as Dictionary
	_assert_dict_eq(
		global_data.get("player_wallet"),
		{"gold": 777},
		"恢复出来的进度必须等于 .bak 的内容"
	)


## 验证 `erase_save()` 清掉全部四种产物并把内存状态复位。
##
## 为什么值得单独一条：`erase_save()` 是本任务唯一的清档入口（玩家没有存档 UI），也是交付说明里
## 推荐的复位手段。漏删任何一种产物都会让「清档」变成半成品——例如留下 `.bak`，下一次启动会
## 直接从备份里把刚清掉的进度恢复回来，玩家看到的仍是旧存档。
##
## @return 无返回值。
func test_erase_save_removes_every_artifact_and_resets_state() -> void:
	var manager: Node = _new_manager()
	_register_stub(manager, "erase", "global", {"value": 1})

	assert_true(bool(manager.call("save_now")), "首次写入必须成功。")
	assert_true(bool(manager.call("save_now")), "第二次写入必须成功，以便产生 .bak。")
	# `.corrupt` 与 `.tmp` 在正常流程里不会与主档同时存在，这里手工造出来覆盖删除路径。
	_write_text(String(manager.call("get_corrupt_file_path")), "{ 损坏 }")
	_write_text(String(manager.call("get_temp_file_path")), "partial")

	for suffix: String in ALL_SUFFIXES:
		assert_true(
			FileAccess.file_exists(TEST_SAVE_PATH + suffix),
			"前置条件：%s 必须存在。" % (TEST_SAVE_PATH + suffix)
		)

	assert_true(bool(manager.call("erase_save")), "清档必须报告全部产物删除成功。")
	for suffix: String in ALL_SUFFIXES:
		assert_false(
			FileAccess.file_exists(TEST_SAVE_PATH + suffix),
			"清档后不得残留 %s。" % (TEST_SAVE_PATH + suffix)
		)
	assert_false(bool(manager.call("has_save")), "清档后 has_save() 必须为 false。")
	_assert_dict_eq(
		manager.call("get_loaded_data"),
		{"global": {}, "run": {}},
		"清档后内存存档必须复位为空作用域"
	)


# ----- 组 5：自动存档 -----

## 验证原子写入：首次写入无 `.bak`，第二次起 `.bak` 等于上一版，且不残留 `.tmp`。
##
## @return 无返回值。
func test_atomic_write_keeps_previous_version_and_no_temp_file() -> void:
	var manager: Node = _new_manager()
	var participant: Node = _register_stub(manager, "atomic", "global", {"gold": 1})

	assert_true(bool(manager.call("save_now")), "首次写入必须成功。")
	assert_false(
		FileAccess.file_exists(TEST_SAVE_PATH + ".tmp"),
		"原子写入不得残留 .tmp。"
	)
	assert_false(
		FileAccess.file_exists(TEST_SAVE_PATH + ".bak"),
		"首次写入时没有旧档可备份。"
	)

	participant.set("State", {"gold": 2})
	assert_true(bool(manager.call("save_now")), "第二次写入必须成功。")
	_assert_dict_eq(
		_read_saved_global(TEST_SAVE_PATH + ".bak").get("atomic"),
		{"gold": 1},
		".bak 必须等于上一次成功写入的内容"
	)
	_assert_dict_eq(
		_read_saved_global(TEST_SAVE_PATH).get("atomic"),
		{"gold": 2},
		"主档必须等于最新内容"
	)
	assert_false(
		FileAccess.file_exists(TEST_SAVE_PATH + ".tmp"),
		"写入完成后不得残留 .tmp。"
	)

	participant.set("State", {"gold": 3})
	assert_true(bool(manager.call("save_now")), "第三次写入必须成功。")
	_assert_dict_eq(
		_read_saved_global(TEST_SAVE_PATH + ".bak").get("atomic"),
		{"gold": 2},
		".bak 必须滚动到上一版，而不是保留最早的一版"
	)


## 验证连续多次变更请求只产生一次写入（0.5 秒防抖）。
##
## @return 无返回值。
func test_debounce_collapses_burst_into_single_write() -> void:
	var manager: Node = _new_manager()
	_register_stub(manager, "debounce", "global", {"value": 1})

	manager.call("request_save")
	manager.call("request_save")
	manager.call("request_save")

	# 未到阈值：不得写入。
	manager.call("_process", 0.1)
	assert_eq(
		int(manager.call("get_successful_write_count")),
		0,
		"防抖阈值内的变更不得落盘。"
	)

	# 越过阈值：恰好一次。
	manager.call("_process", 0.5)
	assert_eq(
		int(manager.call("get_successful_write_count")),
		1,
		"三次连续请求必须合并成一次写入。"
	)

	# 无新变更：不得再写。
	manager.call("_process", 5.0)
	assert_eq(
		int(manager.call("get_successful_write_count")),
		1,
		"没有新变更时不得重复写入。"
	)


## 验证分发存档期间由参与者状态变化引发的信号不会触发回声落盘。
##
## @return 无返回值。
func test_applying_save_suppresses_echo_save_requests() -> void:
	var manager: Node = _new_manager()
	var participant: Node = _make_stub("echo", "global", {})
	participant.set("DeclaredSignals", ["stub_changed"])
	participant.set("EmitOnApply", true)
	manager.call("register_participant", participant)

	# 注册时就会补发一次（此时载荷为空）——它不应把 dirty 置位。
	assert_false(
		bool(manager.get("_dirty")),
		"注册即应用的补发不得请求落盘。"
	)

	manager.call("apply", {"global": {"echo": {"value": 9}}})
	assert_false(
		bool(manager.get("_dirty")),
		"分发存档期间参与者发出的变更信号必须被丢弃，否则会把刚读进来的文件原样重写。"
	)
	assert_eq(
		int(participant.get("ApplyCount")),
		2,
		"注册补发一次、显式 apply 一次。"
	)


## 验证两个作用域互不污染，且 `clear_run_scope()` 能把 run 参与者复位。
##
## 注意这里的正确期望：`run` 数据**会**写进存档文件——它是「本局进度」的落点，将来「继续
## 本局」要读它。跨运行不复用是靠新一局调用 `clear_run_scope()` 实现的，而不是靠不落盘。
## 因此要锁的不变量是「作用域分流」：局外的键不得出现在 `data.run`，局内的键也不得出现
## 在 `data.global`。
##
## @return 无返回值。
func test_scopes_are_split_and_run_scope_can_be_cleared() -> void:
	var manager: Node = _new_manager()
	var global_stub: Node = _register_stub(manager, "global_stub", "global", {"value": 1})
	var run_stub: Node = _register_stub(manager, "run_stub", "run", {"value": 2})

	assert_true(bool(manager.call("save_now")), "写入必须成功。")
	var document: Dictionary = _read_document(TEST_SAVE_PATH)
	var data: Dictionary = document.get("data", {}) as Dictionary
	var saved_global: Dictionary = data.get("global", {}) as Dictionary
	var saved_run: Dictionary = data.get("run", {}) as Dictionary

	assert_true(saved_global.has("global_stub"), "局外参与者的数据必须落进 data.global。")
	assert_false(saved_global.has("run_stub"), "局内参与者的键不得出现在 data.global 里。")
	assert_true(saved_run.has("run_stub"), "局内参与者的数据必须落进 data.run。")
	assert_false(saved_run.has("global_stub"), "局外参与者的键不得出现在 data.run 里。")

	manager.call("clear_run_scope")
	assert_eq(int(run_stub.get("ApplyCount")), 2, "清空 run 作用域必须把 run 参与者复位一次。")
	_assert_dict_eq(
		run_stub.get("LastPayload"),
		{},
		"复位载荷必须是空字典（语义为「没有存档」）"
	)
	assert_eq(
		int(global_stub.get("ApplyCount")),
		1,
		"清空 run 作用域不得触碰局外参与者。"
	)


## 验证同一份存档连续应用两次，参与者状态与只应用一次完全相同（幂等）。
##
## @return 无返回值。
func test_apply_is_idempotent() -> void:
	var manager: Node = _new_manager()
	var participant: Node = _register_stub(manager, "idem", "global", {"value": 1})

	var payload: Dictionary = {"global": {"idem": {"value": 42}}}
	assert_true(bool(manager.call("apply", payload)), "应用存档必须成功。")
	var after_first: Dictionary = (participant.get("State") as Dictionary).duplicate(true)

	assert_true(bool(manager.call("apply", payload)), "重复应用存档必须成功。")
	_assert_dict_eq(
		participant.get("State"),
		after_first,
		"重复应用同一份存档不得改变参与者状态"
	)
	_assert_dict_eq(after_first, {"value": 42}, "参与者必须真正拿到了存档内容")


## 验证参与者拒绝应用存档时被诊断为失败，而不是静默通过。
##
## @return 无返回值。
func test_rejected_application_is_reported_as_failure() -> void:
	var manager: Node = _new_manager()
	var participant: Node = _make_stub("reject", "global", {})
	participant.set("RejectApply", true)
	manager.call("register_participant", participant)

	assert_false(
		bool(manager.call("apply", {"global": {"reject": {"value": 1}}})),
		"参与者拒绝应用时整体结果必须为失败。"
	)


# ----- 组 6：真实参与者的往返 -----

## 验证仓库参与者「先清空再写入」的水合语义与洗炼属性往返。
##
## @return 无返回值。
func test_warehouse_participant_round_trip_clears_stale_slots() -> void:
	var catalog: Dictionary = _build_catalog()
	var lookup: Callable = _build_lookup(catalog)

	var source: Node = WAREHOUSE_COMPONENT_SCRIPT.new()
	track(source)
	source.set("Capacity", 4)
	source.set("SaveItemLookup", lookup)
	_place_stack(source, 0, catalog[&"wood_01"], 3)
	_place_stack(source, 2, catalog[&"iron_sword"], 1, {0: 11, 4: 4})
	var captured: Dictionary = source.call("capture_save_data")

	var target: Node = WAREHOUSE_COMPONENT_SCRIPT.new()
	track(target)
	target.set("Capacity", 4)
	target.set("SaveItemLookup", lookup)
	# 先塞入一批「上一局残留」，验证水合是先清空再写入，而不是叠加。
	_place_stack(target, 1, catalog[&"iron_sword"], 9)
	_place_stack(target, 3, catalog[&"wood_01"], 5)

	assert_true(bool(target.call("apply_save_data", captured)), "仓库必须成功应用存档。")
	_assert_stack_at(target, 0, catalog[&"wood_01"], 3, {})
	_assert_stack_at(target, 1, null, 0, {})
	_assert_stack_at(target, 2, catalog[&"iron_sword"], 1, {0: 11, 4: 4})
	_assert_stack_at(target, 3, null, 0, {})

	var recaptured: Dictionary = target.call("capture_save_data")
	_assert_dict_eq(recaptured, captured, "仓库采集 → 应用 → 再采集必须等价")


## 验证仓库参与者会为超出当前容量的存档槽位扩容，且容量只增不减。
##
## @return 无返回值。
func test_warehouse_participant_grows_capacity_for_oversized_save() -> void:
	var catalog: Dictionary = _build_catalog()
	var lookup: Callable = _build_lookup(catalog)

	var manager: Node = _new_manager()
	var warehouse: Node = WAREHOUSE_COMPONENT_SCRIPT.new()
	track(warehouse)
	warehouse.set("Capacity", 2)
	warehouse.set("SaveItemLookup", lookup)
	manager.call("register_participant", warehouse)

	var oversized_slots: Array = []
	for index: int in 5:
		oversized_slots.append({"card_id": "wood_01", "amount": index + 1})
	manager.call("apply", {"global": {"warehouse": {"slots": oversized_slots}}})

	assert_gt(int(warehouse.get("Capacity")), 4, "存档槽位超出容量时仓库必须扩容。")
	_assert_stack_at(warehouse, 4, catalog[&"wood_01"], 5, {})


## 验证带入栏参与者往返、信号与「取出即消耗」的落盘语义。
##
## @return 无返回值。
func test_carry_participant_round_trip_and_change_signal() -> void:
	var catalog: Dictionary = _build_catalog()

	var source: Node = ITEMS_CONTROL_SCRIPT.new()
	track(source)
	source.set("items", catalog.duplicate())
	var changed_count: Array[int] = [0]
	source.connect("carry_items_changed", func() -> void: changed_count[0] += 1)

	source.call("SetCarryEntry", 0, catalog[&"wood_01"], 2)
	source.call("SetCarryEntry", 3, catalog[&"iron_sword"], 1)
	assert_eq(changed_count[0], 2, "写入带入栏必须发出变更信号。")

	var captured: Dictionary = source.call("capture_save_data")
	var saved_slots: Array = captured.get("slots", []) as Array
	assert_eq(
		saved_slots.size(),
		int(ITEMS_CONTROL_SCRIPT.get_script_constant_map()["CARRY_SLOT_CAPACITY"]),
		"带入栏存档长度必须等于权威栏位数量。"
	)
	assert_eq((saved_slots[0] as Dictionary).get("card_id"), "wood_01", "栏位内容必须落盘。")
	assert_eq(saved_slots[1], null, "空栏位必须落盘为 null。")

	var target: Node = ITEMS_CONTROL_SCRIPT.new()
	track(target)
	target.set("items", catalog.duplicate())
	assert_true(bool(target.call("apply_save_data", captured)), "带入栏必须成功应用存档。")
	var entry: Dictionary = target.call("GetCarryEntry", 0)
	assert_eq((entry.get("item") as Resource).get("CardId"), &"wood_01", "物品身份必须恢复。")
	assert_eq(int(entry.get("count")), 2, "数量必须恢复。")
	assert_eq(
		(target.call("GetCarryEntry", 1) as Dictionary).get("item"),
		null,
		"未占用的栏位必须保持为空。"
	)
	assert_true(bool(target.call("HasCarryItems")), "恢复后带入栏必须报告有内容。")

	# 开局带入即消耗：取出后带入栏清空，反向的变更信号让「消耗」这件事也能落盘。
	var taken: Array = target.call("TakeCarryItems")
	assert_eq(taken.size(), 2, "取出必须返回全部实际占用的栏位。")
	assert_false(bool(target.call("HasCarryItems")), "取出后带入栏必须为空。")
	_assert_dict_eq(
		target.call("capture_save_data"),
		{"slots": _empty_slots(int(ITEMS_CONTROL_SCRIPT.get_script_constant_map()["CARRY_SLOT_CAPACITY"]))},
		"取出即消耗：紧接着采集必须得到一份全空的带入栏"
	)


## 验证钱包参与者的往返与越界回退。
##
## @return 无返回值。
func test_wallet_participant_round_trip_and_clamping() -> void:
	var default_gold: int = int(PLAYER_WALLET_SCRIPT.get_script_constant_map()["DefaultGold"])
	var wallet: Node = PLAYER_WALLET_SCRIPT.new()
	track(wallet)

	_assert_dict_eq(
		wallet.call("capture_save_data"),
		{"gold": default_gold},
		"未读档时钱包采集出的必须是默认金币"
	)

	assert_true(bool(wallet.call("apply_save_data", {"gold": 1500})), "正常金币必须能应用。")
	assert_eq(int(wallet.get("Gold")), 1500, "金币必须恢复为存档值。")
	_assert_dict_eq(
		wallet.call("capture_save_data"),
		{"gold": 1500},
		"采集 → 应用 → 再采集必须等价"
	)

	assert_true(
		bool(wallet.call("apply_save_data", {"gold": -20})),
		"非法金币必须按回退语义成功处理，而不是让整次读档失败。"
	)
	assert_eq(int(wallet.get("Gold")), default_gold, "负金币必须回退到默认值。")

	assert_true(bool(wallet.call("apply_save_data", {})), "空载荷（无存档）必须能应用。")
	assert_eq(int(wallet.get("Gold")), default_gold, "无存档时必须使用默认金币。")


## 验证容量升级参与者的往返与等级收窄。
##
## @return 无返回值。
func test_progression_participant_round_trip_and_clamping() -> void:
	var progression: Node = PLAYER_PROGRESSION_SCRIPT.new()
	track(progression)

	_assert_dict_eq(
		progression.call("capture_save_data"),
		{"warehouse_level": 0, "carry_level": 0},
		"未读档时升级等级必须为 0"
	)

	assert_true(
		bool(progression.call("apply_save_data", {"warehouse_level": 2, "carry_level": 99})),
		"升级等级必须能应用。"
	)
	assert_eq(int(progression.call("GetWarehouseLevel")), 2, "仓库等级必须恢复。")
	assert_eq(
		int(progression.call("GetCarryLevel")),
		int(PLAYER_PROGRESSION_SCRIPT.get_script_constant_map()["CarryMaxLevel"]),
		"超上限的带入栏等级必须收窄到上限。"
	)
	_assert_dict_eq(
		progression.call("capture_save_data"),
		{"warehouse_level": 2, "carry_level": 5},
		"收窄后的等级必须被采集回来，避免每次读档都重新收窄"
	)

	assert_true(
		bool(progression.call("apply_save_data", {"warehouse_level": -3, "carry_level": 1})),
		"负等级必须按收窄语义处理。"
	)
	assert_eq(int(progression.call("GetWarehouseLevel")), 0, "负等级必须收窄到 0。")
	assert_eq(int(progression.call("GetCarryLevel")), 1, "合法等级必须保留。")


## 验证容量升级参与者把容量同步到仓库（含「只增不减」这条不变量）。
##
## @return 无返回值。
func test_progression_applies_capacity_to_warehouse() -> void:
	var progression: Node = PLAYER_PROGRESSION_SCRIPT.new()
	track(progression)
	var warehouse: Node = WAREHOUSE_COMPONENT_SCRIPT.new()
	track(warehouse)
	warehouse.set("Capacity", 1)
	progression.set("_warehouse", warehouse)

	assert_true(bool(progression.call("apply_save_data", {"warehouse_level": 3, "carry_level": 0})))
	assert_eq(
		int(warehouse.get("Capacity")),
		int(PLAYER_PROGRESSION_SCRIPT.get_script_constant_map()["WarehouseBaseValue"])
			+ 3 * int(PLAYER_PROGRESSION_SCRIPT.get_script_constant_map()["WarehouseValuePerLevel"]),
		"仓库容量必须等于等级对应的规则值。"
	)

	# 回落到 0 级不得把已经扩出来的容量缩回去（SetCapacity 只增不减），
	# 否则玩家已放进高序号槽位的物品会变成「存在但看不见」。
	var grown_capacity: int = int(warehouse.get("Capacity"))
	assert_true(bool(progression.call("apply_save_data", {"warehouse_level": 0, "carry_level": 0})))
	assert_eq(
		int(warehouse.get("Capacity")),
		grown_capacity,
		"容量回调不得缩减既有槽位。"
	)


# ----- 夹具与工具 -----

## 在当前临时路径上构造一个存档层实例。
##
## 刻意**不**把实例加入场景树：`test_run` 环境的 `_ready()` 会尝试解析 autoload，
## 而套件需要的是「可显式驱动的纯行为」。因此读盘由本函数直接调用 `load_from_disk()`。
##
## @return 已读完盘（或确认无档）的 `SaveManager` 实例。
func _new_manager() -> Node:
	var manager: Node = SAVE_MANAGER_SCRIPT.new()
	track(manager)
	manager.set("SaveFilePath", TEST_SAVE_PATH)
	manager.call("load_from_disk")
	return manager


## 构造一个尚未注册的档位桩。
##
## 注意 `state` 的语义陷阱：注册会立刻分发一次存档，桩按「先清空再写入」的语义会把状态
## 复位。因此**注册前**播种的状态会被抹掉——需要「已注册且带状态」时请用 `_register_stub`。
##
## @param key 存档键。
## @param scope 作用域。
## @param state 初始状态。
## @return 已 `track` 的参与者实例。
func _make_stub(key: String, scope: String, state: Dictionary) -> Node:
	var participant: Node = StubParticipant.new()
	track(participant)
	participant.set("Key", key)
	participant.set("Scope", scope)
	participant.set("State", state)
	return participant


## 构造、注册并在注册**之后**注入状态的档位桩。
##
## @param manager 存档层实例。
## @param key 存档键。
## @param scope 作用域。
## @param state 注册后注入的状态。
## @return 已注册且带状态的参与者实例。
func _register_stub(manager: Node, key: String, scope: String, state: Dictionary) -> Node:
	var participant: Node = _make_stub(key, scope, {})
	assert_true(
		bool(manager.call("register_participant", participant)),
		"档位桩 %s 必须注册成功。" % key
	)
	participant.set("State", state)
	return participant


## 构造物品目录，覆盖「带 AttributeBonuses 的装备」与「普通物品」两类。
##
## @return CardId → Resource 的目录。
func _build_catalog() -> Dictionary:
	var sword: Resource = StubItem.new()
	sword.set("CardId", &"iron_sword")
	sword.set("CardName", "铁剑")
	sword.set("AttributeBonuses", {0: Vector2i(10, 20), 4: Vector2i(1, 3)})

	var wood: Resource = StubItem.new()
	wood.set("CardId", &"wood_01")
	wood.set("CardName", "木材")

	return {&"iron_sword": sword, &"wood_01": wood}


## 构造编解码用的查表函数，模拟生产里的 `ItemsControl.get_item`。
##
## @param catalog CardId → Resource 的目录。
## @return 接受 StringName 的查表 Callable。
func _build_lookup(catalog: Dictionary) -> Callable:
	return func(card_id: StringName) -> Resource:
		return catalog.get(card_id, null) as Resource


## 在仓库的指定槽位放入物品，可选写入洗炼属性。
##
## @param warehouse 仓库组件实例。
## @param index 槽位序号。
## @param item 物品 Resource。
## @param amount 数量。
## @param rolled 洗炼属性；必须写在 `SetItem` 之后，因为 `SetItem` 会清空该字段。
## @return 无返回值。
func _place_stack(
	warehouse: Node,
	index: int,
	item: Resource,
	amount: int,
	rolled: Dictionary = {}
) -> void:
	var slots: Array = warehouse.get("Slots")
	var stack: Variant = slots[index]
	stack.call("SetItem", item, amount)
	if not rolled.is_empty():
		var target_rolled: Dictionary = stack.get("RolledAttributes")
		for key: Variant in rolled:
			target_rolled[key] = rolled[key]


## 断言某个槽位的内容。
##
## @param warehouse 仓库组件实例。
## @param index 槽位序号。
## @param expected_item 期望物品；null 表示期望空槽位。
## @param expected_amount 期望数量。
## @param expected_rolled 期望洗炼属性。
## @return 无返回值。
func _assert_stack_at(
	warehouse: Node,
	index: int,
	expected_item: Resource,
	expected_amount: int,
	expected_rolled: Dictionary
) -> void:
	var slots: Array = warehouse.get("Slots")
	var stack: Variant = slots[index]
	if expected_item == null:
		assert_true(bool(stack.get("IsEmpty")), "槽位 %d 必须为空。" % index)
		return

	assert_false(bool(stack.get("IsEmpty")), "槽位 %d 不得为空。" % index)
	assert_eq(stack.get("Item"), expected_item, "槽位 %d 的物品身份必须一致。" % index)
	assert_eq(int(stack.get("Amount")), expected_amount, "槽位 %d 的数量必须一致。" % index)
	_assert_dict_eq(
		stack.get("RolledAttributes"),
		expected_rolled,
		"槽位 %d 的洗炼属性必须一致" % index
	)


## 断言解码结果中某个条目的完整内容。
##
## @param decoded `decode_slots` 的返回值。
## @param index 条目序号。
## @param expected_status 期望状态。
## @param expected_item 期望物品。
## @param expected_amount 期望数量。
## @param expected_rolled 期望洗炼属性。
## @return 无返回值。
func _assert_decoded_entry(
	decoded: Dictionary,
	index: int,
	expected_status: String,
	expected_item: Resource,
	expected_amount: int,
	expected_rolled: Dictionary
) -> void:
	var entries: Array = decoded.get("entries", []) as Array
	var entry: Dictionary = entries[index]
	assert_eq(String(entry.get("status")), expected_status, "条目 %d 的状态必须一致。" % index)
	assert_eq(entry.get("item"), expected_item, "条目 %d 的物品必须一致。" % index)
	assert_eq(int(entry.get("amount")), expected_amount, "条目 %d 的数量必须一致。" % index)
	_assert_dict_eq(entry.get("rolled"), expected_rolled, "条目 %d 的洗炼属性必须一致" % index)


## 逐字段比较两个字典。
##
## 为什么不用 `assert_eq` 直接比字典：逐字段比较给出的失败信息能指明是哪个键不对，
## 而且不依赖字典 `==` 的具体实现语义。
##
## @param actual 实际值。
## @param expected 期望字典。
## @param msg 失败信息前缀。
## @return 无返回值。
func _assert_dict_eq(actual: Variant, expected: Dictionary, msg: String) -> void:
	assert_true(
		actual is Dictionary,
		"%s：实际值不是字典（%s）。" % [msg, type_string(typeof(actual))]
	)
	if not (actual is Dictionary):
		return

	var actual_dict: Dictionary = actual
	assert_eq(
		actual_dict.size(),
		expected.size(),
		"%s：键集合不一致（实际 %s，期望 %s）。"
		% [msg, str(actual_dict.keys()), str(expected.keys())]
	)
	for key: Variant in expected:
		assert_eq(actual_dict.get(key), expected[key], "%s：键 %s 的值不一致。" % [msg, str(key)])


## 生成一份全空带入栏的期望槽位数组。
##
## @param slot_count 栏位数量。
## @return 长度为 slot_count 的 null 数组。
func _empty_slots(slot_count: int) -> Array:
	var slots: Array = []
	for _index: int in slot_count:
		slots.append(null)
	return slots


## 读取文件正文。
##
## @param path res:// 或 user:// 路径。
## @return 文件正文；文件缺失时返回空字符串。
func _read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)


## 写入文件正文，必要时先建目录。
##
## @param path 目标路径。
## @param text 正文。
## @return 无返回值。
func _write_text(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(TEST_SAVE_DIRECTORY)
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(text)
	file.close()


## 解析一个存档文件。
##
## @param path 文件路径。
## @return 解析后的字典；无法解析时返回空字典。
func _read_document(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(_read_text(path))
	return parsed if parsed is Dictionary else {}


## 取出存档文件里 `data.global` 的内容。
##
## @param path 文件路径。
## @return `data.global` 字典；结构不对时返回空字典。
func _read_saved_global(path: String) -> Dictionary:
	var document: Dictionary = _read_document(path)
	var data: Variant = document.get("data")
	if not (data is Dictionary):
		return {}
	var global_data: Variant = (data as Dictionary).get("global")
	return global_data if global_data is Dictionary else {}


## 生成一份结构合法的最小存档文本。
##
## @param global_data `data.global` 的内容。
## @return JSON 文本。
func _valid_document(global_data: Dictionary) -> String:
	var version: int = int(SAVE_MANAGER_SCRIPT.get_script_constant_map()["FORMAT_VERSION"])
	return JSON.stringify({
		"format_version": version,
		"saved_at_unix": 0,
		"data": {"global": global_data, "run": {}},
	})


## 按顺序读取 project.godot 的 `[autoload]` 段键名。
##
## @return Autoload 名称数组，顺序即注册顺序（决定 `_ready` 顺序）。
func _read_autoload_order() -> Array[String]:
	var order: Array[String] = []
	var in_section: bool = false
	for line: String in _read_text(PROJECT_CONFIG_PATH).split("\n"):
		var trimmed: String = line.strip_edges()
		if trimmed.begins_with("["):
			in_section = trimmed == "[autoload]"
			continue
		if not in_section or trimmed.is_empty() or trimmed.begins_with(";"):
			continue
		var separator: int = trimmed.find("=")
		if separator <= 0:
			continue
		order.append(trimmed.substr(0, separator))
	return order


## 解析某个 Autoload 指向的实际脚本路径。
##
## 存在的理由：Godot 编辑器会把 `project.godot` 里的 `res://` 路径改写成 `uid://`，
## 直接比对字符串会在编辑器保存一次之后就失效。这里统一走 UID 反查。
##
## @param autoload_name Autoload 名称。
## @return 规范化的脚本路径；无法解析时返回空字符串。
func _resolve_autoload_path(autoload_name: String) -> String:
	var raw_target: String = ""
	var in_section: bool = false
	for line: String in _read_text(PROJECT_CONFIG_PATH).split("\n"):
		var trimmed: String = line.strip_edges()
		if trimmed.begins_with("["):
			in_section = trimmed == "[autoload]"
			continue
		if not in_section or trimmed.is_empty():
			continue
		var separator: int = trimmed.find("=")
		if separator <= 0 or trimmed.substr(0, separator) != autoload_name:
			continue
		raw_target = trimmed.substr(separator + 1).strip_edges()
		raw_target = raw_target.trim_prefix("\"").trim_suffix("\"").trim_prefix("*")

	if raw_target.is_empty():
		return ""
	if not raw_target.begins_with("uid://"):
		return raw_target

	var uid: int = ResourceUID.text_to_id(raw_target)
	if uid == ResourceUID.INVALID_ID:
		return raw_target
	var resolved: String = ResourceUID.get_id_path(uid)
	return resolved if not resolved.is_empty() else raw_target


## 查询某个脚本是否被注册成了全局类名。
##
## @param path 脚本路径。
## @return 该路径注册的类名数组；通常应为空。
func _registered_global_class_names(path: String) -> Array[String]:
	var names: Array[String] = []
	for entry: Variant in ProjectSettings.get_global_class_list():
		if not (entry is Dictionary):
			continue
		var record: Dictionary = entry
		if String(record.get("path", "")) != path:
			continue
		names.append(String(record.get("class", "")))
	return names


## 删除测试目录下的全部存档产物。
##
## @return 无返回值。
func _cleanup_test_files() -> void:
	for suffix: String in ALL_SUFFIXES:
		var path: String = TEST_SAVE_PATH + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	# 目录本身也清掉：它是本套件专用的临时目录，留着只会让 user:// 越积越乱。
	if DirAccess.dir_exists_absolute(TEST_SAVE_DIRECTORY):
		DirAccess.remove_absolute(TEST_SAVE_DIRECTORY)
