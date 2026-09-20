extends PanelContainer

## 角色属性摘要的 GDScript 生产视图。
##
## 该视图只读取 AttributeComponent 的稳定方法和信号，不参与属性计算。当前 C#
## InventoryUI 通过 Node 与 Bind 方法名调用本视图，便于属性组件后续独立迁移。

## 物理攻击枚举值；必须与 C# AttributeType.PhysAtk 保持为 0。
const ATTRIBUTE_TYPE_PHYS_ATK: int = 0
## 物理防御枚举值；必须与 C# AttributeType.PhysDef 保持为 1。
const ATTRIBUTE_TYPE_PHYS_DEF: int = 1
## 法术强度枚举值；必须与 C# AttributeType.MagPower 保持为 2。
const ATTRIBUTE_TYPE_MAG_POWER: int = 2
## 法术抗性枚举值；必须与 C# AttributeType.MagResist 保持为 3。
const ATTRIBUTE_TYPE_MAG_RESIST: int = 3
## 速度枚举值；必须与 C# AttributeType.Speed 保持为 4。
const ATTRIBUTE_TYPE_SPEED: int = 4
## 最大生命枚举值；必须与 C# AttributeType.MaxHealth 保持为 5。
const ATTRIBUTE_TYPE_MAX_HEALTH: int = 5
## 最大能量枚举值；必须与 C# AttributeType.MaxEnergy 保持为 6。
const ATTRIBUTE_TYPE_MAX_ENERGY: int = 6
## 固定物理穿透枚举值；必须与 C# AttributeType.FixedPhysPenetration 保持为 7。
const ATTRIBUTE_TYPE_FIXED_PHYS_PENETRATION: int = 7
## 物理穿透率枚举值；必须与 C# AttributeType.PhysPenetrationRate 保持为 8。
const ATTRIBUTE_TYPE_PHYS_PENETRATION_RATE: int = 8
## 固定法术穿透枚举值；必须与 C# AttributeType.FixedMagicPenetration 保持为 9。
const ATTRIBUTE_TYPE_FIXED_MAGIC_PENETRATION: int = 9
## 法术穿透率枚举值；必须与 C# AttributeType.MagicPenetrationRate 保持为 10。
const ATTRIBUTE_TYPE_MAGIC_PENETRATION_RATE: int = 10
## 暴击率枚举值；必须与 C# AttributeType.CritRate 保持为 11。
const ATTRIBUTE_TYPE_CRIT_RATE: int = 11
## 暴击伤害枚举值；必须与 C# AttributeType.CritDamage 保持为 12。
const ATTRIBUTE_TYPE_CRIT_DAMAGE: int = 12
## 闪避率枚举值；必须与 C# AttributeType.EvasionRate 保持为 13。
const ATTRIBUTE_TYPE_EVASION_RATE: int = 13
## 吸血率枚举值；必须与 C# AttributeType.LifestealRate 保持为 14。
const ATTRIBUTE_TYPE_LIFESTEAL_RATE: int = 14

## 当前绑定的旧 C# 或未来 GDScript AttributeComponent。
var _attributes: Node = null
## 摘要区物理攻击数值标签。
var _phys_atk_value: Label = null
## 摘要区物理防御数值标签。
var _phys_def_value: Label = null
## 摘要区法术强度数值标签。
var _mag_power_value: Label = null
## 摘要区法术抗性数值标签。
var _mag_resist_value: Label = null
## 摘要区速度数值标签。
var _speed_value: Label = null
## 打开详细属性弹窗的按钮。
var _details_button: Button = null
## 承载完整战斗属性的弹窗。
var _details_popup: PopupPanel = null
## 详情区最大生命数值标签。
var _max_health_detail_value: Label = null
## 详情区最大能量数值标签。
var _max_energy_detail_value: Label = null
## 详情区物理穿透数值标签。
var _phys_penetration_detail_value: Label = null
## 详情区法术穿透数值标签。
var _magic_penetration_detail_value: Label = null
## 详情区暴击率数值标签。
var _crit_rate_detail_value: Label = null
## 详情区暴击伤害数值标签。
var _crit_damage_detail_value: Label = null
## 详情区闪避率数值标签。
var _evasion_rate_detail_value: Label = null
## 详情区吸血率数值标签。
var _lifesteal_rate_detail_value: Label = null


## 解析生产场景中的唯一名称节点、连接详情按钮并显示当前绑定状态。
## 返回值：无。
func _ready() -> void:
	_phys_atk_value = get_node("%PhysAtkValue") as Label
	_phys_def_value = get_node("%PhysDefValue") as Label
	_mag_power_value = get_node("%MagPowerValue") as Label
	_mag_resist_value = get_node("%MagResistValue") as Label
	_speed_value = get_node("%SpeedValue") as Label
	_details_button = get_node("%DetailsButton") as Button
	_details_popup = get_node("%AttributeDetailsPopup") as PopupPanel
	_max_health_detail_value = get_node("%MaxHealthDetailValue") as Label
	_max_energy_detail_value = get_node("%MaxEnergyDetailValue") as Label
	_phys_penetration_detail_value = get_node("%PhysPenetrationDetailValue") as Label
	_magic_penetration_detail_value = get_node("%MagicPenetrationDetailValue") as Label
	_crit_rate_detail_value = get_node("%CritRateDetailValue") as Label
	_crit_damage_detail_value = get_node("%CritDamageDetailValue") as Label
	_evasion_rate_detail_value = get_node("%EvasionRateDetailValue") as Label
	_lifesteal_rate_detail_value = get_node("%LifestealRateDetailValue") as Label
	if not _details_button.pressed.is_connected(_on_details_button_pressed):
		_details_button.pressed.connect(_on_details_button_pressed)
	_refresh()


## 绑定属性组件并同步摘要和详情；重复绑定同一组件时仍会主动刷新。
## 参数 attributes：提供 GetEffectiveValue、AttributeChanged 和 AvailablePointsChanged 的属性组件；可为 null。
## 返回值：无。
func Bind(attributes: Node) -> void:
	if _attributes == attributes:
		_refresh()
		return
	_disconnect_attribute_signals()
	_attributes = attributes
	_connect_attribute_signals()
	_refresh()


## 退出场景时解除按钮及属性组件信号，避免隐藏界面保留失效回调。
## 返回值：无。
func _exit_tree() -> void:
	if _details_button != null and _details_button.pressed.is_connected(_on_details_button_pressed):
		_details_button.pressed.disconnect(_on_details_button_pressed)
	_disconnect_attribute_signals()


## 连接新旧 AttributeComponent 共同暴露的稳定信号。
func _connect_attribute_signals() -> void:
	if _attributes == null:
		return
	# 固定回调身份用于去重连接 AttributeChanged。
	var attribute_changed_callback := Callable(self, "_on_attribute_changed")
	if _attributes.has_signal(&"AttributeChanged") and not _attributes.is_connected(&"AttributeChanged", attribute_changed_callback):
		_attributes.connect(&"AttributeChanged", attribute_changed_callback)
	# 固定回调身份用于去重连接 AvailablePointsChanged。
	var available_points_callback := Callable(self, "_on_available_points_changed")
	if _attributes.has_signal(&"AvailablePointsChanged") and not _attributes.is_connected(&"AvailablePointsChanged", available_points_callback):
		_attributes.connect(&"AvailablePointsChanged", available_points_callback)


## 解除当前 AttributeComponent 的两个刷新信号。
func _disconnect_attribute_signals() -> void:
	if _attributes == null:
		return
	# 使用与连接阶段相同的方法身份解除 AttributeChanged。
	var attribute_changed_callback := Callable(self, "_on_attribute_changed")
	if _attributes.has_signal(&"AttributeChanged") and _attributes.is_connected(&"AttributeChanged", attribute_changed_callback):
		_attributes.disconnect(&"AttributeChanged", attribute_changed_callback)
	# 使用与连接阶段相同的方法身份解除 AvailablePointsChanged。
	var available_points_callback := Callable(self, "_on_available_points_changed")
	if _attributes.has_signal(&"AvailablePointsChanged") and _attributes.is_connected(&"AvailablePointsChanged", available_points_callback):
		_attributes.disconnect(&"AvailablePointsChanged", available_points_callback)


## 属性变化后统一刷新全部展示值。
## 参数 change_event：属性组件发出的变更上下文；摘要无需区分具体属性。
func _on_attribute_changed(_change_event: Variant) -> void:
	_refresh()


## 可用点数变化后统一刷新，保持与旧 C# 视图相同的事件边界。
## 参数 available_points：属性组件变更后的剩余点数；摘要不直接显示该值。
func _on_available_points_changed(_available_points: int) -> void:
	_refresh()


## 同步五项摘要与完整详情；节点尚未 Ready 时只保留绑定状态。
func _refresh() -> void:
	if not is_node_ready():
		return
	_set_value(_phys_atk_value, ATTRIBUTE_TYPE_PHYS_ATK)
	_set_value(_phys_def_value, ATTRIBUTE_TYPE_PHYS_DEF)
	_set_value(_mag_power_value, ATTRIBUTE_TYPE_MAG_POWER)
	_set_value(_mag_resist_value, ATTRIBUTE_TYPE_MAG_RESIST)
	_set_value(_speed_value, ATTRIBUTE_TYPE_SPEED)
	_refresh_details()


## 在打开弹窗前重新读取详情，确保隐藏期间发生的变化不会展示旧值。
func _on_details_button_pressed() -> void:
	_refresh_details()
	_details_popup.popup_centered()


## 同步生命、能量、穿透及四项百分比详情。
func _refresh_details() -> void:
	_set_value(_max_health_detail_value, ATTRIBUTE_TYPE_MAX_HEALTH)
	_set_value(_max_energy_detail_value, ATTRIBUTE_TYPE_MAX_ENERGY)
	_set_penetration_value(
		_phys_penetration_detail_value,
		ATTRIBUTE_TYPE_FIXED_PHYS_PENETRATION,
		ATTRIBUTE_TYPE_PHYS_PENETRATION_RATE
	)
	_set_penetration_value(
		_magic_penetration_detail_value,
		ATTRIBUTE_TYPE_FIXED_MAGIC_PENETRATION,
		ATTRIBUTE_TYPE_MAGIC_PENETRATION_RATE
	)
	_set_percent_value(_crit_rate_detail_value, ATTRIBUTE_TYPE_CRIT_RATE)
	_set_percent_value(_crit_damage_detail_value, ATTRIBUTE_TYPE_CRIT_DAMAGE)
	_set_percent_value(_evasion_rate_detail_value, ATTRIBUTE_TYPE_EVASION_RATE)
	_set_percent_value(_lifesteal_rate_detail_value, ATTRIBUTE_TYPE_LIFESTEAL_RATE)


## 写入普通数值；未绑定属性组件时使用短横线占位。
func _set_value(label: Label, attribute_type: int) -> void:
	label.text = "-" if _attributes == null else _format_number(_get_effective_value(attribute_type))


## 写入“固定值 | 百分比”格式的穿透属性。
func _set_penetration_value(label: Label, fixed_type: int, rate_type: int) -> void:
	if _attributes == null:
		label.text = "-"
		return
	label.text = "%s | %s%%" % [
		_format_number(_get_effective_value(fixed_type)),
		_format_number(_get_effective_value(rate_type) * 100.0),
	]


## 将 0 到 1 范围的比率转换为最多一位小数的百分比文本。
func _set_percent_value(label: Label, attribute_type: int) -> void:
	if _attributes == null:
		label.text = "-"
		return
	label.text = "%s%%" % _format_number(_get_effective_value(attribute_type) * 100.0)


## 通过稳定方法名读取旧 C# 或未来 GDScript 属性组件的最终值。
## 参数 attribute_type：与 AttributeType 完全一致的整数值。
## 返回值：最终属性值；组件缺少方法时返回 0，避免视图承担属性计算。
func _get_effective_value(attribute_type: int) -> float:
	if _attributes == null or not _attributes.has_method("GetEffectiveValue"):
		return 0.0
	return float(_attributes.call("GetEffectiveValue", attribute_type))


## 把整数显示为无小数文本，其余数值按旧格式四舍五入到最多一位小数。
## 参数 value：需要呈现的属性数值。
## 返回值：整数或一位小数文本。
func _format_number(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(roundi(value))
	return "%.1f" % value
