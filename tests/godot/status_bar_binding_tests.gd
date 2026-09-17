extends SceneTree

## 状态栏场景绑定回归测试。
##
## 背景（本次修复的 Bug）：
## 局内触发的战斗由 WorldCombatScenePresenter 把 battle.tscn 实例挂到世界主场景 Main 之下，
## 因此战斗进行时 get_tree().current_scene 依然指向 Main，而不是 Battle。
## 旧实现用 current_scene 和全局 "tooltip_panel" 分组查找资源，会分别踩到两个坑：
##   1. 提示框命中 Main 场景里、战斗期间被 HideWorldView() 隐藏的全局 TooltipPanel，导致悬停不显示；
##   2. 玩家实体查找找不到战斗场景自己的 PlayerManager，玩家 Buff 栏目标为空导致不显示任何 Buff。
## 本测试用最小场景复现“局内嵌套”结构，并对照“独立运行战斗场景”结构，断言两种情况下
## 状态栏都必须在自身场景子树内解析提示框与玩家实体。

const TOOLTIP_SCENE: PackedScene = preload("res://scenes/ui_scenes/TooltipPanel.tscn")
const STATUS_BAR_SCRIPT: GDScript = preload("res://scripts/ui_scripts/status_effect_bar.gd")

var _failures: Array[String] = []


func _init() -> void:
	call_deferred(&"_run")


func _run() -> void:
	await _test_tooltip_and_player_resolve_when_battle_is_nested_under_world()
	await _test_tooltip_and_player_resolve_when_battle_is_current_scene()
	_finish()


## 场景一：复现局内触发的战斗（battle.tscn 挂在世界主场景 Main 之下）。
## 该场景是本次 Bug 的直接复现，也是修复必须覆盖的主路径。
func _test_tooltip_and_player_resolve_when_battle_is_nested_under_world() -> void:
	# 1. 世界主场景先入树，并持有随 HUDLayer 一起被隐藏的全局 TooltipPanel。
	var main := Node.new()
	main.name = "Main"
	root.add_child(main)
	current_scene = main

	var world_ui := Node.new()
	world_ui.name = "UI"
	main.add_child(world_ui)

	var hud_layer := CanvasLayer.new()
	hud_layer.name = "HUDLayer"
	world_ui.add_child(hud_layer)

	var hud_root := Control.new()
	hud_root.name = "HUDRoot"
	hud_layer.add_child(hud_root)

	var world_tooltip := TOOLTIP_SCENE.instantiate()
	world_tooltip.name = "TooltipPanel"
	hud_root.add_child(world_tooltip)
	# 战斗期间世界视图会被整体隐藏，这里同步模拟，说明命中该提示框等于完全看不到提示。
	hud_layer.hide()

	# 2. 战斗实例挂到 Main 之下，拥有独立 UI、TooltipPanel 与 PlayerManager/Player 结构。
	var battle := Node2D.new()
	battle.name = "Battle"
	main.add_child(battle)

	var battle_tooltip := _build_battle_subtree(battle, true)

	# 等待两帧让状态栏的 call_deferred("refresh") 执行完毕。
	await process_frame
	await process_frame

	# 3. 先记录根因事实：全局分组的第一顺位确实是主场景里那个被隐藏的提示框。
	var grouped_panels := get_nodes_in_group("tooltip_panel")
	_assert(grouped_panels.size() >= 1, "测试场景应存在 tooltip_panel 分组节点。")
	if grouped_panels.size() > 0:
		_assert(
			grouped_panels[0] == world_tooltip,
			"复现前提：全局分组第一顺位必须是主场景的 TooltipPanel，否则本测试无法覆盖局内隐藏面板的问题。"
		)
	_assert(not hud_layer.visible, "复现前提：战斗期间主场景 HUDLayer 必须处于隐藏状态。")

	_assert_binding(
		battle,
		battle_tooltip,
		battle.get_node_or_null("PlayerManager/Player"),
		"局内嵌套战斗"
	)

	main.free()


## 场景二：对照“直接运行 battle 场景”，确认修复没有破坏独立运行路径。
func _test_tooltip_and_player_resolve_when_battle_is_current_scene() -> void:
	var battle := Node2D.new()
	battle.name = "Battle"
	root.add_child(battle)
	current_scene = battle

	var battle_tooltip := _build_battle_subtree(battle, false)

	await process_frame
	await process_frame

	_assert_binding(
		battle,
		battle_tooltip,
		battle.get_node_or_null("PlayerManager/Player"),
		"独立运行战斗场景"
	)

	battle.free()


## 在给定战斗根节点下搭建 UI/PlayerAttribute/StatusEffectBar 与 PlayerManager/Player 结构。
## 参数 battle_root：战斗场景根节点。
## 参数 with_combat_entity_api：是否给 PlayerManager 挂上 get_combat_entity()，用于区分局内与独立运行两条解析路径。
## 返回值：战斗场景自己的 TooltipPanel，供断言比对。
func _build_battle_subtree(battle_root: Node, with_combat_entity_api: bool) -> Node:
	var battle_ui := Marker2D.new()
	battle_ui.name = "UI"
	battle_root.add_child(battle_ui)

	var battle_tooltip := TOOLTIP_SCENE.instantiate()
	battle_tooltip.name = "TooltipPanel"
	battle_ui.add_child(battle_tooltip)

	var player_manager := Node2D.new()
	player_manager.name = "PlayerManager"
	battle_root.add_child(player_manager)
	if with_combat_entity_api:
		# 用最小脚本模拟 PlayerManager.get_combat_entity()：局内它会返回世界玩家实体，
		# 这里返回本地 Player，断言只关心“状态栏是否定位到了战斗场景自己的 PlayerManager”。
		player_manager.set_script(_make_combat_entity_provider_script())

	var local_player := Node2D.new()
	local_player.name = "Player"
	player_manager.add_child(local_player)

	var components := Node.new()
	components.name = "Components"
	local_player.add_child(components)

	var status_component := Node.new()
	status_component.name = "StatusComponent"
	components.add_child(status_component)

	var player_attribute := VBoxContainer.new()
	player_attribute.name = "PlayerAttribute"
	battle_ui.add_child(player_attribute)

	var status_bar := HBoxContainer.new()
	status_bar.name = "StatusEffectBar"
	status_bar.set_script(STATUS_BAR_SCRIPT)
	status_bar.set("auto_find_player_entity", true)
	player_attribute.add_child(status_bar)

	return battle_tooltip


## 生成只实现 get_combat_entity() 的最小 GDScript，避免为测试新增生产脚本。
## 返回值：可直接 set_script 的 GDScript 实例。
func _make_combat_entity_provider_script() -> GDScript:
	var script := GDScript.new()
	script.source_code = "extends Node2D\n\nfunc get_combat_entity() -> Node:\n\treturn get_node_or_null(\"Player\")\n"
	script.reload()
	return script


## 断言指定战斗场景内玩家 Buff 栏的提示框与实体绑定结果。
## 参数 battle_root：战斗场景根节点。
## 参数 expected_tooltip：期望绑定的战斗场景 TooltipPanel。
## 参数 expected_entity：期望绑定的玩家实体。
## 参数 scenario：场景名称，用于拼装失败信息。
func _assert_binding(battle_root: Node, expected_tooltip: Node, expected_entity: Node, scenario: String) -> void:
	var status_bar := battle_root.get_node_or_null("UI/PlayerAttribute/StatusEffectBar")
	if status_bar == null:
		_failures.append("%s：未找到被测的 StatusEffectBar 节点。" % scenario)
		return

	var resolved_tooltip = status_bar.get("_tooltip_panel")
	_assert(
		resolved_tooltip == expected_tooltip,
		"%s时玩家 Buff 栏必须绑定战斗场景自身的 TooltipPanel，实际绑定：%s。" % [scenario, _describe(resolved_tooltip)]
	)

	var resolved_entity = status_bar.get("_target_entity")
	_assert(
		resolved_entity == expected_entity,
		"%s时玩家 Buff 栏必须绑定战斗场景 PlayerManager 下的玩家实体，实际绑定：%s。" % [scenario, _describe(resolved_entity)]
	)


## 将节点转换为带场景路径的可读描述，便于失败时直接定位绑错的对象。
## 参数 node：待描述的节点，允许为 null。
## 返回值：节点在场景树中的路径；节点无效时返回占位文本。
func _describe(node: Variant) -> String:
	if node == null or not (node is Node) or not is_instance_valid(node):
		return "<null>"
	return String((node as Node).get_path())


func _assert(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("All status bar binding Godot tests passed.")
		quit(0)
		return

	for failure in _failures:
		push_error(failure)
	quit(1)
