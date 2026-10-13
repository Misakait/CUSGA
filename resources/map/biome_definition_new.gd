extends Resource
class_name BiomeDefinitionNew

## 单个生态的场景配置；只保存资源数据，不决定地图坐标和分支布局。
## 主场景的 scene_count 是主线生成次数，分支复用主场景不扣除这个数量。
@export var biome_name: String = ""
@export var main_scenes: Array[map_attribute] = []
@export var special_scenes: Array[map_attribute] = []
## 首领场景按各项 scene_count 在本生态主场景之后随机排列；空数组表示没有首领房间。
@export var boss_scenes: Array[map_attribute] = []
## 键为特殊场景名称，值的 x/y 分别是最少/最多次数。
## 未设置的场景沿用其 scene_count，作为最少与最多次数。
@export var special_scene_count_ranges: Dictionary[String, Vector2i] = {}


## 合并三类场景，保持配置顺序。
## @return 场景配置数组；参数：无。
func get_all_scenes() -> Array[map_attribute]:
	var scenes: Array[map_attribute] = []
	scenes.append_array(main_scenes)
	scenes.append_array(special_scenes)
	scenes.append_array(boss_scenes)
	return scenes


## 读取一种特殊场景的数量范围。
## @param scene 特殊场景配置。
## @return 最少/最多次数组成的 Vector2i；空场景返回零。
func get_special_scene_count_range(scene: map_attribute) -> Vector2i:
	if scene == null:
		return Vector2i.ZERO
	return special_scene_count_ranges.get(
		scene.scene_name, Vector2i(scene.scene_count, scene.scene_count)
	)


## 统计主线、必需特殊场景和可选首领的最低房间数。
## @return 最低数量，不含分支填充用的主场景；参数：无。
func get_total_scene_count() -> int:
	var total: int = 0
	for scene in main_scenes:
		if scene != null:
			total += scene.scene_count
	for scene in special_scenes:
		total += get_special_scene_count_range(scene).x
	for scene in boss_scenes:
		if scene != null:
			total += scene.scene_count
	return total


## 通过代码创建五个独立生态资源，默认顺序为木、土、水、火、金。
## @return 可直接挂载到地图类型数组的资源；参数：无。
static func create_default_biomes() -> Array[BiomeDefinitionNew]:
	var result: Array[BiomeDefinitionNew] = []
	for biome_name_value: String in ["wood", "earth", "water", "fire", "gold"]:
		var path: String = "res://resources/map/biomes/%s_biome.tres" % biome_name_value
		var old_biome: BiomeDefinition = load(path) as BiomeDefinition
		if old_biome == null:
			push_error("无法读取默认生态配置：%s。" % path)
			continue
		var biome := BiomeDefinitionNew.new()
		biome.biome_name = old_biome.biome_name
		biome.resource_name = old_biome.biome_name
		for scene in old_biome.main_scenes:
			if scene != null:
				biome.main_scenes.append(scene.duplicate(true) as map_attribute)
		var special_sources: Array[map_attribute] = []
		special_sources.append_array(old_biome.transition_scenes)
		special_sources.append(old_biome.market_scene)
		special_sources.append(old_biome.teleport_scene)
		var by_path: Dictionary[String, map_attribute] = {}
		for scene in special_sources:
			if scene == null:
				continue
			# 旧过渡池用三个名称引用同一房间；合并配置但保留总次数，避免丢失房间额度。
			if by_path.has(scene.scene_dir):
				by_path[scene.scene_dir].scene_count += scene.scene_count
				continue
			var copy: map_attribute = scene.duplicate(true) as map_attribute
			by_path[copy.scene_dir] = copy
			biome.special_scenes.append(copy)
		for scene in biome.special_scenes:
			biome.special_scene_count_ranges[scene.scene_name] = Vector2i(
				scene.scene_count, scene.scene_count
			)
		# 旧生态没有首领分类，不擅自把传送场景或集市场景当作首领。
		result.append(biome)
	return result
