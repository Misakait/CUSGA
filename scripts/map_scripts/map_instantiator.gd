extends Node

@onready var map_position = $"../MapPositionCreate"
@onready var map_types = $"../MapTypes"
@onready var map_button = $"../MapButton"
@onready var time_system = get_node_or_null("/root/TimeSystem")
@onready var screen_transitions = get_node_or_null("/root/ScreenTransitions")

const ORIGINAL_BACKGROUND_SELF_MODULATE_META := &"original_background_self_modulate"

signal on_entered_room(position: Vector2i, scene: Node2D)

@export var night_background_tint: Color = Color(0.45, 0.45, 0.55, 1.0)

var current_scene: Node2D = null
var current_position: Vector2i = Vector2i.ZERO
#储存每个点的场景路径
var map_road_in_map : Dictionary[Vector2i , String] = {}
#储存所有已加载场景的实例
var map_scene: Dictionary = {}
var _is_night: bool = false

func _ready() -> void:
	_bind_time_system()
	#创建地图
	create_map_road()
	load_scene_at(Vector2i(1,1))

func _exit_tree() -> void:
	if time_system != null and time_system.has_signal(&"DayNightToggled"):
		var callable := Callable(self, "_on_day_night_toggled")
		if time_system.is_connected(&"DayNightToggled", callable):
			time_system.disconnect(&"DayNightToggled", callable)

func create_map_road():
	var map = map_position.map

	#创建地图对应的场景路径
	for x in range(0 , map.size()):
		for y in range(0 , map[x].size()):
			map_road_in_map[Vector2i(x,y)] = map_types.from_name_get_road(map[x][y])

func load_scene_at(position: Vector2i):

	if screen_transitions != null and screen_transitions.has_method(&"fade_in"):
		screen_transitions.fade_in()

	if current_scene:
		remove_child(current_scene)

	#情况一：该场景已经创建过
	if map_scene.has(position):
		current_scene = map_scene[position]

	#情况二：该场景没创建过，就实例化并保存下来
	else:
		var load_road: String = map_road_in_map[position]
		var load_scene = load(load_road)
		current_scene = load_scene.instantiate()

		#添加到“已加载的地图场景”
		map_scene[position] = current_scene

		#初始化该场景
		if current_scene.has_method("initialize_scene"):
			current_scene.initialize_scene()

	#添加到场景树
	add_child(current_scene)
	_apply_background_time_tint(current_scene)
	current_position = position

	#更新按钮
	map_button.update_scene_button(position)
	emit_signal(&"on_entered_room", position, current_scene)

func _bind_time_system() -> void:
	if time_system == null:
		push_warning("MapInstantiator 未找到 TimeSystem，地图背景不会随昼夜状态变暗。")
		return

	_is_night = bool(time_system.get("IsNight"))
	if not time_system.has_signal(&"DayNightToggled"):
		push_warning("TimeSystem 缺少 DayNightToggled 信号，地图背景不会实时响应昼夜切换。")
		return

	var callable := Callable(self, "_on_day_night_toggled")
	if not time_system.is_connected(&"DayNightToggled", callable):
		time_system.connect(&"DayNightToggled", callable)

func _on_day_night_toggled(is_night: bool) -> void:
	_is_night = is_night
	for room_scene in map_scene.values():
		if room_scene is Node:
			_apply_background_time_tint(room_scene)

func _apply_background_time_tint(room_scene: Node) -> void:
	var background := _find_background(room_scene)
	if background == null:
		return

	var day_self_modulate := _get_day_background_self_modulate(background)
	if _is_night:
		background.self_modulate = _multiply_color(day_self_modulate, night_background_tint)
	else:
		background.self_modulate = day_self_modulate

func _find_background(room_scene: Node) -> Sprite2D:
	if room_scene == null:
		return null

	return room_scene.get_node_or_null("Background")

func _get_day_background_self_modulate(background: Sprite2D) -> Color:
	if not background.has_meta(ORIGINAL_BACKGROUND_SELF_MODULATE_META):
		# 只缓存背景自身的日间颜色，避免切回白天时覆盖前景和控件状态。
		background.set_meta(ORIGINAL_BACKGROUND_SELF_MODULATE_META, background.self_modulate)

	return background.get_meta(ORIGINAL_BACKGROUND_SELF_MODULATE_META)

func _multiply_color(base_color: Color, tint: Color) -> Color:
	return Color(
		base_color.r * tint.r,
		base_color.g * tint.g,
		base_color.b * tint.b,
		base_color.a * tint.a
	)
