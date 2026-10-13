extends Node2D

## 有序生态配置管理器，生成顺序完全由 Inspector 中的数组顺序决定。
## 保留旧显示层和通道驻守层的查询入口，以便只替换节点脚本。
## 使用新字段名，避免旧场景序列化的 normal 资源覆盖新类型数组。
@export var biomes: Array[BiomeDefinitionNew] = BiomeDefinitionNew.create_default_biomes()
var map_road: Dictionary[String, String] = {}
var map_attr_by_name: Dictionary[String, map_attribute] = {}
var scene_biome: Dictionary[String, String] = {}
var _legacy_attr_by_name: Dictionary[String, map_attribute] = {}
var _legacy_loaded: bool = false


func _ready() -> void:
	build_all_dicts()


## 按当前生态数组重建旧调用方使用的场景缓存。
## @return 无返回值；参数：无。不会改变数组顺序或共享旧资源。
func build_all_dicts() -> void:
	map_road.clear()
	map_attr_by_name.clear()
	scene_biome.clear()
	for biome in biomes:
		if biome == null:
			continue
		for scene in biome.get_all_scenes():
			if scene == null or scene.scene_name.is_empty():
				continue
			map_road[scene.scene_name] = scene.scene_dir
			map_attr_by_name[scene.scene_name] = scene
			scene_biome[scene.scene_name] = biome.biome_name


## 沿用旧显示层的场景名称到路径入口。
## @param scene_name 地图网格中的场景名称。
## @return 场景路径；空格返回 void，未定义名称返回 wrong 并警告。
func from_name_get_road(scene_name: String) -> String:
	if scene_name == "void":
		return "void"
	var scene: map_attribute = from_name_get_attribute(scene_name)
	if scene != null:
		return scene.scene_dir
	push_warning("出现了未定义的地图类型：%s。" % scene_name)
	return "wrong"


## 沿用旧通道驻守层的场景配置入口。
## @param scene_name 场景名称。
## @return 配置资源；不存在时返回 null。旧快照的名称只用于读取，不参与新地图生成。
func from_name_get_attribute(scene_name: String) -> map_attribute:
	if map_attr_by_name.has(scene_name):
		return map_attr_by_name[scene_name]
	# 旧局可能含 normal 或过渡别名；只读回退保证继续本局不会丢失场景路径。
	_load_legacy_lookup()
	return _legacy_attr_by_name.get(scene_name)


## 统计当前生态配置要求的最低房间数。
## @return 最低数量，不含随机分支填充房间；参数：无。
func get_total_scene_count() -> int:
	var total: int = 0
	for biome in biomes:
		if biome != null:
			total += biome.get_total_scene_count()
	return total


func _load_legacy_lookup() -> void:
	if _legacy_loaded:
		return
	_legacy_loaded = true
	for biome_name_value: String in ["normal", "wood", "earth", "water", "fire", "gold"]:
		var old_biome: BiomeDefinition = load(
			"res://resources/map/biomes/%s_biome.tres" % biome_name_value
		) as BiomeDefinition
		if old_biome == null:
			continue
		for scene in old_biome.get_all_scenes():
			if scene != null:
				_legacy_attr_by_name[scene.scene_name] = scene
