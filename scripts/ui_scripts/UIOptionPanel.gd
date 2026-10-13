extends Control

## 暂停菜单内的参数设置页。
##
## 本页读写地图、背包和按键偏好，并把返回与局内死亡意图交给宿主，不直接修改玩家。

signal back_requested
## 局内设置请求玩家死亡；宿主负责调用玩家生命组件的正常伤害入口。
signal death_requested

const SETTINGS_SECTION: String = "map"
const MINIMAP_ZOOM_KEY: String = "minimap_zoom"
const INVENTORY_SECTION: String = "inventory"
const SHOW_SELECTED_ITEM_INFO_KEY: String = "show_selected_item_info"

## 按键绑定管理器节点路径。
##
## 用 NodePath 而不是直接引用 autoload 标识符：本页也会被编辑器测试实例化，那里没有
## autoload，直接引用会在解析阶段就报错。
const KEY_BINDING_MANAGER_PATH: NodePath = ^"/root/KeyBindingManager"
## 按键绑定注册表脚本，提供动作清单、分组与显示名。
const KEY_BINDING_REGISTRY: GDScript = preload("res://core/input/key_binding_registry.gd")
## 按键绑定行场景，每个可重绑动作实例化一行。
const KEY_BINDING_ROW_SCENE: PackedScene = preload("res://scenes/ui_scenes/key_binding_row.tscn")
## 分组标题字号，比动作名略小以体现层级。
const BINDING_GROUP_FONT_SIZE: int = 16
## 分组标题颜色，弱化处理以免和可交互的键位按钮抢注意力。
const BINDING_GROUP_COLOR: Color = Color(0.7, 0.78, 0.84)
## 保存失败提示。
##
## 键位在内存里已经生效，但没写进 user://settings.cfg；不告诉玩家就等于悄悄丢设置。
## 这是本分类唯一保留的提示文案：面板不再解释操作方式，也不再回显成功，只报告真正需要
## 玩家知道的问题。
const BINDING_SAVE_FAILED_TEXT: String = "键位已在本局生效，但保存失败，重启后会恢复原键位。"

## 小地图缩放滑条下限。
@export_range(0.1, 4.0, 0.05) var minimum_minimap_zoom: float = 0.75
## 小地图缩放滑条上限。
@export_range(0.1, 6.0, 0.05) var maximum_minimap_zoom: float = 3.5
## 小地图缩放滑条步长。
@export_range(0.01, 1.0, 0.01) var minimap_zoom_step: float = 0.05
## 没有本地偏好时使用的默认缩放倍率。
@export_range(0.1, 6.0, 0.05) var default_minimap_zoom: float = 2.0
## 是否在本实例显示局内测试用的立即死亡按钮；主菜单实例保持关闭。
@export var show_death_button: bool = false

@onready var _map_category_button: Button = %MapCategoryButton
@onready var _inventory_category_button: Button = %InventoryCategoryButton
@onready var _map_settings: Control = %MapSettings
@onready var _inventory_settings: Control = %InventorySettings
@onready var _selected_item_info_toggle: CheckButton = %SelectedItemInfoToggle
@onready var _zoom_slider: HSlider = %MiniMapZoomSlider
@onready var _zoom_value_label: Label = %MiniMapZoomValue
@onready var _reset_button: Button = %ResetMapButton
@onready var _back_button: Button = %BackButton
@onready var _key_binding_category_button: Button = %KeyBindingCategoryButton
@onready var _key_binding_settings: Control = %KeyBindingSettings
@onready var _binding_list: VBoxContainer = %BindingList
@onready var _binding_feedback_label: Label = %BindingFeedbackLabel
@onready var _reset_all_bindings_button: Button = %ResetAllBindingsButton
@onready var _death_button: Button = %DeathButton

## 按键绑定管理器；编辑器测试环境没有 autoload 时为 null。
var _key_binding_manager: Node = null
## 动作名 → 该动作的绑定行，用于按动作刷新文案。
var _binding_rows: Dictionary = {}
## 最近一次插入的分组标题，用来避免相邻的同组动作重复插入标题。
var _last_binding_group: String = ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_map_category_button.button_pressed = true
	_inventory_settings.hide()
	_map_category_button.pressed.connect(_on_map_category_pressed)
	_inventory_category_button.pressed.connect(_on_inventory_category_pressed)
	_selected_item_info_toggle.toggled.connect(_on_selected_item_info_toggled)
	_zoom_slider.min_value = minf(minimum_minimap_zoom, maximum_minimap_zoom)
	_zoom_slider.max_value = maxf(minimum_minimap_zoom, maximum_minimap_zoom)
	_zoom_slider.step = minimap_zoom_step
	_zoom_slider.value_changed.connect(_on_zoom_changed)
	_reset_button.pressed.connect(_on_reset_pressed)
	_back_button.pressed.connect(_on_back_pressed)
	_key_binding_category_button.button_pressed = false
	_key_binding_settings.hide()
	_key_binding_category_button.pressed.connect(_on_key_binding_category_pressed)
	_reset_all_bindings_button.pressed.connect(_on_reset_all_bindings_pressed)
	_death_button.visible = show_death_button
	_death_button.pressed.connect(_on_death_button_pressed)
	_build_binding_rows()
	_connect_key_binding_manager()
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
	var saved_item_info: Variant = SettingsManager.get_setting(
		INVENTORY_SECTION, SHOW_SELECTED_ITEM_INFO_KEY, true
	)
	_selected_item_info_toggle.set_pressed_no_signal(saved_item_info if saved_item_info is bool else true)
	_refresh_binding_rows()


func _on_map_category_pressed() -> void:
	_map_category_button.set_pressed_no_signal(true)
	_inventory_category_button.set_pressed_no_signal(false)
	_key_binding_category_button.set_pressed_no_signal(false)
	_map_settings.show()
	_inventory_settings.hide()
	_key_binding_settings.hide()
	_cancel_binding_listening()


func _on_inventory_category_pressed() -> void:
	_map_category_button.set_pressed_no_signal(false)
	_inventory_category_button.set_pressed_no_signal(true)
	_key_binding_category_button.set_pressed_no_signal(false)
	_map_settings.hide()
	_inventory_settings.show()
	_key_binding_settings.hide()
	_cancel_binding_listening()


func _on_selected_item_info_toggled(enabled: bool) -> void:
	SettingsManager.set_setting(INVENTORY_SECTION, SHOW_SELECTED_ITEM_INFO_KEY, enabled)


func _on_zoom_changed(value: float) -> void:
	_update_value_label(value)
	SettingsManager.set_setting(SETTINGS_SECTION, MINIMAP_ZOOM_KEY, value)


func _on_reset_pressed() -> void:
	_zoom_slider.value = clampf(
		default_minimap_zoom, _zoom_slider.min_value, _zoom_slider.max_value
	)


func _on_back_pressed() -> void:
	_cancel_binding_listening()
	back_requested.emit()


func _update_value_label(value: float) -> void:
	_zoom_value_label.text = "%.2f×" % value


## 切换到「按键」分类。
## @return 无返回值。
func _on_key_binding_category_pressed() -> void:
	_map_category_button.set_pressed_no_signal(false)
	_inventory_category_button.set_pressed_no_signal(false)
	_key_binding_category_button.set_pressed_no_signal(true)
	_map_settings.hide()
	_inventory_settings.hide()
	_key_binding_settings.show()
	_set_binding_feedback("")
	_refresh_binding_rows()


## 按注册表清单构建全部绑定行。
##
## 清单是唯一事实来源：本页不硬编码动作名，因此以后新增输入动作只要进了注册表就会
## 自动出现在这里，不会出现「游戏里能按、设置里改不了」的漏网动作。
## @return 无返回值。
func _build_binding_rows() -> void:
	var entries: Array = KEY_BINDING_REGISTRY.call("get_rebindable_actions")
	for entry: Dictionary in entries:
		_add_binding_group_title(String(entry.get("group", "")))
		var action: StringName = StringName(entry.get("action", &""))
		var row: Control = KEY_BINDING_ROW_SCENE.instantiate() as Control
		_binding_list.add_child(row)
		# setup 必须在进入场景树之后调用：行内的控件引用是 @onready 的，过早落值会拿到 null。
		row.call("setup", action, String(entry.get("display", "")), String(entry.get("note", "")))
		row.connect(&"rebind_requested", _on_binding_rebind_requested)
		row.connect(&"reset_requested", _on_binding_reset_requested)
		_binding_rows[action] = row


## 在分组发生变化时插入一个分组标题。
## @param group 分组名；为空或与上一组相同时不插入。
## @return 无返回值。
func _add_binding_group_title(group: String) -> void:
	if group.is_empty() or group == _last_binding_group:
		return
	_last_binding_group = group
	var title: Label = Label.new()
	title.text = group
	title.add_theme_font_size_override(&"font_size", BINDING_GROUP_FONT_SIZE)
	title.add_theme_color_override(&"font_color", BINDING_GROUP_COLOR)
	_binding_list.add_child(title)


## 解析按键绑定管理器并订阅它的信号。
## @return 无返回值。
func _connect_key_binding_manager() -> void:
	_key_binding_manager = get_node_or_null(KEY_BINDING_MANAGER_PATH)
	if _key_binding_manager == null:
		push_warning(
			"UIOptionPanel: 未找到 %s，按键列表只显示当前键位，改动无法保存。" % KEY_BINDING_MANAGER_PATH
		)
		return
	if not _key_binding_manager.is_connected(&"binding_changed", _on_binding_changed):
		_key_binding_manager.connect(&"binding_changed", _on_binding_changed)
	if not _key_binding_manager.is_connected(&"bindings_reset", _on_bindings_reset):
		_key_binding_manager.connect(&"bindings_reset", _on_bindings_reset)


## 断开与按键绑定管理器的信号连接。
##
## 管理器是常驻 autoload，生命周期长于本页；不断开会让它一直持有已释放页面的回调。
## @return 无返回值。
func _exit_tree() -> void:
	if _key_binding_manager == null:
		return
	if _key_binding_manager.is_connected(&"binding_changed", _on_binding_changed):
		_key_binding_manager.disconnect(&"binding_changed", _on_binding_changed)
	if _key_binding_manager.is_connected(&"bindings_reset", _on_bindings_reset):
		_key_binding_manager.disconnect(&"bindings_reset", _on_bindings_reset)


## 刷新全部绑定行的键位文案、冲突标记与「恢复默认」按钮。
## @return 无返回值。
func _refresh_binding_rows() -> void:
	var conflicts: Array = []
	if _key_binding_manager != null:
		conflicts = _key_binding_manager.call("get_conflicting_actions")
	for action: Variant in _binding_rows.keys():
		var action_name: StringName = StringName(action)
		var row: Control = _binding_rows[action]
		row.call(
			"refresh",
			_resolve_binding_event(action_name),
			conflicts.has(action_name),
			_is_default_binding(action_name)
		)


## 查询某个动作当前键位是否就是项目默认键位。
##
## 优先问管理器；编辑器测试环境没有 autoload 时一律视为默认，也就是不显示「恢复默认」
## 按钮——在没有恢复能力的环境里给出一个点了没反应的入口，比不显示更糟。
## @param action 动作名。
## @return bool 当前是默认键位返回 true。
func _is_default_binding(action: StringName) -> bool:
	if _key_binding_manager == null:
		return true
	return bool(_key_binding_manager.call("is_default_binding", action))


## 读取某个动作当前生效的键盘事件。
##
## 优先问管理器（它已经应用了玩家偏好）；编辑器测试环境没有 autoload 时退化为直接读
## InputMap，让面板在没有管理器的情况下仍能显示真实键位而不是空白。
## @param action 动作名。
## @return InputEvent 当前键盘事件；动作不存在或没有键盘事件时返回 null。
func _resolve_binding_event(action: StringName) -> InputEvent:
	if _key_binding_manager != null:
		return _key_binding_manager.call("get_binding_event", action) as InputEvent
	if not InputMap.has_action(action):
		return null
	for candidate: InputEvent in InputMap.action_get_events(action):
		if candidate is InputEventKey:
			return candidate
	return null


## 处理某一行发出的改键请求。
## @param action 动作名。
## @param event 玩家按下的按键事件。
## @return 无返回值。
func _on_binding_rebind_requested(action: StringName, event: InputEventKey) -> void:
	if _key_binding_manager == null:
		_set_binding_feedback("按键服务未就绪，本次修改没有生效。")
		return
	var result: Dictionary = _key_binding_manager.call("rebind", action, event)
	if not bool(result.get("ok", false)):
		_set_binding_feedback(String(result.get("reason", "改键失败，请重试。")))
		_refresh_binding_rows()
		return
	if not bool(result.get("saved", false)):
		_set_binding_feedback(BINDING_SAVE_FAILED_TEXT)
		return
	# 改键成功不再回显：列表里的键位文案与刚出现的「恢复默认」按钮本身就是结果。
	_set_binding_feedback("")


## 处理某一行「恢复默认」按钮的点击。
## @param action 动作名。
## @return 无返回值。
func _on_binding_reset_requested(action: StringName) -> void:
	if _key_binding_manager == null:
		_set_binding_feedback("按键服务未就绪，无法恢复默认。")
		return
	if not bool(_key_binding_manager.call("reset_action_to_default", action)):
		_set_binding_feedback(
			"「%s」没有可恢复的默认键位。" % String(KEY_BINDING_REGISTRY.call("get_display_name", action))
		)
		return
	_set_binding_feedback("")


## 处理「全部恢复默认」按钮。
## @return 无返回值。
func _on_reset_all_bindings_pressed() -> void:
	if _key_binding_manager == null:
		_set_binding_feedback("按键服务未就绪，无法恢复默认。")
		return
	_key_binding_manager.call("reset_all_to_defaults")
	_set_binding_feedback("")


## 转发局内测试死亡请求；死亡事实由暂停菜单通过生命组件产生。
## 返回值：无。
func _on_death_button_pressed() -> void:
	if not show_death_button or _death_button.disabled:
		return
	_cancel_binding_listening()
	_death_button.disabled = true
	death_requested.emit()


## 管理器广播某个动作改键成功时刷新列表。
## @param _action 动作名；刷新是全量的，因此这里不单独使用。
## @param _event 生效后的按键事件；同上。
## @return 无返回值。
func _on_binding_changed(_action: StringName, _event: InputEvent) -> void:
	_refresh_binding_rows()


## 管理器广播「全部恢复默认」时刷新列表。
## @return 无返回值。
func _on_bindings_reset() -> void:
	_refresh_binding_rows()


## 取消所有行的「等待按键」状态。
##
## 切走分类、收起面板时调用；否则会留下一个仍在拦截键盘的行，玩家之后按任何键都被吞掉。
## @return 无返回值。
func _cancel_binding_listening() -> void:
	for row: Variant in _binding_rows.values():
		if row is Node and (row as Node).has_method(&"cancel_listening"):
			(row as Node).call("cancel_listening")


## 更新按键分类的提示文案。
## @param text 需要展示的文案；为空时清空提示。
## @return 无返回值。
func _set_binding_feedback(text: String) -> void:
	_binding_feedback_label.text = text
