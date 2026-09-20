@tool
extends McpTestSuite

## BoardCardView GDScript 生产视图的跨语言契约套件。

const BOARD_CARD_SCENE: PackedScene = preload("res://scenes/board_card_scene/BoardCardView.tscn")
const ITEM_DATA_SCRIPT: GDScript = preload("res://resources/item/item_data.gd")
const TERRAIN_DATA_SCRIPT: GDScript = preload("res://resources/interaction/terrain_card_data.gd")


## 提供 GodotAI 使用的稳定套件名称。
func suite_name() -> String:
	return "board_card_view_contract"


## 提供视图所需的最小地形实例协议，不依赖旧 C# BoardCardState。
class FakeTerrain extends RefCounted:
	var TerrainData: Resource


## 提供视图所需的最小 ItemStack 协议。
class FakeStack extends RefCounted:
	var Item: Resource
	var Amount: int = 1
	var IsEmpty: bool = false


## 验证生产场景脚本、序列化节点、初始化协议、缩放、数量和信号名称。
func test_production_board_card_view_contract() -> void:
	var scene_text := FileAccess.get_file_as_string("res://scenes/board_card_scene/BoardCardView.tscn")
	assert_true(scene_text.contains("res://core/board/board_card_view.gd"), "生产棋盘卡场景必须切换到 GDScript 视图。")
	assert_false(scene_text.contains("res://core/board/BoardCardView.cs"), "生产棋盘卡场景不得继续引用 C# 视图。")
	var source_text := FileAccess.get_file_as_string("res://core/board/board_card_view.gd")
	for method_name: String in [
		"GetCardData", "GetCardDisplayName", "IsLootCard", "IsTerrainCard",
		"GetLootStackOrNull", "GetTerrainInstanceOrNull", "GetTerrainDataOrNull",
		"InitializeTerrain", "InitializeLoot", "RefreshView", "PlayScatterFrom",
		"PlayFlyTo", "SetHighlighted", "SetInteractionDisabled"
	]:
		assert_true(source_text.contains("func %s" % method_name), "视图必须保留 %s PascalCase 方法。" % method_name)
	for signal_name: String in ["Clicked", "Pressed", "Released", "HoverStarted", "HoverEnded"]:
		assert_true(source_text.contains("signal %s" % signal_name), "视图必须保留 %s 信号。" % signal_name)

	var scene_tree := Engine.get_main_loop() as SceneTree
	var card := BOARD_CARD_SCENE.instantiate() as Node2D
	scene_tree.root.add_child(card)
	var terrain_data: Resource = TERRAIN_DATA_SCRIPT.new()
	terrain_data.set("CardName", "测试地形")
	var terrain := FakeTerrain.new()
	terrain.TerrainData = terrain_data
	card.call("InitializeTerrain", terrain)
	assert_true(bool(card.call("IsTerrainCard")), "地形初始化后必须识别为地形卡。")
	assert_eq(String(card.call("GetCardDisplayName")), "测试地形", "地形卡标题必须读取 CardName。")
	assert_eq(card.scale, Vector2(3.0, 3.0), "地形卡静止缩放必须保持 3 倍。")

	var item: Resource = ITEM_DATA_SCRIPT.new()
	item.set("CardName", "测试掉落")
	var stack := FakeStack.new()
	stack.Item = item
	stack.Amount = 3
	card.call("InitializeLoot", stack)
	assert_true(bool(card.call("IsLootCard")), "掉落初始化后必须识别为掉落卡。")
	assert_eq(String(card.call("GetCardDisplayName")), "测试掉落", "掉落卡标题必须读取 Item.CardName。")
	assert_eq(card.get_node("Amount").text, "3", "掉落数量必须保持原数量显示。")
	assert_eq(card.scale, Vector2.ONE, "掉落卡静止缩放必须保持一倍。")

	var pressed_count := [0]
	var pressed_callback := func(_card: Node2D) -> void:
		pressed_count[0] += 1
	card.connect("Pressed", pressed_callback)
	card.emit_signal("Pressed", card)
	assert_eq(pressed_count[0], 1, "Pressed 信号参数和名称必须保持。")
	card.call("SetInteractionDisabled", true)
	assert_false(bool(card.get("input_pickable")), "禁用卡牌必须关闭输入。")
	assert_true(float(card.modulate.r) < 1.0, "禁用卡牌必须变灰。")
	card.call("SetInteractionDisabled", false)
	assert_true(bool(card.get("input_pickable")), "恢复卡牌必须重新允许输入。")
	assert_eq(card.modulate, Color.WHITE, "恢复卡牌必须还原白色。")
	card.disconnect("Pressed", pressed_callback)
	card.queue_free()
