extends Node2D

## 地图类型管理器 — 管理 6 个生态群系的场景定义。
##
## 群系数据来源（按优先级）：
## 1. Inspector 中手动配置的 biome_definitions 数组（编辑器中可视化编辑）
## 2. 若数组为空，自动从 resources/map/biomes/ 加载 .tres 文件作为默认值
##
## 要修改场景数量、连接数约束、驻守怪物等配置：
## - 在 Godot 编辑器中打开 resources/map/biomes/xxx_biome.tres
## - 直接在 Inspector 中修改，所有字段均可编辑
## - 也可在 MapTypes 节点的 Inspector 中展开 biome_definitions 逐项编辑
##
## 要新增生态群系：
## - 复制一份现有 .tres 文件，修改 biome_name 和场景列表
## - 在 map_control.tscn 的 MapTypes → biome_definitions 中添加引用

@export var biome_definitions: Array[BiomeDefinition] = []

# 场景名 → 场景 .tscn 路径
var map_road: Dictionary[String, String] = {}

# 场景名 → map_attribute
var map_attr_by_name: Dictionary[String, map_attribute] = {}

# 群系名 → BiomeDefinition
var biome_by_name: Dictionary[String, BiomeDefinition] = {}

# 场景名 → 所属群系名
var scene_biome: Dictionary[String, String] = {}

# 起始群系的引用
var starting_biome: BiomeDefinition = null


func _ready() -> void:
	if biome_definitions.is_empty():
		_load_default_biomes()
	build_all_dicts()


## 从 resources/map/biomes/ 加载默认群系 .tres 文件
func _load_default_biomes() -> void:
	const biome_files := [
		"res://resources/map/biomes/normal_biome.tres",
		"res://resources/map/biomes/earth_biome.tres",
		"res://resources/map/biomes/fire_biome.tres",
		"res://resources/map/biomes/gold_biome.tres",
		"res://resources/map/biomes/water_biome.tres",
		"res://resources/map/biomes/wood_biome.tres",
	]
	for path in biome_files:
		var biome: BiomeDefinition = load(path) as BiomeDefinition
		if biome != null:
			biome_definitions.append(biome)
		else:
			push_error("无法加载群系资源: ", path)

	if biome_definitions.is_empty():
		push_error("未找到任何群系定义资源，地图将无法生成。")


## 构建所有查询字典
func build_all_dicts() -> void:
	biome_by_name.clear()
	map_road.clear()
	map_attr_by_name.clear()
	scene_biome.clear()
	starting_biome = null

	for biome_def in biome_definitions:
		if biome_def == null or biome_def.biome_name.is_empty():
			continue

		var bname := biome_def.biome_name
		biome_by_name[bname] = biome_def

		if biome_def.is_starting_biome:
			starting_biome = biome_def

		# 遍历群系内所有场景
		for attr in biome_def.get_all_scenes():
			if attr == null or attr.scene_name.is_empty():
				continue
			var sname := attr.scene_name
			map_road[sname] = attr.scene_dir
			map_attr_by_name[sname] = attr
			scene_biome[sname] = bname


## 根据场景名查找 .tscn 路径
func from_name_get_road(scene_name: String) -> String:
	if map_road.has(scene_name):
		return map_road[scene_name]
	if scene_name != "void":
		push_warning("出现了未定义的地图类型: ", scene_name)
		return "wrong"
	return "void"


## 根据场景名查找 map_attribute
func from_name_get_attribute(scene_name: String) -> map_attribute:
	if map_attr_by_name.has(scene_name):
		return map_attr_by_name[scene_name]
	return null


## 根据群系名查找 BiomeDefinition
func from_name_get_biome(biome_name: String) -> BiomeDefinition:
	if biome_by_name.has(biome_name):
		return biome_by_name[biome_name]
	return null


## 返回当前地图包含的场景总数
func get_total_scene_count() -> int:
	var total := 0
	for biome_def in biome_definitions:
		if biome_def != null:
			total += biome_def.get_total_scene_count()
	return total
