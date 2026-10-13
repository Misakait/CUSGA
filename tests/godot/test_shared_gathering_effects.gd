@tool
extends McpTestSuite

## 一次性与可重复采集共享规则及真实协调器入口的聚焦回归。

const SINGLE_SCRIPT: GDScript = preload("res://resources/interaction/gathering_interaction.gd")
const REUSABLE_SCRIPT: GDScript = preload("res://resources/interaction/reusable_gathering_interaction.gd")
const CALCULATOR: GDScript = preload("res://core/gathering/gathering_effect_calculator.gd")
const COORDINATOR_SCRIPT: GDScript = preload("res://core/gameflow/world_interaction_coordinator.gd")


## 按标签与槽位匹配的装备查询夹具。
class FakeEquipment extends Node:
	var reduction: int = 17
	var yield_bonus: int = 3
	var tag: StringName = &"wood"
	var slot: int = 5

	## 参数 target：采集标签；参数 target_slot：工具槽位。
	## 返回值：匹配后的耗时减免。
	func GetGatheringTimeReduction(target: StringName, target_slot: int) -> int:
		return reduction if target == tag and target_slot == slot else 0

	## 参数 target：采集标签；返回值：匹配后的额外产量。
	func GetGatheringYieldBonus(target: StringName) -> int:
		return yield_bonus if target == tag else 0


## 玩家与 GameplayPort 的最小查询面。
class FakePlayer extends Node:
	var Equipment: Node


## 通过 Player 属性提供玩家对象的最小端口。
class FakePort extends Node:
	var Player: Node


## 地形配置只需保存交互行为和显示名。
class FakeTerrainData extends Resource:
	var InteractionBehavior: Resource
	var CardName: String = "共享采集测试"


## 两种资源点所需的可写状态。
class FakeTerrain extends RefCounted:
	var TerrainData: Resource
	var IsHarvested: bool = false
	var RemainingGatheringCount: int = -1
	var RefreshReadyTotalTime: int = 0


## 记录掉落表收到的额外产量。
class FakeLootTable extends LootTableData:
	var received_bonus: int = -1
	var drop: RefCounted = RefCounted.new()

	## 参数 bonus：额外产量；返回值：同一掉落对象用于校验身份。
	func RollLoot(bonus: int) -> Array[RefCounted]:
		received_bonus = bonus
		return [drop]


## 记录协调器实际推进的时间。
class FakeTimeSystem extends Node:
	var TotalTimePassed: int = 0
	var IsNight: bool = false

	## 参数 amount：游戏时间点数；返回值：无。
	func PassTime(amount: int) -> void:
		TotalTimePassed += amount


## 卡片稳定协议夹具。
class FakeCard extends Node2D:
	var terrain: RefCounted
	var interaction_disabled: bool = false

	## 无参数；返回值：当前地形状态。
	func GetTerrainInstanceOrNull() -> RefCounted:
		return terrain

	## 参数 disabled：是否禁用交互；返回值：无。
	func SetInteractionDisabled(disabled: bool) -> void:
		interaction_disabled = disabled


## 记录一次性采集移除源卡的请求。
class FakeBoard extends Node:
	var removed_count: int = 0

	## 参数 _card：被移除的卡片；返回值：无。
	func RemoveCard(_card: Node2D) -> void:
		removed_count += 1


## 返回测试注册名。
## 返回值：聚焦采集规则套件名。
func suite_name() -> String:
	return "shared_gathering_effects"


## 验证两种采集的槽位、标签、下限和基础耗时边界完全一致。
## 返回值：无。
func test_both_interactions_share_tag_slot_and_minimum_rules() -> void:
	var equipment := FakeEquipment.new()
	for script: GDScript in [SINGLE_SCRIPT, REUSABLE_SCRIPT]:
		var interaction: Resource = script.new()
		interaction.set("GatheringTag", &"wood")
		assert_eq(interaction.call("get_effective_time_cost", equipment), 3, "20 基础减去匹配工具17应为3。")
		assert_true(is_equal_approx(float(interaction.call("get_required_hold_seconds", equipment)), 0.3), "3点应显示0.3秒长按。")
		interaction.set("MinimumTimeCost", 5)
		assert_eq(interaction.call("get_effective_time_cost", equipment), 5, "超额减免受到最低耗时限制。")
		interaction.set("EffectiveToolSlot", 6)
		assert_eq(interaction.call("get_effective_time_cost", equipment), 20, "非指定槽位不会提供减免。")
		interaction.set("EffectiveToolSlot", 5)
		interaction.set("GatheringTag", &"earth")
		assert_eq(interaction.call("get_effective_time_cost", equipment), 20, "标签不匹配时没有减免。")
		interaction.set("GatheringTag", &"")
		equipment.tag = &""
		assert_eq(interaction.call("get_effective_time_cost", equipment), 20, "双方空标签也不能触发效果。")
		equipment.tag = &"wood"
		interaction.set("MinimumTimeCost", 0)
		interaction.set("TimeCost", -20)
		assert_eq(interaction.call("get_effective_time_cost", null), 1, "负基础耗时和错误下限最终至少1点。")
	equipment.free()


## 验证两种采集向掉落表传入相同产量，空标签与缺失协议安全返回中性值。
## 返回值：无。
func test_shared_yield_and_empty_protocol() -> void:
	var equipment := FakeEquipment.new()
	var player := FakePlayer.new()
	player.Equipment = equipment
	for script: GDScript in [SINGLE_SCRIPT, REUSABLE_SCRIPT]:
		var interaction: Resource = script.new()
		var table := FakeLootTable.new()
		interaction.set("DropTable", table)
		interaction.set("GatheringTag", &"wood")
		var ops: Array = interaction.call("build_ops", player, FakeTerrain.new())
		assert_eq(table.received_bonus, 3, "匹配工具额外产量应传入掉落表。")
		var found := false
		for op: Dictionary in ops:
			if op.get("type") == "spawn_loot":
				found = op.get("drops")[0] == table.drop
		assert_true(found, "掉落操作保持掉落对象身份。")
		interaction.set("GatheringTag", &"")
		equipment.tag = &""
		interaction.call("build_ops", player, FakeTerrain.new())
		assert_eq(table.received_bonus, 0, "空标签不会为掉落提供额外产量。")
		equipment.tag = &"wood"
	assert_eq(CALCULATOR.get_yield_bonus(RefCounted.new(), &"wood"), 0, "没有查询协议安全返回0。")
	assert_eq(CALCULATOR.get_effective_time_cost(RefCounted.new(), &"wood", 5, 20, 1), 20, "没有耗时协议保持基础耗时。")
	equipment.free()
	player.free()


## 验证长按期间工具和下限改变时仍扣除已显示的快照。
## 返回值：无。
func test_snapshot_survives_equipment_and_config_change() -> void:
	var equipment := FakeEquipment.new()
	var player := FakePlayer.new()
	player.Equipment = equipment
	for script: GDScript in [SINGLE_SCRIPT, REUSABLE_SCRIPT]:
		var interaction: Resource = script.new()
		interaction.set("GatheringTag", &"wood")
		var snapshot: int = interaction.call("get_effective_time_cost", equipment)
		assert_eq(snapshot, 3, "长按开始使用当前工具得出3点快照。")
		equipment.reduction = 0
		interaction.set("MinimumTimeCost", 9)
		var ops: Array = interaction.call("build_ops", player, FakeTerrain.new(), snapshot)
		assert_eq(ops[0].get("amount"), 3, "完成时尊重3点快照，不受后续工具或下限变化影响。")
		ops = interaction.call("build_ops", player, FakeTerrain.new(), -1)
		assert_eq(ops[0].get("amount"), 1, "非法快照安全限制到1点。")
		equipment.reduction = 17
	equipment.free()
	player.free()


## 验证真实世界协调器完成入口消费耗时快照，并区分两种资源点状态。
## 返回值：无。
func test_real_coordinator_entry_uses_snapshot_and_source_rules() -> void:
	var coordinator: Node = COORDINATOR_SCRIPT.new()
	var equipment := FakeEquipment.new()
	var player := FakePlayer.new()
	player.Equipment = equipment
	var port := FakePort.new()
	port.Player = player
	var clock := FakeTimeSystem.new()
	var board := FakeBoard.new()
	coordinator.set("_gameplay_port", port)
	coordinator.set("_time_system", clock)
	coordinator.set("_board_controller", board)
	for script: GDScript in [SINGLE_SCRIPT, REUSABLE_SCRIPT]:
		var interaction: Resource = script.new()
		interaction.set("GatheringTag", &"wood")
		var data := FakeTerrainData.new()
		data.InteractionBehavior = interaction
		var terrain := FakeTerrain.new()
		terrain.TerrainData = data
		var card := FakeCard.new()
		card.terrain = terrain
		var is_reusable: bool = coordinator.call("_is_reusable_gathering", interaction)
		assert_eq(is_reusable, script == REUSABLE_SCRIPT, "耗时查询方法不能把一次性资源误判成重复采集。")
		var holdable: Dictionary = coordinator.call("_try_get_holdable_terrain", card)
		assert_true(bool(holdable.get("ok")), "世界入口应接受可采集地形。")
		assert_eq(holdable.get("action_point_cost"), 3, "真实长按入口应快照工具减免后的3点。")
		equipment.reduction = 0
		var before := clock.TotalTimePassed
		coordinator.call("_complete_terrain_hold", card, terrain, interaction, int(holdable["action_point_cost"]))
		assert_eq(clock.TotalTimePassed - before, 3, "真实完成入口必须实际推进相同3点。")
		if is_reusable:
			assert_eq(terrain.RemainingGatheringCount, 0, "重复采集完成后耗尽默认1次。")
			assert_eq(terrain.RefreshReadyTotalTime, clock.TotalTimePassed + 100, "刷新由完成后的游戏时间计算。")
			assert_true(card.interaction_disabled, "耗尽资源点必须禁用交互。")
			assert_eq(board.removed_count, 1, "重复采集保留卡片，不新增移除请求。")
		else:
			assert_true(terrain.IsHarvested, "一次性采集应标记完成。")
			assert_eq(board.removed_count, 1, "一次性采集最后移除源卡。")
		equipment.reduction = 17
		card.free()
	coordinator.free()
	equipment.free()
	player.free()
	port.free()
	clock.free()
	board.free()
