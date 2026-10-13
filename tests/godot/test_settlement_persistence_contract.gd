@tool
extends McpTestSuite

## 轮回档案与存档门禁契约；文件写入只发生在独立测试目录，不操作玩家真实存档。
const PROFILE: GDScript = preload("res://core/progression/player_profile.gd")
const MANAGER: GDScript = preload("res://core/save/save_manager.gd")
const WALLET: GDScript = preload("res://core/autoloads/player_wallet.gd")
const PROGRESSION: GDScript = preload("res://core/progression/player_progression.gd")
const STACK: GDScript = preload("res://resources/item/item_stack.gd")
const WHEAT: Resource = preload("res://items/items/wheat.tres")
const PATH: String = "user://test_settlement_profile/save.json"

## 读取套件名称。无参数；返回发现用名称。
func suite_name() -> String:
	return "settlement_persistence_contract"

## 每个测试前清理临时文件。无参数；无返回值。
func setup() -> void:
	_cleanup()

## 套件结束后清理临时文件。无参数；无返回值。
func suite_teardown() -> void:
	_cleanup()

## 验证档案默认容量和重复结算标记。无参数；无返回值。
func test_profile_capacity_and_settled_ids() -> void:
	var profile: RefCounted = PROFILE.new()
	assert_eq(int(profile.call("get_harvest_capacity")), 5)
	assert_false(bool(profile.call("set_harvest_capacity", 4)))
	assert_true(bool(profile.call("set_harvest_capacity", 8)))
	profile.call("mark_run_settled", "run-a")
	profile.call("mark_run_settled", "run-a")
	profile.call("mark_run_settled", "")
	assert_true(bool(profile.call("has_settled_run", "run-a")))
	var encoded: Dictionary = profile.call("capture_extra_data")
	assert_eq((encoded.get("settled_run_ids") as Array).size(), 1)
	assert_eq(int(encoded.get("harvest_capacity")), 8)

## 验证规则传入极大代币增量时饱和到上限，不溢出为负余额。无参数；无返回值。
func test_token_delta_saturates_before_integer_overflow() -> void:
	var profile: RefCounted = PROFILE.new()
	profile.call("add_tokens", 1)
	profile.call("add_tokens", 9223372036854775807)
	assert_eq(int(profile.get("tokens")), 2147483647)
	profile.call("add_tokens", -1)
	assert_eq(int(profile.get("tokens")), 2147483647)

## 验证待领取堆叠复制和洗炼属性往返。无参数；无返回值。
func test_pending_harvest_isolated_and_serialized() -> void:
	var profile: RefCounted = PROFILE.new()
	var source: RefCounted = STACK.new()
	source.call("SetItem", WHEAT, 3)
	source.set("RolledAttributes", {7: 12})
	profile.call("add_pending_harvest", [source])
	source.set("Amount", 100)
	var copied: Array = profile.call("get_pending_harvest")
	assert_eq(int(copied[0].get("Amount")), 3)
	copied[0].set("Amount", 99)
	(copied[0].get("RolledAttributes") as Dictionary)[7] = 999
	var encoded: Dictionary = profile.call("capture_extra_data")
	var restored: RefCounted = PROFILE.new()
	restored.call("apply_extra_data", encoded, Callable(self, "_lookup"))
	var stacks: Array = restored.call("get_pending_harvest")
	assert_eq(stacks.size(), 1)
	assert_eq(int(stacks[0].get("Amount")), 3)
	assert_eq((stacks[0].get("RolledAttributes") as Dictionary).get(7), 12)
	assert_eq(stacks[0].get("Item"), WHEAT)

## 验证旧存档键继续读写同一档案。无参数；无返回值。
func test_legacy_wallet_and_progression_share_profile() -> void:
	var profile: RefCounted = PROFILE.new()
	var wallet: Node = WALLET.new()
	var progression: Node = PROGRESSION.new()
	track(wallet)
	track(progression)
	wallet.set("_profile", profile)
	progression.set("_profile", profile)
	wallet.call("apply_save_data", {"gold": 2000})
	progression.call("apply_save_data", {"warehouse_level": 2, "carry_level": 3})
	assert_eq(int(profile.get("gold")), 2000)
	assert_true(bool(wallet.call("TrySpend", 100)))
	assert_eq(int(profile.get("gold")), 1900)
	assert_eq(int(progression.call("GetWarehouseCapacity")), 45)
	var levels: Dictionary = profile.get("upgrade_levels")
	levels["warehouse_level"] = 3
	assert_eq(int(progression.call("GetWarehouseLevel")), 3)
	profile.call("apply_extra_data", {}, Callable())
	assert_eq(int(progression.call("GetWarehouseLevel")), 3)
	assert_eq(int(wallet.get("Gold")), 1900)

## 验证默认测试模式阻止显式、防抖、退出、低层原子写入和删除。无参数；无返回值。
func test_disabled_policy_blocks_every_file_mutation() -> void:
	var manager: Node = _manager(false)
	assert_false(bool(manager.call("save_now")))
	manager.call("request_save")
	manager.call("_process", 1.0)
	manager.call("_notification", Node.NOTIFICATION_WM_CLOSE_REQUEST)
	assert_false(bool(manager.call("_write_atomically", "{}")))
	assert_false(bool(manager.call("erase_save")))
	assert_eq(int(manager.call("get_successful_write_count")), 0)
	for suffix: String in ["", ".bak", ".tmp", ".corrupt"]:
		assert_false(FileAccess.file_exists(PATH + suffix))
	assert_false(bool(manager.call("configure_test_persistence", PATH, true)))

## 验证正式局内暂停写入，结束后一次保存带出资产和空快照。无参数；无返回值。
func test_run_hold_and_atomic_settlement_commit() -> void:
	var manager: Node = _manager(true)
	manager.call("register_participant", manager)
	assert_true(bool(manager.call("save_now")))
	var before: String = FileAccess.get_file_as_string(PATH)
	manager.call("set_run_mode", 1)
	var before_count: int = int(manager.call("get_successful_write_count"))
	before = FileAccess.get_file_as_string(PATH)
	manager.call("begin_run_write_hold")
	var profile: RefCounted = manager.call("get_profile")
	profile.call("add_tokens", 10)
	profile.call("mark_run_settled", "run-complete")
	assert_true(bool(manager.call("freeze_run_before_battle")))
	manager.call("resume_run_after_battle")
	manager.call("request_save")
	manager.call("_process", 1.0)
	manager.call("_notification", Node.NOTIFICATION_WM_CLOSE_REQUEST)
	assert_false(bool(manager.call("save_now")))
	assert_eq(FileAccess.get_file_as_string(PATH), before)
	assert_eq(int(manager.call("get_successful_write_count")), before_count)
	assert_eq(manager.call("get_loaded_run_data", "world"), {})
	manager.call("clear_run_scope")
	manager.call("end_run_write_hold")
	assert_eq(int(manager.call("get_successful_write_count")), before_count)
	assert_true(bool(manager.call("save_now")))
	var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	var data: Dictionary = document.get("data", {})
	assert_eq(data.get("run"), {})
	assert_false(FileAccess.file_exists(PATH + ".tmp"))
	assert_eq(FileAccess.get_file_as_string(PATH + ".bak"), before)
	var reader: Node = _manager(false)
	reader.call("register_participant", reader)
	var restored: RefCounted = reader.call("get_profile")
	assert_eq(int(restored.get("tokens")), 10)
	assert_true(bool(restored.call("has_settled_run", "run-complete")))
	manager.call("begin_run_write_hold")

## 验证禁用模式读取损坏主档时不复制或覆盖任何存档产物。无参数；无返回值。
func test_disabled_corrupt_load_is_read_only() -> void:
	DirAccess.make_dir_recursive_absolute(PATH.get_base_dir())
	var file: FileAccess = FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string("broken-json")
	file.close()
	var manager: Node = _manager(false)
	assert_false(bool(manager.call("has_save")))
	assert_eq(FileAccess.get_file_as_string(PATH), "broken-json")
	assert_false(FileAccess.file_exists(PATH + ".corrupt"))
	assert_false(FileAccess.file_exists(PATH + ".bak"))
	assert_false(FileAccess.file_exists(PATH + ".tmp"))

## 验证测试入口拒绝真实存档目录。无参数；无返回值。
func test_test_override_rejects_real_save_path() -> void:
	var manager: Node = MANAGER.new()
	track(manager)
	assert_false(bool(manager.call("configure_test_persistence", "user://save/game_save.json", true)))
	assert_false(bool(manager.call("configure_test_persistence", "user://test_fake/../save/game_save.json", true)))
	assert_false(bool(manager.call("is_persistence_enabled")))


func _manager(enabled: bool) -> Node:
	var manager: Node = MANAGER.new()
	track(manager)
	manager.call("configure_test_persistence", PATH, enabled)
	manager.call("load_from_disk")
	return manager


func _lookup(id: StringName) -> Resource:
	return WHEAT if id == StringName(WHEAT.get("CardId")) else null


func _cleanup() -> void:
	for suffix: String in ["", ".bak", ".tmp", ".corrupt"]:
		var path: String = PATH + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
