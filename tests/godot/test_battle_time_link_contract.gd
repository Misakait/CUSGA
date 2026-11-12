@tool
extends McpTestSuite

## 战斗行动值 → 局外时间的联动契约。
##
## 关键事实：
## 1. 战斗 ATB 每次结算都会从全体实体扣除同一段 `min_av`，这段值就是本次战斗时间消耗；
## 2. 局外时间的唯一权威仍是 `TimeSystem.PassTime`，战斗侧只负责换算和转交；
## 3. 换算倍率必须可导出调参，并且不足 1 点的时间余量不能丢。

const BATTLE_MANAGER_SCRIPT: GDScript = preload("res://scripts/battle_scripts/battle_manager.gd")
const BRIDGE_PATH: String = "res://core/combat/battle_time_bridge.gd"


## 记录 PassTime 调用的伪时间系统，替代 /root/TimeSystem。
class FakeTimeSystem extends Node:
	var passed_total: int = 0
	var call_count: int = 0

	## 记录一次局外时间推进。
	## 参数 amount：本次推进的时间点。
	## 返回值：无。
	func PassTime(amount: int) -> void:
		passed_total += amount
		call_count += 1


func suite_name() -> String:
	return "battle_time_link_contract"


## 验证 BattleManager 暴露了可调倍率，且默认值能让战斗产生可感知的时间推进。
func test_battle_manager_exposes_time_multiplier() -> void:
	var manager: Node = BATTLE_MANAGER_SCRIPT.new()
	var multiplier: Variant = manager.get("battle_action_value_to_time_multiplier")
	assert_true(multiplier != null, "BattleManager 必须导出 battle_action_value_to_time_multiplier。")
	if multiplier != null:
		assert_true(float(multiplier) > 0.0, "默认倍率必须大于 0，否则战斗永远不会推进时间。")
		assert_eq(float(multiplier), 0.05, "默认倍率应为 0.05：100 点战斗行动值折算 5 点局外时间。")
	manager.free()


## 验证 ATB 结算入口确实把本次最小行动值交给时间联动。
func test_calculate_turn_calls_time_link() -> void:
	var source: String = FileAccess.get_file_as_string("res://scripts/battle_scripts/battle_manager.gd")
	var function_start: int = source.find("func _handle_calculate_turn")
	assert_true(function_start >= 0, "BattleManager 必须保留 _handle_calculate_turn。")
	if function_start < 0:
		return
	var function_end: int = source.find("\nfunc ", function_start + 1)
	var function_block: String = source.substr(function_start) if function_end < 0 else source.substr(function_start, function_end - function_start)
	var expected_call: String = "_advance_world_time_for_battle_action(min_av)"
	var found_call: bool = false
	for line: String in function_block.split("\n"):
		# 必须匹配真正的调用行，不能只匹配注释或说明文字。
		if line.strip_edges() == expected_call:
			found_call = true
			break
	assert_true(
		found_call,
		"ATB 结算必须在扣除 min_av 后推进局外时间，否则战斗不会导致时间流逝。"
	)


## 验证换算桥本身：倍率、取整、余量累积和关闭开关。
func test_bridge_converts_and_carries_fractional_time() -> void:
	assert_true(ResourceLoader.exists(BRIDGE_PATH), "必须存在战斗时间换算桥。")
	if not ResourceLoader.exists(BRIDGE_PATH):
		return
	var bridge_script: GDScript = load(BRIDGE_PATH)
	var bridge: RefCounted = bridge_script.new()

	assert_eq(bridge.call("Accumulate", 100.0, 0.05), 5, "100 点战斗行动值 × 0.05 必须折算 5 点。")
	assert_true(
		absf(float(bridge.call("GetPendingPoints"))) < 0.00001,
		"整数点必须全部转交，不能留下浮点残渣。"
	)

	bridge.call("Reset")
	assert_eq(bridge.call("Accumulate", 1.0, 0.4), 0, "不足 1 点时必须先保留余量。")
	assert_eq(bridge.call("Accumulate", 1.0, 0.4), 0, "第二次仍不足 1 点时必须继续累积。")
	assert_eq(bridge.call("Accumulate", 1.0, 0.4), 1, "三次 0.4 点必须累积出 1 点。")
	assert_true(
		absf(float(bridge.call("GetPendingPoints")) - 0.2) < 0.00001,
		"转交 1 点后必须保留剩余 0.2 点。"
	)

	assert_eq(bridge.call("Accumulate", 100.0, 0.0), 0, "倍率为 0 时必须关闭联动。")
	assert_eq(bridge.call("Accumulate", 100.0, -1.0), 0, "负倍率必须按 0 处理。")
	assert_eq(bridge.call("Accumulate", -100.0, 0.5), 0, "负战斗行动值不得推进时间。")


## 验证 BattleManager 真实调用 PassTime，而不是只把数值留在自己内部。
func test_battle_manager_passes_integer_points_to_time_system() -> void:
	var manager: Node = BATTLE_MANAGER_SCRIPT.new()
	var multiplier: Variant = manager.get("battle_action_value_to_time_multiplier")
	assert_true(multiplier != null, "BattleManager 必须导出倍率参数。")
	if multiplier == null:
		manager.free()
		return
	assert_true(
		manager.has_method("_advance_world_time_for_battle_action"),
		"BattleManager 必须有统一的时间推进入口。"
	)
	if not manager.has_method("_advance_world_time_for_battle_action"):
		manager.free()
		return

	manager.set("battle_action_value_to_time_multiplier", 0.05)
	var fake: Node = FakeTimeSystem.new()
	manager.set("TimeSystemNode", fake)
	manager.call("_advance_world_time_for_battle_action", 100.0)
	assert_eq(fake.get("passed_total"), 5, "一次 100 点战斗回合必须推进 5 点局外时间。")
	assert_eq(fake.get("call_count"), 1, "一次推进必须只调用一次 PassTime。")

	manager.call("_advance_world_time_for_battle_action", 100.0)
	assert_eq(fake.get("passed_total"), 10, "连续战斗回合必须继续推进时间。")

	manager.free()
	fake.free()


## 验证小数余量由 BattleManager 持有的换算桥跨回合保留。
func test_battle_manager_keeps_fractional_remainder_across_turns() -> void:
	var manager: Node = BATTLE_MANAGER_SCRIPT.new()
	if manager.get("battle_action_value_to_time_multiplier") == null:
		assert_true(false, "BattleManager 必须导出倍率参数。")
		manager.free()
		return
	manager.set("battle_action_value_to_time_multiplier", 0.005)
	var fake: Node = FakeTimeSystem.new()
	manager.set("TimeSystemNode", fake)

	manager.call("_advance_world_time_for_battle_action", 100.0)
	assert_eq(fake.get("passed_total"), 0, "0.5 点不足 1 点，本回合不应推进整数时间。")
	manager.call("_advance_world_time_for_battle_action", 100.0)
	assert_eq(fake.get("passed_total"), 1, "两回合的 0.5 点必须累积成 1 点。")

	manager.free()
	fake.free()


## 验证倍率为 0 或负数时战斗不推进时间。
func test_battle_manager_disables_time_link_for_non_positive_multiplier() -> void:
	var manager: Node = BATTLE_MANAGER_SCRIPT.new()
	if manager.get("battle_action_value_to_time_multiplier") == null:
		assert_true(false, "BattleManager 必须导出倍率参数。")
		manager.free()
		return
	var fake: Node = FakeTimeSystem.new()
	manager.set("TimeSystemNode", fake)

	manager.set("battle_action_value_to_time_multiplier", 0.0)
	manager.call("_advance_world_time_for_battle_action", 100.0)
	assert_eq(fake.get("passed_total"), 0, "倍率 0 必须关闭时间联动。")

	manager.set("battle_action_value_to_time_multiplier", -0.5)
	manager.call("_advance_world_time_for_battle_action", 100.0)
	assert_eq(fake.get("passed_total"), 0, "负倍率必须按 0 处理，不能倒流时间。")

	manager.free()
	fake.free()


## 验证缺少时间节点时战斗不崩溃，且不会把本次行动值提前消耗掉。
func test_battle_manager_degrades_without_time_system() -> void:
	var manager: Node = BATTLE_MANAGER_SCRIPT.new()
	if manager.get("battle_action_value_to_time_multiplier") == null:
		assert_true(false, "BattleManager 必须导出倍率参数。")
		manager.free()
		return
	manager.set("battle_action_value_to_time_multiplier", 0.05)
	manager.set("TimeSystemNode", null)
	manager.call("_advance_world_time_for_battle_action", 100.0)

	var fake: Node = FakeTimeSystem.new()
	manager.set("TimeSystemNode", fake)
	manager.call("_advance_world_time_for_battle_action", 100.0)
	assert_eq(fake.get("passed_total"), 5, "时间节点恢复后，本次行动值必须仍然可以完整折算。")

	manager.free()
	fake.free()
