@tool
extends McpTestSuite

## 玩家键盘接管鼠标移动时清理旧请求的回归套件。

const CLICK_WALK_SCRIPT: GDScript = preload("res://scripts/player_scripts/states/ClickWalk.gd")
const WALK_SCRIPT: GDScript = preload("res://scripts/player_scripts/states/Walk.gd")
const STATE_MACHINE_SCRIPT: GDScript = preload("res://scripts/player_scripts/PlayerStateMachine.gd")


class FakeAnimationState:
	extends RefCounted
	var traveled_animations: Array[StringName] = []

	func travel(animation: StringName) -> void:
		traveled_animations.append(animation)


class FakePlayer:
	extends CharacterBody2D
	var anim_state := FakeAnimationState.new()


## 返回 GodotAI 使用的稳定套件名称。
## @return 玩家移动输入契约套件名。
func suite_name() -> String:
	return "player_movement_input_contract"


## 验证进入键盘行走时清除点击目标，同时保留走路动画。
## @return 无返回值。
func test_keyboard_takeover_clears_mouse_request() -> void:
	var machine := STATE_MACHINE_SCRIPT.new() as StateMachine
	var click_walk := CLICK_WALK_SCRIPT.new() as ClickWalkState
	var walk := WALK_SCRIPT.new() as Walk_
	var player := FakePlayer.new()
	machine.states["clickwalk"] = click_walk
	walk.state_machine = machine
	walk.player = player
	click_walk.set("_target_world_position", Vector2(100.0, 200.0))
	click_walk.set("_has_target", true)

	walk.enter()

	assert_false(bool(click_walk.has_movement_request()), "键盘接管后不得保留鼠标移动请求。")
	assert_false(bool(click_walk.get("_has_target")), "键盘接管后必须清除已记录的鼠标目标。")
	assert_eq(player.anim_state.traveled_animations, [&"walk"], "进入键盘行走后仍须播放原有走路动画。")

	player.free()
	walk.free()
	click_walk.free()
	machine.free()
