@tool
extends McpTestSuite

## 战斗行动条行动值显示契约。
##
## 锁定三条行为：
## 1. 当前正在行动的角色只显示名字，不显示行动值；
## 2. 后续每个预测槽位显示「该角色距离这次行动还差多少行动值」；
## 3. 同一个角色在轴内出现多次时，每次使用各自的距离，而不是复用当前行动值。

const TIMELINE_SCRIPT: GDScript = preload("res://scripts/ui_scripts/action_timeline.gd")


## 构造一个只暴露行动条所需字段的战斗实体。
class FakeCombatant extends Node:
	var action_value: float = 0.0
	var speed: float = 100.0
	var hp: float = 100.0

	func _init(display_name: String, initial_av: float, initial_speed: float = 100.0) -> void:
		name = display_name
		action_value = initial_av
		speed = initial_speed


func _scene_tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func suite_name() -> String:
	return "action_timeline_action_value_contract"


## 读取指定槽位的文本，避免测试直接依赖 Label 的内部结构。
## 参数 timeline：行动条实例。
## 参数 index：槽位索引。
## 返回值：该槽位当前显示的文字。
func _label_text(timeline: ActionTimeline, index: int) -> String:
	var label: Label = timeline.active_labels[index]
	return label.text


func test_current_actor_hides_action_value_and_future_slots_show_distance() -> void:
	var timeline: ActionTimeline = TIMELINE_SCRIPT.new()
	timeline.max_timeline_slots = 4
	_scene_tree().root.add_child(timeline)

	var player: Node = FakeCombatant.new("Player", 0.0)
	var monster: Node = FakeCombatant.new("Monster", 7.0, 50.0)
	monster.set_meta("MonsterName", "怪物")

	timeline.call("update_timeline", [player, monster], player, 500.0)

	assert_eq(timeline.active_labels.size(), 4, "四个预测槽位都必须生成标签。")
	assert_eq(_label_text(timeline, 0), "玩家", "当前行动角色不能显示行动值。")
	assert_eq(_label_text(timeline, 1), "玩家  5", "统一为 1 行动值 = 1 时间点后，首个后续槽位应显示 5 点距离。")
	assert_eq(_label_text(timeline, 2), "怪物  7", "第三个槽位必须显示从当前时刻累计的 5 + 2 = 7 点距离。")
	assert_eq(_label_text(timeline, 3), "玩家  10", "第四个槽位必须继续累计到 5 + 2 + 3 = 10 点距离。")

	timeline.queue_free()
	player.queue_free()
	monster.queue_free()


func test_current_actor_stays_hidden_even_when_its_action_value_is_nonzero() -> void:
	var timeline: ActionTimeline = TIMELINE_SCRIPT.new()
	timeline.max_timeline_slots = 3
	_scene_tree().root.add_child(timeline)

	var player: Node = FakeCombatant.new("Player", 4.0)
	var monster: Node = FakeCombatant.new("Monster", 5.0)
	monster.set_meta("MonsterName", "怪物")

	timeline.call("update_timeline", [player, monster], player, 500.0)

	assert_eq(_label_text(timeline, 0), "玩家", "当前行动角色即使行动值非零也不能显示数字。")
	assert_eq(_label_text(timeline, 1), "玩家  4", "当前角色下一次行动必须先显示自己的 4 点距离。")
	assert_eq(_label_text(timeline, 2), "怪物  5", "怪物的槽位必须显示累计到 4 + 1 = 5 点距离。")

	timeline.queue_free()
	player.queue_free()
	monster.queue_free()


func test_action_value_is_rounded_to_whole_number() -> void:
	var timeline: ActionTimeline = TIMELINE_SCRIPT.new()
	timeline.max_timeline_slots = 4
	_scene_tree().root.add_child(timeline)

	var player: Node = FakeCombatant.new("Player", 0.0)
	var monster: Node = FakeCombatant.new("Monster", 12.6)
	monster.set_meta("MonsterName", "怪物")

	timeline.call("update_timeline", [player, monster], player, 500.0)

	assert_eq(_label_text(timeline, 0), "玩家", "当前行动角色不能显示行动值。")
	assert_eq(_label_text(timeline, 3), "怪物  13", "行动值必须四舍五入到整数显示。")

	timeline.queue_free()
	player.queue_free()
	monster.queue_free()
