extends "res://scripts/ui_scripts/backpack_item_slot.gd"

## 结算专用物品格子；参数由 bind_snapshot 提供，返回值见各接口。
## 只展示隔离后的物品堆叠，不连接死亡玩家的库存或任何资产操作。

func _ready() -> void:
	super._ready()
	pressed.connect(_on_snapshot_pressed)

## 绑定固定的结算收获，空值表示空格。
## 参数 index：结果中的格子索引；stack：真实 ItemStack 或空值。
## 返回值：无；内部复制堆叠，外部变更不会修改本格结果。
func bind_snapshot(index: int, stack: Variant) -> void:
	var snapshot: Variant = null
	if stack is Object and (stack as Object).has_method("Duplicate"):
		snapshot = (stack as Object).call("Duplicate")
	bind_inventory(index, snapshot, null)
	configure_display(true, false)

func _gui_input(_event: InputEvent) -> void:
	# 原生 Button 的松开负责结束瞬时按压；结算不继承背包快捷键和操作菜单。
	pass

func _get_drag_data(_at_position: Vector2) -> Variant:
	# 物品已经由经理入账，拖出结果副本会制造第二份物品，因此明确拒绝拖动。
	return null

func _can_drop_data(_at_position: Vector2, _data: Variant) -> bool:
	return false

func _drop_data(_at_position: Vector2, _data: Variant) -> void:
	pass

func _on_snapshot_pressed() -> void:
	if item_data != null:
		slot_clicked.emit(self)
