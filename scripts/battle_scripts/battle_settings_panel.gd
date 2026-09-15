## 战斗操作模式设置面板。
## 该组件只管理设置入口和选项展示，并通过信号把玩家选择交给 CardManager，
## 以保持 UI 与卡牌输入规则之间的低耦合。
extends Control

## 当玩家选择新的操作模式时发出。
## 参数是 CardManager 提供的稳定模式值，而不是界面显示文本。
signal operation_mode_selected(operation_mode: String)

## 当玩家选择新的战斗表现强度时发出，参数是稳定的内部值。
signal feedback_intensity_selected(feedback_intensity: String)

## 右上角用于展开或收起设置面板的按钮。
## 该节点必须保留在本组件根节点下的固定路径；缺失时设置功能不可用。
@onready var _settings_button: Button = $SettingsButton

## 承载操作模式下拉选择器的弹出面板。
## 初始保持隐藏，避免战斗开始时遮挡场景。
@onready var _settings_popup: PanelContainer = $SettingsPopup

## 用于显示“点击”和“拖拽”模式的选择控件。
## 选项顺序由 configure_options 的参数决定，不能自行假定固定索引。
@onready var _operation_mode_option: OptionButton = $SettingsPopup/MarginContainer/ModeContainer/OperationModeOption

## 用于显示表现强度选项的标题。
@onready var _feedback_intensity_title: Label = $SettingsPopup/MarginContainer/ModeContainer/FeedbackIntensityTitle

## 用于显示完整与减弱表现强度的选择控件。
@onready var _feedback_intensity_option: OptionButton = $SettingsPopup/MarginContainer/ModeContainer/FeedbackIntensityOption

## OptionButton 索引对应的内部模式值。
## 仅保存由 CardManager 提供的值，用于将本地化显示文本安全转换回业务值。
var _mode_values: Array[String] = []

## 表现强度选择器索引对应的稳定内部值。
var _feedback_intensity_values: Array[String] = []

## 连接本组件拥有的控件信号并隐藏弹出面板。
## @return void 无返回值。
func _ready() -> void:
	_settings_popup.hide()
	_settings_button.pressed.connect(_on_settings_button_pressed)
	_operation_mode_option.item_selected.connect(_on_operation_mode_item_selected)
	_feedback_intensity_option.item_selected.connect(_on_feedback_intensity_item_selected)

## 用 CardManager 定义的操作模式填充选项并同步当前值。
## @param mode_options 每项包含 value（内部值）与 label（界面文本）的字典数组。
## @param active_mode 当前已经生效的内部模式值。
## @return void 无返回值。
func configure_options(mode_options: Array[Dictionary], active_mode: String) -> void:
	_mode_values.clear()
	_operation_mode_option.clear()

	for mode_option: Dictionary in mode_options:
		# 当前选项的稳定模式值，用于写入配置而不依赖显示文本。
		var mode_value: String = str(mode_option.get("value", ""))
		# 当前选项的本地化显示文案，缺失时回退到稳定模式值以保持可用。
		var mode_label: String = str(mode_option.get("label", mode_value))
		if mode_value.is_empty():
			continue
		_mode_values.append(mode_value)
		_operation_mode_option.add_item(mode_label)

	set_active_mode(active_mode)

## 同步选择控件显示的当前模式，不触发新的业务写入。
## @param active_mode 需要显示为已选择的内部模式值。
## @return void 无返回值。
func set_active_mode(active_mode: String) -> void:
	# 当前模式在下拉选项数组中的索引；-1 表示调用方给出了未配置值。
	var mode_index: int = _mode_values.find(active_mode)
	if mode_index >= 0:
		_operation_mode_option.select(mode_index)

## 用表现强度选项填充选择器并同步当前值。
## @param intensity_options 每项包含 value 和 label 的字典数组。
## @param active_intensity 当前已经生效的稳定值。
## @return void 无返回值。
func configure_feedback_intensity_options(intensity_options: Array[Dictionary], active_intensity: String) -> void:
	_feedback_intensity_values.clear()
	_feedback_intensity_option.clear()
	for intensity_option: Dictionary in intensity_options:
		var intensity_value: String = str(intensity_option.get("value", ""))
		var intensity_label: String = str(intensity_option.get("label", intensity_value))
		if intensity_value.is_empty():
			continue
		_feedback_intensity_values.append(intensity_value)
		_feedback_intensity_option.add_item(intensity_label)
	set_active_feedback_intensity(active_intensity)

## 同步表现强度选择器显示值，不触发写入行为。
## @param active_intensity 当前已经生效的稳定值。
## @return void 无返回值。
func set_active_feedback_intensity(active_intensity: String) -> void:
	var intensity_index: int = _feedback_intensity_values.find(active_intensity)
	if intensity_index >= 0:
		_feedback_intensity_option.select(intensity_index)

## 切换设置弹出面板的可见状态。
## @return void 无返回值。
func _on_settings_button_pressed() -> void:
	_settings_popup.visible = not _settings_popup.visible

## 将玩家选择的索引转换为模式值并通知卡牌输入拥有者。
## @param selected_index OptionButton 当前被选择的索引。
## @return void 无返回值。
func _on_operation_mode_item_selected(selected_index: int) -> void:
	if selected_index < 0 or selected_index >= _mode_values.size():
		push_warning("操作模式选择索引无效：%s" % selected_index)
		return

	operation_mode_selected.emit(_mode_values[selected_index])
	_settings_popup.hide()

## 将表现强度选择器索引转换为稳定值后通知领域拥有者。
## @param selected_index 表现强度选择器当前索引。
## @return void 无返回值。
func _on_feedback_intensity_item_selected(selected_index: int) -> void:
	if selected_index < 0 or selected_index >= _feedback_intensity_values.size():
		push_warning("战斗表现强度索引无效：%s" % selected_index)
		return
	feedback_intensity_selected.emit(_feedback_intensity_values[selected_index])
	_settings_popup.hide()
