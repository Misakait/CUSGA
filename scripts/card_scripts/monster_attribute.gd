extends VBoxContainer

## 怪物五维属性显示组件。
## 挂载在 monster.tscn 的 MonsterAttribute 节点上，从父级 Monster 的 AttributeComponent 读取最终属性值，
## 并同步显示物攻、法强、物抗、法抗、速度。组件只负责展示，不参与怪物数据初始化和战斗计算。

const ATTRIBUTE_TYPE_PHYS_ATK: int = 0 ## AttributeType.PhysAtk，用于读取物理攻击。
const ATTRIBUTE_TYPE_PHYS_DEF: int = 1 ## AttributeType.PhysDef，用于读取物理抗性。
const ATTRIBUTE_TYPE_MAG_POWER: int = 2 ## AttributeType.MagPower，用于读取法术强度。
const ATTRIBUTE_TYPE_MAG_RESIST: int = 3 ## AttributeType.MagResist，用于读取法术抗性。
const ATTRIBUTE_TYPE_SPEED: int = 4 ## AttributeType.Speed，用于读取速度。

@export var empty_value_text: String = "--" ## 怪物尚未初始化或属性组件缺失时显示的占位文本。
@export var integer_display: bool = true ## 当前怪物五维使用整数显示，后续若出现小数属性可在检查器关闭。

@onready var _phy_power_label: Label = $power/PhyLabel
@onready var _mag_power_label: Label = $power/MagLabel
@onready var _phy_def_label: Label = $def/PhyLabel
@onready var _mag_def_label: Label = $def/MagLabel
@onready var _speed_label: Label = $speed/Label

var _monster_entity: Node = null
var _attribute_component: Node = null

func _ready() -> void:
	# MonsterAttribute 是 Monster 的子节点，子节点 _ready 会早于父节点；延迟刷新可确保 Monster.Initialize 已把 BaseData 写入组件。
	call_deferred("refresh")

## 重新绑定当前怪物并刷新五维显示。
## 使用场景：怪物生成、怪物数据被重新 Initialize、外部系统希望强制同步属性 UI。
func refresh() -> void:
	_resolve_attribute_component()
	_connect_attribute_changed_signal()
	_update_all_labels()

## 从父级怪物节点定位 AttributeComponent。
## 该脚本默认挂载在 MonsterAttribute，父节点就是怪物实体；若未来调整层级，可通过向上查找保持兼容。
func _resolve_attribute_component() -> void:
	_monster_entity = _find_monster_entity()
	_attribute_component = null

	if _monster_entity and _monster_entity.has_method("get_node_or_null"):
		_attribute_component = _monster_entity.get_node_or_null("Components/AttributeComponent")

## 查找承载怪物数据和组件的实体节点。
## 返回值：找到的怪物 Node；找不到时返回 null。
func _find_monster_entity() -> Node:
	var current := get_parent()
	while current:
		if current.has_method("get_node_or_null") and current.get_node_or_null("Components/AttributeComponent"):
			return current
		current = current.get_parent()

	return null

## 监听属性变化，确保怪物被 Buff、减益或成长系统影响后 UI 自动刷新。
func _connect_attribute_changed_signal() -> void:
	if not _attribute_component:
		return

	if _attribute_component.has_signal("AttributeChanged"):
		var callable := Callable(self, "_on_attribute_changed")
		if not _attribute_component.is_connected("AttributeChanged", callable):
			_attribute_component.connect("AttributeChanged", callable)

## AttributeComponent.AttributeChanged 的回调。
## 参数 event 由 C# 属性系统提供；统一刷新五项显示，避免 UI 侧复制属性枚举判断逻辑。
func _on_attribute_changed(_event: RefCounted) -> void:
	_update_all_labels()

## 将怪物五维写入对应 Label。
func _update_all_labels() -> void:
	if not _attribute_component:
		_set_empty_labels()
		return

	_phy_power_label.text = _format_attribute_value(_get_attribute_value(ATTRIBUTE_TYPE_PHYS_ATK))
	_mag_power_label.text = _format_attribute_value(_get_attribute_value(ATTRIBUTE_TYPE_MAG_POWER))
	_phy_def_label.text = _format_attribute_value(_get_attribute_value(ATTRIBUTE_TYPE_PHYS_DEF))
	_mag_def_label.text = _format_attribute_value(_get_attribute_value(ATTRIBUTE_TYPE_MAG_RESIST))
	_speed_label.text = _format_attribute_value(_get_attribute_value(ATTRIBUTE_TYPE_SPEED))

## 读取指定属性类型的最终值。
## 参数 attribute_type：C# AttributeType 枚举对应的整数值。
## 返回值：属性最终值；无法读取时返回 null。
func _get_attribute_value(attribute_type: int) -> Variant:
	if not _attribute_component:
		return null

	if _attribute_component.has_method("GetEffectiveValue"):
		return _attribute_component.call("GetEffectiveValue", attribute_type)

	return null

## 格式化属性值。
## 参数 value：属性数值或 null。
## 返回值：用于 Label.text 的显示字符串。
func _format_attribute_value(value: Variant) -> String:
	if value == null:
		return empty_value_text

	var numeric_value := float(value)
	if integer_display:
		return str(roundi(numeric_value))

	return str(snappedf(numeric_value, 0.01))

## 没有可用属性来源时清空为兜底文本，避免显示 scene 中的编辑器测试值。
func _set_empty_labels() -> void:
	_phy_power_label.text = empty_value_text
	_mag_power_label.text = empty_value_text
	_phy_def_label.text = empty_value_text
	_mag_def_label.text = empty_value_text
	_speed_label.text = empty_value_text
