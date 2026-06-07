extends SceneTree

## 一次性脚本：根据 map_types.gd 的工厂数据生成 6 个 BiomeDefinition .tres 文件。
##
## 用法（在项目根目录运行）：
##   godot-mono --headless --path . --script res://scripts/generated/create_biome_resources.gd
##
## 输出目录：res://resources/map/biomes/

const OUTPUT_DIR := "res://resources/map/biomes"
const MAP_ENV_BASE := "res://scenes/map_scenes/map_env"

enum Category {
	MAIN = 0,
	TRANSITION = 1,
	TELEPORT = 2,
	MARKET = 3,
}


func _init() -> void:
	print("[CreateBiomeResources] 开始生成群系 .tres 资源...")

	_create_normal()
	_create_earth()
	_create_fire()
	_create_gold()
	_create_water()
	_create_wood()

	print("[CreateBiomeResources] 全部 6 个群系资源已生成到 ", OUTPUT_DIR)
	quit()


func _create_normal() -> void:
	var biome := BiomeDefinition.new()
	biome.biome_name = "normal"
	biome.is_starting_biome = true
	var p := "/normal"

	biome.main_scenes = [
		_make("clear_creek",        p + "/main/clear_creek.tscn",       Category.MAIN, 3, 4),
		_make("common_forest",      p + "/main/common_forest.tscn",     Category.MAIN, 3, 4),
		_make("rolling_hills",      p + "/main/rolling_hills.tscn",     Category.MAIN, 3, 4),
		_make("tranquil_lakeside",  p + "/main/tranquil_lakeside.tscn", Category.MAIN, 3, 4),
		_make("vast_grassland",     p + "/main/vast_grassland.tscn",    Category.MAIN, 3, 4),
	]
	biome.transition_scenes = _trans([
		["abandoned_farmland", "secondary/abandoned_farmland.tscn"],
		["forest_path",        "secondary/forest_path.tscn"],
		["ordinary_wetland",   "secondary/ordinary_wetland.tscn"],
		["riverside_meadow",   "secondary/riverside_meadow.tscn"],
		["valley_pass",        "secondary/valley_pass.tscn"],
	], p)
	biome.teleport_scene = _make("gate_of_ordinariness", p + "/transmitting/gate_of_ordinariness.tscn", Category.TELEPORT, 3, 4)
	biome.market_scene = _make("ordinary_market", p + "/market/ordinary_market.tscn", Category.MARKET, 3, 4)
	_save(biome, "normal_biome.tres")


func _create_earth() -> void:
	var biome := BiomeDefinition.new()
	biome.biome_name = "earth"
	var p := "/earth"

	biome.main_scenes = [
		_make("fossil_cliff",   p + "/main/fossil_cliff.tscn",   Category.MAIN, 3, 4),
		_make("gem_vein",       p + "/main/gem_vein.tscn",       Category.MAIN, 3, 4),
		_make("karst_cave",     p + "/main/karst_cave.tscn",     Category.MAIN, 3, 4),
		_make("meteor_crater",  p + "/main/meteor_crater.tscn",  Category.MAIN, 3, 4),
		_make("rocky_plain",    p + "/main/rocky_plain.tscn",    Category.MAIN, 3, 4),
	]
	biome.transition_scenes = _trans([
		["boulder_maze",      "secondary/boulder_maze.tscn"],
		["crystal_cave",      "secondary/crystal_cave.tscn"],
		["gravel_highland",   "secondary/gravel_highland.tscn"],
		["quicksand_vortex",  "secondary/quicksand_vortex.tscn"],
		["sandstone_canyon",  "secondary/sandstone_canyon.tscn"],
	], p)
	biome.teleport_scene = _make("gate_of_stone", p + "/transmitting/gate_of_stone.tscn", Category.TELEPORT, 3, 4)
	biome.market_scene = _make("stone_market", p + "/market/stone_market.tscn", Category.MARKET, 3, 4)
	_save(biome, "earth_biome.tres")


func _create_fire() -> void:
	var biome := BiomeDefinition.new()
	biome.biome_name = "fire"
	var p := "/fire"

	biome.main_scenes = [
		_make("ash_plain",           p + "/main/ash_plain.tscn",           Category.MAIN, 3, 4),
		_make("lava_riverside",      p + "/main/lava_riverside.tscn",      Category.MAIN, 3, 4),
		_make("obsidian_cliff",      p + "/main/obsidian_cliff.tscn",      Category.MAIN, 3, 4),
		_make("sulfur_rift",         p + "/main/sulfur_rift.tscn",         Category.MAIN, 3, 4),
		_make("volcanic_foothills",  p + "/main/volcanic_foothills.tscn",  Category.MAIN, 3, 4),
	]
	biome.transition_scenes = _trans([
		["ash_hill",           "secondary/ash_hill.tscn"],
		["geothermal_valley",  "secondary/geothermal_valley.tscn"],
		["igneous_cliff",      "secondary/igneous_cliff.tscn"],
		["lava_plateau",       "secondary/lava_plateau.tscn"],
		["sulfur_passage",     "secondary/sulfur_passage.tscn"],
	], p)
	biome.teleport_scene = _make("gate_of_scorched_wilds", p + "/transmitting/gate_of_scorched_wilds.tscn", Category.TELEPORT, 3, 4)
	biome.market_scene = _make("scorched_wilds_exchange", p + "/market/scorched_wilds_exchange.tscn", Category.MARKET, 3, 4)
	_save(biome, "fire_biome.tres")


func _create_gold() -> void:
	var biome := BiomeDefinition.new()
	biome.biome_name = "gold"
	var p := "/gold"

	biome.main_scenes = [
		_make("copper_rust_forest",  p + "/main/copper_rust_forest.tscn",  Category.MAIN, 3, 4),
		_make("gear_wasteland",      p + "/main/gear_wasteland.tscn",      Category.MAIN, 3, 4),
		_make("golden_sand_plain",   p + "/main/golden_sand_plain.tscn",   Category.MAIN, 3, 4),
		_make("iron_ridge_canyon",   p + "/main/iron_ridge_canyon.tscn",   Category.MAIN, 3, 4),
		_make("magnetite_mine",      p + "/main/magnetite_mine.tscn",      Category.MAIN, 3, 4),
	]
	biome.transition_scenes = _trans([
		["alloy_rift_valley",  "secondary/alloy_rift_valley.tscn"],
		["magnetite_hills",    "secondary/magnetite_hills.tscn"],
		["ore_vein_field",     "secondary/ore_vein_field.tscn"],
		["rusted_plains",      "secondary/rusted_plains.tscn"],
		["smelting_ruins",     "secondary/smelting_ruins.tscn"],
	], p)
	biome.teleport_scene = _make("gate_steel_dome", p + "/transmitting/gate_steel_dome.tscn", Category.TELEPORT, 3, 4)
	biome.market_scene = _make("steel_dome_exchange", p + "/market/steel_dome_exchange.tscn", Category.MARKET, 3, 4)
	_save(biome, "gold_biome.tres")


func _create_water() -> void:
	var biome := BiomeDefinition.new()
	biome.biome_name = "water"
	var p := "/water"

	biome.main_scenes = [
		_make("coral_shoal",     p + "/main/coral_shoal.tscn",     Category.MAIN, 3, 4),
		_make("crystal_river",   p + "/main/crystal_river.tscn",   Category.MAIN, 3, 4),
		_make("deep_sea_rift",   p + "/main/deep_sea_rift.tscn",   Category.MAIN, 3, 4),
		_make("frozen_lake",     p + "/main/frozen_lake.tscn",     Category.MAIN, 3, 4),
		_make("waterfall_cave",  p + "/main/waterfall_cave.tscn",  Category.MAIN, 3, 4),
	]
	biome.transition_scenes = _trans([
		["crystal_shoal",          "secondary/crystal_shoal.tscn"],
		["deep_sea_undercurrent",  "secondary/deep_sea_undercurrent.tscn"],
		["frozen_lake_shore",      "secondary/frozen_lake_shore.tscn"],
		["shallow_reef",           "secondary/shallow_reef.tscn"],
		["waterfall_pool",         "secondary/waterfall_pool.tscn"],
	], p)
	biome.teleport_scene = _make("gate_of_surging_sea", p + "/transmitting/gate_of_surging_sea.tscn", Category.TELEPORT, 3, 4)
	biome.market_scene = _make("abyss_sea_market", p + "/market/abyss_sea_market.tscn", Category.MARKET, 3, 4)
	_save(biome, "water_biome.tres")


func _create_wood() -> void:
	var biome := BiomeDefinition.new()
	biome.biome_name = "wood"
	var p := "/wood"

	biome.main_scenes = [
		_make("ancient_tree",        p + "/main/ancient_tree.tscn",        Category.MAIN, 3, 4),
		_make("deep_forest",         p + "/main/deep_forest.tscn",         Category.MAIN, 3, 4),
		_make("sea_of_flowers",      p + "/main/sea_of_flowers.tscn",      Category.MAIN, 3, 4),
		_make("spirit_bamboo_path",  p + "/main/spirit_bamboo_path.tscn",  Category.MAIN, 3, 4),
		_make("vine_swamp",          p + "/main/vine_swamp.tscn",          Category.MAIN, 3, 4),
	]
	biome.transition_scenes = _trans([
		["ancient_root_tunnel",  "secondary/ancient_root_tunnel.tscn"],
		["bamboo_wind_path",     "secondary/bamboo_wind_path.tscn"],
		["honey_meadow",         "secondary/honey_meadow.tscn"],
		["mossy_valley",         "secondary/mossy_valley.tscn"],
		["tree_shadow_path",     "secondary/tree_shadow_path.tscn"],
	], p)
	biome.teleport_scene = _make("gate_of_jade_abyss", p + "/transmitting/gate_of_jade_abyss.tscn", Category.TELEPORT, 3, 4)
	biome.market_scene = _make("jade_abyss_exchange", p + "/market/jade_abyss_exchange.tscn", Category.MARKET, 3, 4)
	_save(biome, "wood_biome.tres")


# ---- helpers ----

func _make(name: String, rel: String, cat: int, min_c: int, max_c: int) -> map_attribute:
	var a := map_attribute.new()
	a.scene_name = name
	a.scene_dir = MAP_ENV_BASE + rel
	a.category = cat
	a.min_connections = min_c
	a.max_connections = max_c
	a.scene_count = 1
	return a


func _trans(base: Array, biome_path: String) -> Array[map_attribute]:
	var out: Array[map_attribute] = []
	for i in range(3):
		for entry in base:
			var nm: String = entry[0]
			var fn: String = entry[1]
			out.append(_make(nm + "_t%d" % (i + 1), biome_path + "/" + fn, Category.TRANSITION, 1, 4))
	return out


func _save(biome: BiomeDefinition, filename: String) -> void:
	var path := OUTPUT_DIR + "/" + filename
	var err := ResourceSaver.save(biome, path)
	if err == OK:
		print("  OK: ", path)
	else:
		printerr("  FAIL: ", path, " (err ", err, ")")
