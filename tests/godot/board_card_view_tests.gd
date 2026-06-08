extends SceneTree

const BOARD_CONTROLLER_SCRIPT := "res://core/board/BoardController.cs"
const BOARD_CARD_VIEW_SCENE := "res://scenes/board_card_scene/BoardCardView.tscn"
const TERRAIN_INSTANCE_SCRIPT := "res://resources/interaction/TerrainInstance.cs"
const TERRAIN_CARD_DATA_SCRIPT := "res://resources/interaction/TerrainCardData.cs"

var _failures: Array[String] = []


func _init() -> void:
	call_deferred(&"_run")


func _run() -> void:
	await _test_spawned_terrain_card_uses_exported_resting_scale()
	_finish()


func _test_spawned_terrain_card_uses_exported_resting_scale() -> void:
	var controller = load(BOARD_CONTROLLER_SCRIPT).new()
	controller.CardViewScene = load(BOARD_CARD_VIEW_SCENE)
	controller.CardsRootPath = NodePath("")
	root.add_child(controller)
	await process_frame

	var terrain_data = load(TERRAIN_CARD_DATA_SCRIPT).new()
	terrain_data.CardName = "测试地形"
	var terrain = load(TERRAIN_INSTANCE_SCRIPT).new()
	terrain.LocalGridPos = Vector2i.ZERO
	terrain.TerrainData = terrain_data

	var card = controller.SpawnTerrainCard(terrain, Vector2(100, 100))
	_assert(
		card != null,
		"地形卡生成应返回有效的 BoardCardView。"
	)

	if card == null:
		controller.queue_free()
		await process_frame
		return

	var configured_scale := float(card.get("TerrainCardRestingScale"))
	_assert(
		configured_scale > 1.0,
		"地形卡默认静止缩放应大于普通卡，避免 32x32 CardIcon 以原始尺寸显示。"
	)
	_assert(
		card.scale == Vector2(configured_scale, configured_scale),
		"地形卡生成后应使用导出的静止缩放配置，不能把倍率写死在测试或代码路径里。"
	)

	var tuned_scale := configured_scale + 0.5
	card.set("TerrainCardRestingScale", tuned_scale)
	card.RefreshView()
	_assert(
		card.scale == Vector2(tuned_scale, tuned_scale),
		"微调导出的地形卡缩放后，RefreshView 应使用新的配置值。"
	)

	controller.queue_free()
	await process_frame


func _assert(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("All board card view Godot tests passed.")
		quit(0)
		return

	for failure in _failures:
		push_error(failure)
	quit(1)
