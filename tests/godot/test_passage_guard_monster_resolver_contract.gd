@tool
extends McpTestSuite

## 驻守怪物解析器 GDScript 生产边界契约。

const RESOLVER_SCRIPT: GDScript = preload("res://core/map/passage_guard_monster_resolver.gd")
## 迁移后的怪物数据与驻守遭遇数据 GDScript 载体（C# 全局类已随物理退役删除）。
const MONSTER_DATA_SCRIPT: GDScript = preload("res://resources/monster/monster_data.gd")
const ENCOUNTER_DATA_SCRIPT: GDScript = preload("res://resources/map/passage_guard_encounter_data.gd")


func suite_name() -> String:
	return "passage_guard_monster_resolver_contract"


## 验证无向边缓存、Resource 池读取、房间清理和控制器生产路径。
func test_production_resolver_contract() -> void:
	var controller_source := FileAccess.get_file_as_string("res://scripts/map_scripts/passage_guard_controller.gd")
	assert_true(
		controller_source.contains("res://core/map/passage_guard_monster_resolver.gd"),
		"生产驻守控制器必须使用 GDScript 怪物解析器。"
	)
	assert_false(
		controller_source.contains("PassageGuardMonsterResolver.new()"),
		"生产驻守控制器不得继续直接实例化 C# 解析器。"
	)

	var monster: Resource = MONSTER_DATA_SCRIPT.new()
	monster.set("MonsterName", "测试木精")
	var encounter: Resource = ENCOUNTER_DATA_SCRIPT.new()
	encounter.get("Monsters").append(monster)
	var pool: Array = [encounter]
	var resolver: RefCounted = RESOLVER_SCRIPT.new()
	var first: Array = resolver.call("Resolve", Vector2i(3, 4), Vector2i(3, 3), pool)
	var second: Array = resolver.call("ResolveResources", Vector2i(3, 3), Vector2i(3, 4), pool)

	assert_true(is_same(first, second), "同一房间的无向通道必须复用同一组怪物数组。")
	assert_eq(first.size(), 1, "解析器必须保留 encounter 中的怪物数量。")
	assert_true(first[0] == monster, "解析器必须保留原 MonsterData Resource 身份。")
	assert_eq(String(first[0].get("MonsterName")), "测试木精", "解析器必须保留怪物字段。")

	resolver.call("BeginRoom")
	var after_reset: Array = resolver.call("Resolve", Vector2i(3, 3), Vector2i(3, 4), pool)
	assert_false(is_same(first, after_reset), "BeginRoom 后必须清除旧房间的边缓存。")
	assert_eq(resolver.call("Resolve", Vector2i.ZERO, Vector2i.ONE, []), [], "空 encounter 池必须返回空数组。")
