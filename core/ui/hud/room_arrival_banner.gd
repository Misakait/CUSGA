extends CanvasLayer

## 无缝跨房地点提示。只监听已完成的房间进入事件，不参与扣费、暂停或移动。

@export var config: RoomTransitionConfig = preload("res://resources/map/room_transition_config.tres")
## 地图根节点相对路径；宿主需要提供 on_entered_room(position, scene) 信号。
@export var map_control_path: NodePath = ^".."

@onready var _banner: Control = $Root/Banner
@onready var _accent: ColorRect = $Root/Banner/Accent
@onready var _biome_banner: Control = $Root/BiomeBanner
@onready var _biome_accent: ColorRect = $Root/BiomeBanner/Accent

var _map_control: Node = null
var _model: Node = null
var _map_types: Node = null
var _last_position: Vector2i
var _last_biome: String = ""
var _has_room: bool = false
var _tween: Tween = null
var _rise_offset: float = 0.0
var _biome_tween: Tween = null
var _biome_rise_offset: float = 0.0


func _ready() -> void:
	_banner.hide()
	_biome_banner.hide()
	_map_control = get_node_or_null(map_control_path)
	if _map_control == null or not _map_control.has_signal(&"on_entered_room"):
		push_warning("地点提示未找到地图进入信号，请检查 map_control_path。")
		return
	_model = _map_control.get_node_or_null("MapWorldModel")
	_map_types = _map_control.get_node_or_null("MapTypes")
	_map_control.connect(&"on_entered_room", _on_entered_room)
	get_viewport().size_changed.connect(_update_layout)
	_update_layout()
	# CanvasLayer 不继承世界节点的可见性；战斗隐藏探索地图时一并收起旧提示。
	if _map_control is CanvasItem:
		(_map_control as CanvasItem).visibility_changed.connect(_on_map_visibility_changed)


func _exit_tree() -> void:
	_cancel_animation()
	if is_instance_valid(_map_control):
		if _map_control.is_connected(&"on_entered_room", _on_entered_room):
			_map_control.disconnect(&"on_entered_room", _on_entered_room)
		if _map_control is CanvasItem:
			var item := _map_control as CanvasItem
			if item.visibility_changed.is_connected(_on_map_visibility_changed):
				item.visibility_changed.disconnect(_on_map_visibility_changed)


## 播放房间名；跨生态时另在上方播放独立的生态名，普通换房不打断生态提示。
## @param room_name 已转换为显示文本的房间名。
## @param biome_id 配置中的生态标识，用于上方生态名与两条提示的装饰色。
## @param biome_changed 是否跨生态；为 true 时启动或替换上方生态提示。
## @return 无返回值。
func show_arrival(room_name: String, biome_id: String, biome_changed: bool = false) -> void:
	if config == null or not config.enabled:
		_cancel_animation()
		_banner.hide()
		_biome_banner.hide()
		return
	_play_banner(_banner, room_name, biome_id, false)
	if biome_changed:
		var biome_name: String = config.biome_names.get(biome_id, biome_id)
		if not biome_name.is_empty():
			_play_banner(_biome_banner, biome_name, biome_id, true)


func _play_banner(target: Control, text: String, biome_id: String, is_biome: bool) -> void:
	_cancel_banner(is_biome)
	_update_layout()
	var title := target.get_node("Title") as Label
	var accent := target.get_node("Accent") as ColorRect
	var backdrop := target.get_node("Backdrop") as TextureRect
	title.text = text
	title.add_theme_font_size_override("font_size", config.biome_font_size if is_biome else config.room_font_size)
	title.add_theme_color_override("font_color", config.text_color)
	if config.font != null:
		title.add_theme_font_override("font", config.font)
	else:
		title.remove_theme_font_override("font")
	accent.color = config.biome_colors.get(biome_id, config.text_color)
	backdrop.modulate.a = clampf(config.backdrop_opacity, 0.0, 0.8)
	var set_offset: Callable = _set_biome_rise_offset if is_biome else _set_rise_offset
	var initial_offset := maxf(config.rise_distance, 0.0)
	set_offset.call(initial_offset)
	target.modulate.a = 0.0
	accent.scale.x = 0.18
	target.show()
	var enter_time := maxf(config.enter_duration, 0.05)
	var line_time := maxf(config.line_duration, 0.05)
	var hold_time := maxf(config.biome_hold_duration if is_biome else config.room_hold_duration, 0.0)
	var tween := create_tween()
	if is_biome:
		_biome_tween = tween
	else:
		_tween = tween
	tween.set_parallel(true)
	tween.tween_property(target, "modulate:a", 1.0, enter_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_method(set_offset, initial_offset, 0.0, enter_time).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(accent, "scale:x", 1.0, line_time).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# 两条提示各自持有补间和结束回调，普通换房只替换下方文字。
	tween.chain().tween_interval(hold_time)
	tween.chain().tween_property(target, "modulate:a", 0.0, maxf(config.exit_duration, 0.05)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(target.hide)


func _on_entered_room(position: Vector2i, _scene: Node2D) -> void:
	if _model == null:
		return
	if _has_room and position == _last_position:
		return
	var resource: Resource = _model.call(&"get_scene_resource", position)
	if resource == null:
		return
	var room_id := String(resource.get(&"scene_name"))
	var biome_id := ""
	if _map_types != null:
		var scene_biomes: Dictionary = _map_types.get(&"scene_biome")
		biome_id = String(scene_biomes.get(room_id, ""))
	var biome_changed := _has_room and biome_id != _last_biome
	var should_show := _has_room or (config != null and config.show_initial_room)
	_last_position = position
	_last_biome = biome_id
	_has_room = true
	if not should_show or config == null:
		return
	var room_name: String = config.room_names.get(room_id, "")
	# 自定义地图尚未登记中文名时，仍提供可读名称；不暴露 _t1 这类内部后缀。
	if room_name.is_empty():
		var parts := room_id.rsplit("_t", true, 1)
		var readable_id := parts[0] if parts.size() == 2 and parts[1].is_valid_int() else room_id
		room_name = readable_id.replace("_", " ").capitalize()
	show_arrival(room_name, biome_id, biome_changed)


func _update_layout() -> void:
	if config == null:
		return
	var viewport_size := get_viewport().get_visible_rect().size
	_layout_banner(_banner, viewport_size, config.banner_width, clampf(config.screen_y_ratio, 0.1, 0.5), 80.0, _rise_offset)
	_layout_banner(_biome_banner, viewport_size, config.biome_banner_width, clampf(config.biome_screen_y_ratio, 0.05, 0.4), 96.0, _biome_rise_offset)
	_accent.pivot_offset = _accent.size * 0.5
	_biome_accent.pivot_offset = _biome_accent.size * 0.5


func _layout_banner(target: Control, viewport_size: Vector2, max_width: float, y_ratio: float, height: float, rise: float) -> void:
	var width := minf(maxf(max_width, 240.0), maxf(viewport_size.x - 32.0, 1.0))
	target.set_anchors_preset(Control.PRESET_TOP_LEFT)
	target.position = Vector2((viewport_size.x - width) * 0.5, viewport_size.y * y_ratio - height * 0.5 + rise)
	target.size = Vector2(width, height)


func _set_rise_offset(value: float) -> void:
	# 动画只保存相对偏移，窗口在入场中改变尺寸时仍能重新计算屏幕中心。
	_rise_offset = value
	_update_layout()


func _set_biome_rise_offset(value: float) -> void:
	_biome_rise_offset = value
	_update_layout()


func _on_map_visibility_changed() -> void:
	if not (_map_control as CanvasItem).is_visible_in_tree():
		_cancel_animation()
		_banner.hide()
		_biome_banner.hide()


func _cancel_animation() -> void:
	_cancel_banner(false)
	_cancel_banner(true)


func _cancel_banner(is_biome: bool) -> void:
	var tween := _biome_tween if is_biome else _tween
	if tween != null and tween.is_valid():
		tween.kill()
	if is_biome:
		_biome_tween = null
		_biome_rise_offset = 0.0
	else:
		_tween = null
		_rise_offset = 0.0
