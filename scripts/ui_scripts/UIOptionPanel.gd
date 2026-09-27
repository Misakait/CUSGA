extends Control

## 暂停菜单内的参数设置页。
##
## 本页只读写 SettingsManager 中的地图偏好并发出返回请求，不直接查找 MiniMap。

signal back_requested

const SETTINGS_SECTION: String = "map"
const MINIMAP_ZOOM_KEY: String = "minimap_zoom"

## 小地图缩放滑条下限。
@export_range(0.1, 4.0, 0.05) var minimum_minimap_zoom: float = 0.75
## 小地图缩放滑条上限。
@export_range(0.1, 6.0, 0.05) var maximum_minimap_zoom: float = 3.5
## 小地图缩放滑条步长。
@export_range(0.01, 1.0, 0.01) var minimap_zoom_step: float = 0.05
## 没有本地偏好时使用的默认缩放倍率。
@export_range(0.1, 6.0, 0.05) var default_minimap_zoom: float = 2.0

@onready var _map_category_button: Button = %MapCategoryButton
@onready var _zoom_slider: HSlider = %MiniMapZoomSlider
@onready var _zoom_value_label: Label = %MiniMapZoomValue
@onready var _reset_button: Button = %ResetMapButton
@onready var _back_button: Button = %BackButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_map_category_button.button_pressed = true
	_map_category_button.disabled = true
	_zoom_slider.min_value = minf(minimum_minimap_zoom, maximum_minimap_zoom)
	_zoom_slider.max_value = maxf(minimum_minimap_zoom, maximum_minimap_zoom)
	_zoom_slider.step = minimap_zoom_step
	_zoom_slider.value_changed.connect(_on_zoom_changed)
	_reset_button.pressed.connect(_on_reset_pressed)
	_back_button.pressed.connect(_on_back_pressed)
	_refresh_from_settings()


## 从 SettingsManager 重新读取当前地图偏好。
##
## @return 无返回值。
func refresh_from_settings() -> void:
	_refresh_from_settings()


func _refresh_from_settings() -> void:
	var saved_value: Variant = SettingsManager.get_setting(
		SETTINGS_SECTION, MINIMAP_ZOOM_KEY, default_minimap_zoom
	)
	var zoom: float = default_minimap_zoom
	if saved_value is float or saved_value is int:
		zoom = float(saved_value)
	_zoom_slider.set_value_no_signal(clampf(zoom, _zoom_slider.min_value, _zoom_slider.max_value))
	_update_value_label(_zoom_slider.value)


func _on_zoom_changed(value: float) -> void:
	_update_value_label(value)
	SettingsManager.set_setting(SETTINGS_SECTION, MINIMAP_ZOOM_KEY, value)


func _on_reset_pressed() -> void:
	_zoom_slider.value = clampf(
		default_minimap_zoom, _zoom_slider.min_value, _zoom_slider.max_value
	)


func _on_back_pressed() -> void:
	back_requested.emit()


func _update_value_label(value: float) -> void:
	_zoom_value_label.text = "%.2f×" % value
