@tool
extends McpTestSuite

## 局内账本与轮回配置契约；真实 autoload 及界面生命周期由主场景冒烟覆盖。
const RUN: GDScript = preload("res://core/gameflow/run_session_data.gd")
const ITEM: GDScript = preload("res://resources/item/item_data.gd")
const CONFIG: GDScript = preload("res://resources/save/settlement_config.gd")


## 无参数；返回可通过 MCP 定位的套件名。
func suite_name() -> String:
	return "run_settlement_flow"


## 无参数；验证容量按格数和真实堆叠上限计算，不足时整体失败。
func test_capacity_atomicity_and_real_stack() -> void:
	var run: RefCounted = RUN.new("test-run", 5)
	var item: Resource = ITEM.new()
	item.set("MaxStackSize", 2)
	assert_true(run.call("add_harvest_item", item, 9, {"power": 3}))
	assert_eq(run.call("get_harvest").size(), 5)
	assert_false(run.call("add_harvest_item", item, 2, {"power": 3}))
	assert_true(run.call("add_harvest_item", item, 1, {"power": 3}))
	var stacks: Array = run.call("get_harvest")
	var sum: int = 0
	for stack: RefCounted in stacks:
		assert_eq(stack.get("Item"), item)
		assert_eq(stack.get("RolledAttributes"), {"power": 3})
		sum += int(stack.get("Amount"))
	assert_eq(sum, 10)
	assert_false(run.call("add_harvest_item", item, 1, {"power": 9}))


## 无参数；验证外部结果修改不会改变内部奖励，取消保留属性。
func test_isolated_harvest_and_remove() -> void:
	var run: RefCounted = RUN.new("test-run", 5)
	var item: Resource = ITEM.new()
	assert_true(run.call("add_harvest_item", item, 4, {"power": 3}))
	var copies: Array = run.call("get_harvest")
	copies[0].set("Amount", 99)
	copies[0].get("RolledAttributes")["power"] = 99
	var actual: Array = run.call("get_harvest")
	assert_eq(actual[0].get("Amount"), 4)
	assert_eq(actual[0].get("RolledAttributes"), {"power": 3})
	assert_false(run.call("remove_harvest_item", item, 5, {"power": 3}))
	assert_true(run.call("remove_harvest_item", item, 4, {"power": 3}))
	assert_eq(run.call("get_harvest").size(), 0)


## 无参数；验证计时、追加描述和结束冻结属于纯内存账本。
func test_description_timing_and_ended_freeze() -> void:
	var run: RefCounted = RUN.new("test-run", 5)
	run.call("add_description", "击败了小怪1")
	run.call("add_description", "")
	run.call("add_description", "击败了boss1")
	assert_eq(run.get("description"), "击败了小怪1\n击败了boss1")
	run.call("set_description", "新描述")
	run.call("advance_time", 3.0)
	run.call("advance_time", -1.0)
	assert_true(run.call("record_statistic", "kills", 1))
	run.set("ended", true)
	run.call("advance_time", 5.0)
	run.call("add_description", "不应加入")
	assert_eq(run.get("duration_seconds"), 3.0)
	assert_eq(run.get("description"), "新描述")
	assert_false(run.call("record_statistic", "kills", 1))
	assert_false(run.call("add_harvest_item", ITEM.new(), 1))


## 无参数；验证默认正式白名单为空、测试赠品真实、持久化关闭。
func test_config_defaults_and_asset() -> void:
	var config: Resource = CONFIG.new()
	assert_false(config.get("persistence_enabled"))
	assert_true(config.get("enable_death_test_reward"))
	assert_eq(config.get("allowed_resources"), [])
	assert_eq(config.get("death_test_item"), load("res://items/items/wheat.tres"))
	var asset: Resource = load("res://resources/save/settlement_config.tres")
	assert_true(asset != null)
	assert_false(asset.get("persistence_enabled"))


## 无参数；相同物品不同洗炼不可合并，容量下限与局外默认一致。
func test_distinct_attributes_and_capacity_floor() -> void:
	var run: RefCounted = RUN.new("test-run", 0)
	assert_eq(run.get("capacity"), 5)
	var item: Resource = ITEM.new()
	assert_true(run.call("add_harvest_item", item, 1, {"power": 3}))
	assert_true(run.call("add_harvest_item", item, 1, {"power": 4}))
	assert_eq(run.call("get_harvest").size(), 2)
	assert_eq(run.call("get_remaining_slots"), 3)


## 无参数；默认计算保留真实资源和属性、代币为零，返回堆叠与输入隔离。
func test_default_reward_calculation_isolated_and_zero_tokens() -> void:
	var run: RefCounted = RUN.new("test-run", 5)
	var item: Resource = ITEM.new()
	assert_true(run.call("add_harvest_item", item, 2, {"power": 3}))
	var input: Array = run.call("get_harvest")
	var statistics: Dictionary = {"kills": 1}
	var config: Resource = CONFIG.new()
	for reason: String in ["death", "win", "abandon"]:
		var rewards: Dictionary = config.call("calculate_rewards", input, statistics, reason)
		assert_eq(rewards["tokens"], 0)
		var output: Array = rewards["harvest"]
		assert_eq(output.size(), 1)
		assert_eq(output[0].get("Item"), item)
		assert_eq(output[0].get("Amount"), 2)
		assert_eq(output[0].get("RolledAttributes"), {"power": 3})
		assert_false(output[0] == input[0])
		output[0].set("Amount", 99)
		output[0].get("RolledAttributes")["power"] = 99
		assert_eq(input[0].get("Amount"), 2)
		assert_eq(input[0].get("RolledAttributes"), {"power": 3})
	assert_eq(statistics, {"kills": 1})
	var empty_result: Dictionary = config.call("calculate_rewards", [], {}, "death")
	assert_eq(empty_result["harvest"], [])
	assert_eq(empty_result["tokens"], 0)
