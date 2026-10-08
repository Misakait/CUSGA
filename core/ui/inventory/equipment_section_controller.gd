extends GridContainer

## 角色装备区域 Controller。
## 装备槽位数量和合法性由 EquipmentComponent 及稳定枚举提供，本脚本只复用 ItemSlot 视图。

const ITEM_SLOT_SCENE: PackedScene = preload("res://scenes/ui/item_slot.tscn")
const EQUIPMENT_TYPES: GDScript = preload("res://core/constants/equipment_types.gd")

var _equipment: Node = null
var _tooltip_presenter: Variant = null
var _slots: Array[ItemSlot] = []

## 绑定装备组件并刷新固定的 16 个装备槽。
## @param equipment EquipmentComponent 实例。
## @param tooltip_presenter 共享提示框 Presenter。
func Bind(equipment: Node, tooltip_presenter: Variant) -> void:
	if _equipment != equipment:
		_disconnect_equipment()
	_equipment = equipment
	_connect_equipment()
	_tooltip_presenter = tooltip_presenter
	Refresh()

## 按 EquipmentSlot 稳定枚举顺序创建或复用 ItemSlot。
func Refresh() -> void:
	var slot_values: Array = EQUIPMENT_TYPES.EquipmentSlot.values()
	while _slots.size() > slot_values.size():
		var removed: ItemSlot = _slots.pop_back()
		removed.queue_free()
	while _slots.size() < slot_values.size():
		_create_slot()
	for index in slot_values.size():
		var slot_value: int = int(slot_values[index])
		_slots[index].configure_display(false, false)
		_slots[index].set_empty_label(_get_slot_label(slot_value))
		_slots[index].bind_equipment(_equipment, slot_value, _tooltip_presenter)

## 返回当前装备格子。
## @return Array[ItemSlot] 当前格子列表。
func GetSlots() -> Array[ItemSlot]:
	return _slots

func _create_slot() -> void:
	var slot: ItemSlot = ITEM_SLOT_SCENE.instantiate() as ItemSlot
	slot.configure_compact_layout(0.8)
	add_child(slot)
	_slots.append(slot)

func _connect_equipment() -> void:
	if _equipment != null and _equipment.has_signal("EquipmentChanged"):
		var callback := Callable(self, "_on_equipment_changed")
		if not _equipment.is_connected("EquipmentChanged", callback):
			_equipment.connect("EquipmentChanged", callback)

func _disconnect_equipment() -> void:
	if _equipment != null and _equipment.has_signal("EquipmentChanged"):
		var callback := Callable(self, "_on_equipment_changed")
		if _equipment.is_connected("EquipmentChanged", callback):
			_equipment.disconnect("EquipmentChanged", callback)

func _on_equipment_changed() -> void:
	Refresh()

func _get_slot_label(slot: int) -> String:
	match slot:
		0: return "头盔"
		1: return "胸甲"
		2: return "护腿"
		3: return "靴子"
		4: return "武器"
		5: return "斧头"
		6: return "镐子"
		7: return "鱼竿"
		8: return "左护手"
		9: return "右护手"
		10: return "火把"
		11: return "吊坠"
		12: return "戒指一"
		13: return "戒指二"
		14: return "腰带"
		15: return "魔法物品"
		_: return str(slot)

func _exit_tree() -> void:
	_disconnect_equipment()
