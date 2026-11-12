@tool
extends McpTestSuite

## 物品交互减速契约套件（TDD）。
##
## 锁定四件事：玩家有效速度在交互时保留 20%、键盘与鼠标两条移动路径都读同一有效速度、
## 协调器在有效地形长按开始时减速并在所有清理路径只恢复一次、建筑/UI 等非物品入口不被误伤。

const PLAYER_CHAR_SCRIPT: GDScript = preload("res://scripts/player_scripts/PlayerChar.gd")
const PLAYER_DATA_SCRIPT: GDScript = preload("res://scripts/player_scripts/PlayerData.gd")
const COORDINATOR_SCRIPT: GDScript = preload("res://core/gameflow/world_interaction_coordinator.gd")
const PLAYER_CHAR_PATH: String = "res://scripts/player_scripts/PlayerChar.gd"
const COORDINATOR_PATH: String = "res://core/gameflow/world_interaction_coordinator.gd"
const CLICK_WALK_PATH: String = "res://scripts/player_scripts/states/ClickWalk.gd"


## 玩家替身：只记录物品交互协议的调用次数，不依赖生产 PlayerChar。
class StubPlayer extends Node2D:
	var begin_calls: int = 0
	var end_calls: int = 0

	## 记录一次进入物品交互减速。
	## @return 无返回值。
	func BeginItemInteraction() -> void:
		begin_calls += 1

	## 记录一次退出物品交互减速。
	## @return 无返回值。
	func EndItemInteraction() -> void:
		end_calls += 1


## 地形卡替身：只实现清理路径会调用的抖动协议。
class StubCard extends Node2D:
	## 记录 SetDestroying 的实参。
	var destroying_calls: Array = []

	## 记录一次抖动状态切换。
	## @param destroying 目标抖动状态。
	## @return 无返回值。
	func SetDestroying(destroying: bool) -> void:
		destroying_calls.append(destroying)


## 返回 GodotAI 使用的稳定套件名称。
## @return 物品交互减速套件名。
func suite_name() -> String:
	return "item_interaction_move_slowdown"


## 玩家有效速度：未交互为基础速度，交互期间为 20%，结束与重复结束都恢复。
## @return 无返回值。
func test_effective_speed_uses_twenty_percent_during_interaction() -> void:
	var player := PLAYER_CHAR_SCRIPT.new() as CharacterBody2D
	var data: PlayerData = PLAYER_DATA_SCRIPT.new() as PlayerData
	data.walk_speed = 500.0
	player.set("player_data", data)

	var has_speed_api: bool = player.has_method("get_effective_walk_speed")
	assert_true(has_speed_api, "玩家必须提供 get_effective_walk_speed()，否则两条移动路径无法共用同一速度口径。")
	if not has_speed_api:
		player.free()
		return

	var multiplier: Variant = player.get("item_interaction_speed_multiplier")
	assert_eq(float(multiplier) if multiplier != null else -1.0, 0.2,
		"物品交互减速倍率默认必须保留 20% 的移动速度。")
	assert_true(player.has_method("BeginItemInteraction"), "玩家必须提供开始物品交互的公共入口。")
	assert_true(player.has_method("EndItemInteraction"), "玩家必须提供结束物品交互的公共入口。")

	assert_eq(float(player.call("get_effective_walk_speed")), 500.0, "未交互时必须保持基础速度。")
	player.call("BeginItemInteraction")
	assert_eq(float(player.call("get_effective_walk_speed")), 100.0, "交互期间必须降到基础速度的 20%。")
	player.call("BeginItemInteraction")
	assert_eq(float(player.call("get_effective_walk_speed")), 100.0, "重复开始不得叠乘减速倍率。")
	player.call("EndItemInteraction")
	assert_eq(float(player.call("get_effective_walk_speed")), 500.0, "交互结束必须恢复基础速度。")
	player.call("EndItemInteraction")
	assert_eq(float(player.call("get_effective_walk_speed")), 500.0, "重复结束不得产生负倍率或残留减速。")

	player.set("item_interaction_speed_multiplier", 0.5)
	player.call("BeginItemInteraction")
	assert_eq(float(player.call("get_effective_walk_speed")), 250.0,
		"减速比例必须来自可配置倍率，不能硬编码 0.2。")
	player.call("EndItemInteraction")

	player.free()


## 两条移动路径必须共用有效速度，不能在状态脚本里继续直接乘基础 `walk_speed`。
## @return 无返回值。
func test_movement_paths_use_effective_speed() -> void:
	var player_source: String = FileAccess.get_file_as_string(PLAYER_CHAR_PATH)
	var click_source: String = FileAccess.get_file_as_string(CLICK_WALK_PATH)

	assert_true(player_source.contains("@export_range(0.0, 1.0, 0.01)"),
		"减速倍率必须在玩家 Inspector 中导出并限制在 0～1。")

	var move_body: String = _function_body(player_source, "func move_player(")
	assert_true(move_body.contains("get_effective_walk_speed()"),
		"键盘移动必须读取有效速度，不能直接使用 player_data.walk_speed。")

	var click_body: String = _function_body(click_source, "func physics_update(")
	assert_true(click_body.contains("get_effective_walk_speed"),
		"鼠标点击移动必须读取有效速度，否则只减速键盘一条路径。")
	assert_true(click_body.contains("direction * walk_speed"),
		"鼠标目标速度必须使用有效速度，不能继续乘基础 walk_speed。")
	assert_true(click_body.contains("walk_speed * 12.0 * delta"),
		"鼠标加速量必须使用有效速度，否则减速时仍会瞬间冲速。")


## 协调器的清理路径必须在所有取消/完成分支恢复速度，且重复清理不重复调用。
## @return 无返回值。
func test_coordinator_restores_speed_on_clear() -> void:
	var player := track(StubPlayer.new()) as StubPlayer
	var card := track(StubCard.new()) as StubCard
	var coordinator := track(COORDINATOR_SCRIPT.new()) as Node
	coordinator.set("_player_char", player)
	coordinator.set("_active_terrain_hold_card", card)
	coordinator.set("_player_click_walk_state", null)

	coordinator.call("_set_player_item_interaction_slowed", true)
	assert_eq(player.begin_calls, 1, "协调器必须能把开始减速转发给玩家协议。")

	coordinator.call("_clear_active_terrain_hold")
	assert_eq(player.end_calls, 1, "清理地形长按必须且只能恢复一次全速。")
	assert_eq(card.destroying_calls, [false], "清理地形长按仍须复位卡牌抖动。")

	coordinator.call("_clear_active_terrain_hold")
	assert_eq(player.end_calls, 1, "重复清理不得重复调用结束协议。")


## 源码形状：开始减速必须排在可长按校验之后、begin_hold 之前。
## @return 无返回值。
func test_coordinator_starts_slowdown_before_hold() -> void:
	var source: String = FileAccess.get_file_as_string(COORDINATOR_PATH)
	var press_body: String = _function_body(source, "func _on_board_card_pressed(card: Node2D) -> void:")

	var slow_index: int = press_body.find("_set_player_item_interaction_slowed(true)")
	var holdable_index: int = press_body.find("_try_get_holdable_terrain")
	var begin_hold_index: int = press_body.find("_hold_interaction_controller.call(")
	assert_true(slow_index >= 0, "有效地形长按开始时必须通知玩家减速。")
	assert_true(slow_index > holdable_index,
		"必须先确认目标可长按再减速，掉落物、超范围与建筑入口不得误触。")
	assert_true(slow_index < begin_hold_index,
		"必须在 begin_hold 之前减速，零耗时完成回调才能立即恢复全速。")

	var clear_body: String = _function_body(source, "func _clear_active_terrain_hold() -> void:")
	assert_true(clear_body.contains("_set_player_item_interaction_slowed(false)"),
		"完成、松开、走远、切目标与场景卸载都必须走同一恢复入口。")


## 截取一个顶层函数的源码片段：从签名行起到该函数末尾。
## @param source 完整脚本源码。
## @param signature 目标函数的签名片段（含 func 关键字）。
## @return 该函数的源码片段；签名不存在时返回空字符串。
func _function_body(source: String, signature: String) -> String:
	var start: int = source.find(signature)
	if start < 0:
		return ""
	var tail: String = source.substr(start)
	var end: int = tail.find("\n\n\n")
	if end < 0:
		return tail
	return tail.substr(0, end)
