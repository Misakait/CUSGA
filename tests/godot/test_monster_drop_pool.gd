@tool
extends McpTestSuite

## 检验怪物加权掉落池与战斗掉落收集边界。
const POOL: GDScript = preload("res://resources/loot/monster_drop_pool.gd")
const ENTRY: GDScript = preload("res://resources/loot/monster_drop_entry.gd")
const ITEM: GDScript = preload("res://resources/item/item_data.gd")
const STACK: GDScript = preload("res://resources/item/item_stack.gd")
const MONSTER: GDScript = preload("res://resources/monster/monster_data.gd")
const COLLECTOR: GDScript = preload("res://core/gameflow/battle_loot_collector.gd")

## 记录世界掉落生成请求的棋盘替身。
class FakeBoard extends Node:
	var calls: int = 0
	var stacks: Array = []
	var origin: Vector2 = Vector2.ZERO
	func SpawnLootCards(input: Array, at: Vector2) -> void:
		calls += 1
		stacks = input.duplicate()
		origin = at

## 返回测试套件名称。
func suite_name() -> String:
	return "monster_drop_pool"

## 创建指定物品与权重的条目。
func _entry(item: Resource, weight: int) -> MonsterDropEntry:
	var entry: MonsterDropEntry = ENTRY.new()
	entry.drop_item = item
	entry.drop_weight = weight
	return entry

## 按固定随机种子逐次核对权重区间与空结果。
func test_weighted_draws_include_empty_and_are_independent() -> void:
	var pool: MonsterDropPool = POOL.new()
	var wood: Resource = ITEM.new()
	var embryo: Resource = ITEM.new()
	var universal: Resource = ITEM.new()
	pool.draw_count = 100
	pool.entries.assign([_entry(wood, 50), _entry(embryo, 50), _entry(universal, 10), _entry(null, 50), _entry(wood, 0)])
	var actual_rng := RandomNumberGenerator.new()
	actual_rng.seed = 12345
	var expected_rng := RandomNumberGenerator.new()
	expected_rng.seed = 12345
	var expected: Array[Resource] = []
	for index in 100:
		var roll: int = expected_rng.randi_range(1, 160)
		if roll <= 50:
			expected.append(wood)
		elif roll <= 100:
			expected.append(embryo)
		elif roll <= 110:
			expected.append(universal)
	var result: Array = pool.RollLoot(0, actual_rng)
	assert_eq(result.size(), expected.size(), "空结果不能生成堆叠")
	for index in mini(result.size(), expected.size()):
		assert_eq(result[index].get("Item"), expected[index], "每次抽取应命中对应权重区间")
		assert_eq(result[index].get("Amount"), 1, "单次命中生成一件物品")

## 验证空池、无权重和默认 5 次抽取。
func test_empty_pool_and_default_draw_count() -> void:
	var pool: MonsterDropPool = POOL.new()
	assert_eq(pool.draw_count, 5, "默认应抽取五次")
	assert_true(pool.RollLoot().is_empty(), "空池不得生成物品")
	var item: Resource = ITEM.new()
	pool.entries.append(_entry(item, 1))
	assert_eq(pool.RollLoot().size(), 5, "唯一物品应抽中五次")
	pool.draw_count = 0
	assert_true(pool.RollLoot().is_empty(), "零次抽取不得生成物品")
	pool.draw_count = 5
	pool.entries[0].drop_weight = 0
	assert_true(pool.RollLoot().is_empty(), "总权重为零时不得生成物品")

## 每个新怪物应拥有独立的可配置空掉落池。
func test_monsters_have_independent_default_pools() -> void:
	var first: Resource = MONSTER.new()
	var second: Resource = MONSTER.new()
	var first_pool: MonsterDropPool = first.get("drop_pool")
	var second_pool: MonsterDropPool = second.get("drop_pool")
	assert_true(first_pool != null and second_pool != null, "每个怪物均应有空池")
	assert_true(first_pool != second_pool, "不同怪物不得共用可变默认池")
	first_pool.draw_count = 3
	assert_eq(second_pool.draw_count, 5, "修改一个怪物不得影响另一个怪物")

## 所有生产怪物资源均可加载，并使用怪物专用掉落池。
func test_monster_assets_load_with_drop_pool() -> void:
	var directory: DirAccess = DirAccess.open("res://resources/monster")
	assert_true(directory != null, "怪物资源目录必须存在")
	if directory == null:
		return
	for file_name: String in directory.get_files():
		if not file_name.ends_with(".tres"):
			continue
		var path: String = "res://resources/monster".path_join(file_name)
		var monster: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		assert_true(monster != null, "%s 必须可加载" % path)
		if monster == null:
			continue
		assert_true(monster.get("drop_pool") is MonsterDropPool, "%s 必须具有怪物掉落池" % path)
		var source: String = FileAccess.get_file_as_string(path)
		assert_false(source.contains("LootTable ="), "%s 不得继续绑定旧技能卡掉落表" % path)

## 怪物资源保存后应能恢复独立配置，供检查器配置实际怪物时使用。
func test_configured_pool_survives_resource_save_and_reload() -> void:
	var monster: Resource = MONSTER.new()
	var pool: MonsterDropPool = monster.get("drop_pool")
	pool.draw_count = 7
	pool.entries.append(_entry(null, 50))
	var path: String = "user://monster_drop_pool_contract_%d.tres" % OS.get_process_id()
	var error: Error = ResourceSaver.save(monster, path)
	assert_eq(error, OK, "配置后的怪物应能保存")
	if error != OK:
		return
	var restored: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_true(restored != null, "保存后的怪物应能重新加载")
	if restored != null:
		var restored_pool: MonsterDropPool = restored.get("drop_pool")
		assert_eq(restored_pool.draw_count, 7, "应恢复配置的抽取次数")
		assert_eq(restored_pool.entries.size(), 1, "应恢复掉落条目")
		if restored_pool.entries.size() == 1:
			assert_eq(restored_pool.entries[0].drop_weight, 50, "应恢复空结果权重")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

## 胜利只投放一次，失败不投放。
func test_battle_collector_emits_only_once_on_victory() -> void:
	var board: Node = track(FakeBoard.new())
	var player: Node2D = track(Node2D.new())
	player.position = Vector2(321, 123)
	var collector: Node = track(COLLECTOR.new())
	collector.call("Configure", board, player)
	var stack: RefCounted = STACK.new()
	stack.call("SetItem", ITEM.new(), 1)
	collector.call("_on_entity_dropped", Vector2.ZERO, [stack])
	collector.call("_on_battle_ended", true)
	collector.call("_on_battle_ended", true)
	assert_eq(board.get("calls"), 1, "胜利掉落只能投放一次")
	assert_eq(board.get("stacks").size(), 1, "应保留怪物掉落堆叠")
	assert_eq(board.get("origin"), Vector2(321, 123), "掉落应使用玩家世界位置")
	var failed: Node = track(COLLECTOR.new())
	failed.call("Configure", board, player)
	failed.call("_on_entity_dropped", Vector2.ZERO, [stack])
	failed.call("_on_battle_ended", false)
	assert_eq(board.get("calls"), 1, "失败时不得向世界投放掉落")
