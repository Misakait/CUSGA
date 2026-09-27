extends PanelContainer

## 大地图的可滚动标记选择图例。
##
## 图例只维护选择状态并发出配置 Resource，不直接新增或删除 Model 记录。

signal marker_config_selected(config: Resource)

## 可供玩家选择的标记配置；不可显示、未激活或禁止手动放置的项会被过滤。
@export var marker_configs: Array[Resource] = []

var _selected_config: Resource = null
var _button_group: ButtonGroup = ButtonGroup.new()

@onready var _options_list: VBoxContainer = %OptionsList
@onready var _status_label: Label = %StatusLabel


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_options()


## 返回当前选中的玩家标记配置。
##
## @return 尚无可用选项时返回 null。
func get_selected_config() -> Resource:
	return _selected_config


## 重新读取导出配置并构建可滚动选项。
##
## @return 无返回值。
func refresh_options() -> void:
	_build_options()


func _build_options() -> void:
	for child: Node in _options_list.get_children():
		child.queue_free()
	_button_group = ButtonGroup.new()
	_selected_config = null
	for config: Resource in marker_configs:
		if not _is_player_option(config):
			continue
		var button := Button.new()
		button.custom_minimum_size = Vector2(0.0, 42.0)
		button.toggle_mode = true
		button.button_group = _button_group
		button.text = str(config.get("display_name"))
		button.icon = config.get("icon") as Texture2D
		button.expand_icon = true
		# icon_max_width 是 Button 的主题常量，不是可直接赋值的节点属性。
		button.add_theme_constant_override(&"icon_max_width", 28)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(_on_option_pressed.bind(config))
		_options_list.add_child(button)
		if _selected_config == null:
			button.button_pressed = true
			_select_config(config)
	if _selected_config == null:
		_status_label.text = "当前没有可放置标记"


func _on_option_pressed(config: Resource) -> void:
	_select_config(config)


func _select_config(config: Resource) -> void:
	_selected_config = config
	_status_label.text = "已选择：%s" % str(config.get("display_name"))
	marker_config_selected.emit(config)


func _is_player_option(config: Resource) -> bool:
	return (
		config != null
		and bool(config.get("allow_map_display"))
		and bool(config.get("active"))
		and bool(config.get("player_placeable"))
		and config.get("icon") is Texture2D
	)
