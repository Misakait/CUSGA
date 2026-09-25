@tool
extends McpTestSuite

## Item 场景与房间掉落仓库的回归契约。
##
## 这些测试只锁定跨模块边界：动画不能改命中节点，掉落不能阻挡玩家，
## 快照不能因为资源路径失效而丢掉仍可由 CardId 找到的物品。

const ITEM_SCENE: PackedScene = preload("res://scenes/ItemTerrian/Item.tscn")
const ITEM_STACK_SCRIPT: GDScript = preload("res://resources/item/item_stack.gd")
const LOOT_STORE_SCRIPT: GDScript = preload("res://core/map/room_loot_store.gd")
const ITEM_RESOURCE_PATH: String = "res://items/item1.tres"


func suite_name() -> String:
	return "item_room_content"


func test_idle_and_hover_only_transform_visuals() -> void:
	var scene_text: String = FileAccess.get_file_as_string("res://scenes/ItemTerrian/Item.tscn")
	assert_true(scene_text.contains("resource_name = \"Idle\""), "Item 必须提供 Idle 动画。")
	assert_true(scene_text.contains("resource_name = \"Hover\""), "Item 必须提供 Hover 动画。")

	var item: Node2D = ITEM_SCENE.instantiate() as Node2D
	track(item)
	var animation_player: AnimationPlayer = item.get_node("AnimationPlayer") as AnimationPlayer
	var library: AnimationLibrary = animation_player.get_animation_library("")
	for animation_name: StringName in [&"Idle", &"Hover"]:
		var animation: Animation = library.get_animation(animation_name)
		assert_true(animation != null, "%s 动画必须存在。" % animation_name)
		if animation == null:
			continue
		for track_index in animation.get_track_count():
			var path: String = str(animation.track_get_path(track_index))
			assert_false(path.contains(":position"), "%s 不得改变位置轨道。" % animation_name)
			assert_false(path.contains(":rotation"), "%s 不得改变旋转轨道。" % animation_name)
			assert_true(path.begins_with("Visuals:"), "%s 只能驱动 Visuals 子树。" % animation_name)


func test_loot_disables_physics_but_keeps_mouse_hit() -> void:
	var item: Node2D = ITEM_SCENE.instantiate() as Node2D
	get_tree().root.add_child(item)
	track(item)
	var stack: RefCounted = ITEM_STACK_SCRIPT.new() as RefCounted
	stack.call("SetItem", load(ITEM_RESOURCE_PATH) as Resource, 2)
	item.call("InitializeLoot", stack)
	await get_tree().process_frame
	var collision: CollisionShape2D = item.get_node("Collision") as CollisionShape2D
	var interaction: Area2D = item.get_node("Interaction") as Area2D
	assert_true(collision.disabled, "掉落物 Collision 必须关闭，不能阻挡玩家。")
	assert_eq(int(item.collision_layer), 0, "掉落物根节点不能加入物理碰撞层。")
	assert_true(interaction.input_pickable, "掉落物 Interaction 必须保留鼠标命中。")


func test_loot_snapshot_preserves_rolled_attributes_and_card_id_fallback() -> void:
	var store: Node = LOOT_STORE_SCRIPT.new()
	track(store)
	var stack: RefCounted = ITEM_STACK_SCRIPT.new() as RefCounted
	stack.call("SetItem", load(ITEM_RESOURCE_PATH) as Resource, 3)
	stack.set("RolledAttributes", {"PhysAtk": 4})
	var record: Dictionary = store.call("AddLoot", Vector2i(2, 3), stack, Vector2(120, 240))
	var encoded: Dictionary = store.call("SnapshotEncoded")
	var encoded_record: Dictionary = encoded["rooms"]["2,3"][0]
	assert_eq(encoded_record.get("rolled", {}).get("PhysAtk"), 4, "掉落快照必须保留洗炼属性。")

	# 模拟资源路径迁移：恢复时只能依赖稳定 CardId，仍应找回同一个掉落。
	encoded_record["path"] = "res://items/missing_after_migration.tres"
	var restored: Node = LOOT_STORE_SCRIPT.new()
	track(restored)
	restored.call("RestoreEncoded", encoded)
	var restored_records: Array = restored.call("GetLoot", Vector2i(2, 3))
	assert_eq(restored_records.size(), 1, "有效 CardId 应能在资源路径失效时恢复掉落。")
	if restored_records.size() == 1:
		var restored_stack: RefCounted = restored_records[0].get("stack") as RefCounted
		assert_eq(restored_stack.get("Amount"), 3, "恢复后的掉落数量必须保持。")
		assert_eq(restored_stack.get("RolledAttributes").get("PhysAtk"), 4, "恢复后的洗炼属性必须保持。")

