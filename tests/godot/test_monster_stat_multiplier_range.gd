@tool
extends McpTestSuite

## 怪物遭遇倍率范围 GDScript Resource 的数据契约回归套件。
##
## 套件同时验证独立资源实例与实际地形资产，避免只检查脚本语法而漏掉
## `.tres` / `.tscn` 中仍指向旧 C# Resource 的情况。

const RANGE_SCRIPT: GDScript = preload("res://resources/encounters/monster_stat_multiplier_range.gd")
const TERRAIN_PATHS: Array[String] = [
	"res://resources/map/terrain/earth_terrain.tres",
	"res://resources/map/terrain/fire_terrain.tres",
	"res://resources/map/terrain/gold_terrain.tres",
	"res://resources/map/terrain/normal_terrain.tres",
	"res://resources/map/terrain/reusable_wood_terrain.tres",
	"res://resources/map/terrain/water_terrain.tres",
	"res://resources/map/terrain/wood_terrain.tres",
]


## 返回套件名称，供 MCP 按批次筛选测试。
func suite_name() -> String:
	return "monster_stat_multiplier_range"


## 验证 GDScript Resource 保留原 C# 资源的全部字段默认值与快照结构。
func test_default_values_and_snapshots() -> void:
	var range: Resource = RANGE_SCRIPT.new()
	for property_name: String in [
		"MinMaxHealth", "MinPhysAtk", "MinPhysDef", "MinMagPower", "MinMagResist", "MinSpeed",
		"MaxMaxHealth", "MaxPhysAtk", "MaxPhysDef", "MaxMagPower", "MaxMagResist", "MaxSpeed",
	]:
		assert_true(is_equal_approx(float(range.get(property_name)), 1.0), "%s 默认倍率应为 1。" % property_name)

	var minimums: Dictionary = range.call("get_min")
	var maximums: Dictionary = range.call("get_max")
	assert_eq(minimums["MaxHealth"], 1.0, "下界快照应保留生命倍率字段。")
	assert_eq(maximums["Speed"], 1.0, "上界快照应保留速度倍率字段。")


## 验证配置字段可以独立修改，不会让上下界快照互相污染。
func test_min_and_max_values_are_independent() -> void:
	var range: Resource = RANGE_SCRIPT.new()
	range.set("MinPhysAtk", 0.9)
	range.set("MaxPhysAtk", 1.2)
	var minimums: Dictionary = range.call("get_min")
	var maximums: Dictionary = range.call("get_max")
	assert_true(is_equal_approx(float(minimums["PhysAtk"]), 0.9), "下界应读取 MinPhysAtk。")
	assert_true(is_equal_approx(float(maximums["PhysAtk"]), 1.2), "上界应读取 MaxPhysAtk。")
	assert_true(is_equal_approx(float(minimums["PhysDef"]), 1.0), "修改攻击倍率不应污染防御倍率。")


## 验证所有地形倍率子资源均已切换到 GDScript Resource。
func test_terrain_assets_use_gdscript_range() -> void:
	for terrain_path: String in TERRAIN_PATHS:
		var profile: Resource = load(terrain_path)
		assert_true(profile != null, "%s 必须能够加载。" % terrain_path)
		var range: Resource = profile.get("EncounterVarianceRange")
		assert_true(range != null, "%s 必须保留遭遇倍率范围。" % terrain_path)
		assert_eq(
			range.get_script().resource_path,
			"res://resources/encounters/monster_stat_multiplier_range.gd",
			"%s 必须使用 GDScript 倍率范围资源。" % terrain_path
		)
