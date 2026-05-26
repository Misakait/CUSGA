extends VBoxContainer

## 玩家五维属性显示组件。
## 挂载在战斗场景的 PlayerAttribute 节点上，负责从当前玩家实体的 AttributeComponent 读取最终属性值，
## 并把物攻、法强、物抗、法抗、速度同步到对应 Label。该脚本只依赖节点约定和 AttributeComponent，
## 不直接持有战斗管理器引用，方便单独复用到其它玩家属性展示界面。

const ATTRIBUTE_TYPE_PHYS_ATK: int = 0 ## AttributeType.PhysAtk，用于读取物理攻击。
const ATTRIBUTE_TYPE_PHYS_DEF: int = 1 ## AttributeType.PhysDef，用于读取物理抗性。
const ATTRIBUTE_TYPE_MAG_POWER: int = 2 ## AttributeType.MagPower，用于读取法术强度。
const ATTRIBUTE_TYPE_MAG_RESIST: int = 3 ## AttributeType.MagResist，用于读取法术抗性。
const ATTRIBUTE_TYPE_SPEED: int = 4 ## AttributeType.Speed，用于读取速度。

@export var empty_value_text: String = "--" ## 找不到属性组件时显示的兜底文本，避免界面残留编辑器里的测试值。
@export var integer_display: bool = true ## 当前五维都是整数语义，默认四舍五入显示，后续若支持小数属性可在检查器关闭。

@onready var _phy_power_label: Label = $attribute/PhyPowerLabel
@onready var _mag_power_label: Label = $attribute/MagPowerLabel
@onready var _phy_def_label: Label = $attribute/PhyDefLabel
@onready var _mag_def_label: Label = $attribute/MagDefLabel
@onready var _speed_label: Label = $attribute/SpeedLabel

var _player_entity: Node = null
var _attribute_component: Node = null

func _ready() -> void:
	# 玩家实体可能由同一场景中的 PlayerManager 稍后初始化；延迟一帧可以避开兄弟节点 ready 顺序差异。
	call_deferred("refresh")

## 重新查找玩家实体并刷新五维显示。
## 使用场景：战斗场景刚载入、玩家节点被替换、外部系统希望手动强制同步 UI。
func refresh() -> void:
	_resolve_attribute_component()
	_connect_attribute_changed_signal()
	_update_all_labels()

## 定位当前战斗中应该展示的玩家 AttributeComponent。
## 查找顺序优先使用 PlayerManager 暴露的真实战斗实体，其次兼容全局玩家和常见场景路径。
func _resolve_attribute_component() -> void:
	_player_entity = _find_player_entity()
	_attribute_component = null

	if _player_entity and _player_entity.has_method("get_node_or_null"):
		_attribute_component = _player_entity.get_node_or_null("Components/AttributeComponent")

## 查找玩家实体。
## 返回值：找到的玩家 Node；找不到时返回 null，并由显示层使用兜底文本。
func _find_player_entity() -> Node:
	var player_manager := get_tree().current_scene.get_node_or_null("PlayerManager") if get_tree().current_scene else null
	if player_manager:
		if player_manager.has_method("get_combat_entity"):
			var combat_entity = player_manager.call("get_combat_entity")
			if combat_entity:
				return combat_entity

		var local_player = player_manager.get_node_or_null("Player")
		if local_player:
			return local_player

	var grouped_players := get_tree().get_nodes_in_group("Player")
	if grouped_players.size() > 0:
		return grouped_players[0]

	var gameplay_port := get_tree().root.get_node_or_null("Main/Gameplay/GameplayPort")
	if gameplay_port and gameplay_port.get("Player") != null:
		return gameplay_port.get("Player")

	return get_tree().root.get_node_or_null("Main/Player")

## 监听属性变化，确保战斗中 Buff 或其它系统改变五维时 UI 能自动刷新。
func _connect_attribute_changed_signal() -> void:
	if not _attribute_component:
		return

	if _attribute_component.has_signal("AttributeChanged"):
		var callable := Callable(self, "_on_attribute_changed")
		if not _attribute_component.is_connected("AttributeChanged", callable):
			_attribute_component.connect("AttributeChanged", callable)

## AttributeComponent.AttributeChanged 的回调。
## 参数 event 由 C# 侧 AttributeChangedEvent 提供；本组件不关心具体哪一项变化，统一刷新可降低 UI 与属性枚举的耦合。
func _on_attribute_changed(_event: RefCounted) -> void:
	_update_all_labels()

## 将五维属性写入对应 Label。
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

## 没有可用属性来源时清空为兜底文本，避免误导玩家。
func _set_empty_labels() -> void:
	_phy_power_label.text = empty_value_text
	_mag_power_label.text = empty_value_text
	_phy_def_label.text = empty_value_text
	_mag_def_label.text = empty_value_text
	_speed_label.text = empty_value_text
