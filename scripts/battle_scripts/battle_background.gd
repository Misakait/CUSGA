extends Sprite2D

## 战斗背景表现组件：根据进入战斗时传入的地图路径选择五行底图。
## 只接收地图标识，不查询世界节点或修改地图状态，独立运行战斗场景时同样可用。

## 地图资源的群系目录前缀；只解析紧随其后的目录，避免误用文件名里的元素词。
const MAP_ENV_PREFIX: String = "res://scenes/map_scenes/map_env/"

## 群系与背景贴图的配置表；gold 对应金行，检查器可替换素材，运行时无需修改。
@export var backgrounds: Dictionary[String, Texture2D] = {
	"gold": preload("res://res/background/battle/metal.png"),
	"wood": preload("res://res/background/battle/wood.png"),
	"water": preload("res://res/background/battle/water.png"),
	"fire": preload("res://res/background/battle/fire.png"),
	"earth": preload("res://res/background/battle/earth.png"),
}
## normal 群系、未知地图及独立战斗的默认背景；木行空地适合普通探索区域。
## 只需在检查器中配置，运行时切换地图不会改写此默认值。
@export_enum("wood", "gold", "water", "fire", "earth") var fallback_biome: String = "wood"
## 背景覆盖的设计视口尺寸；与项目的 1280×720 画布保持一致，不随贴图尺寸变化。
@export var design_size: Vector2 = Vector2(1280.0, 720.0)

## 当前实际使用的群系键，供运行时检查；每个战斗实例独立保存。
var current_biome: String = ""


func _ready() -> void:
	# 协调器会在入树前配置地图；只为直接运行的场景补默认值，避免覆盖已选的五行。
	if current_biome.is_empty():
		configure_for_map("")


## 按地图所属群系应用背景，并将原图完整铺满设计视口。
## @param map_scene_path 遭遇发生时的完整地图场景路径；空串与未知目录使用默认背景。
## @return 无返回值；配置缺少对应贴图时尝试默认贴图，均缺少时保留场景原纹理。
func configure_for_map(map_scene_path: String) -> void:
	current_biome = fallback_biome
	if map_scene_path.begins_with(MAP_ENV_PREFIX):
		# 主场景、过渡场景和传送点的层数不同，群系始终是 map_env 后的第一个目录。
		var biome: String = map_scene_path.trim_prefix(MAP_ENV_PREFIX).get_slice("/", 0)
		if backgrounds.get(biome) != null:
			current_biome = biome
	# 使用实例配置表，后续替换五行素材不需要改动世界交互协调器。
	var selected_texture: Texture2D = backgrounds.get(current_biome) as Texture2D
	if selected_texture == null:
		return
	texture = selected_texture
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	position = design_size * 0.5
	scale = design_size / selected_texture.get_size()
