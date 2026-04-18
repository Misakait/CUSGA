extends Control

# 引用 InventoryComponent
@onready var inventory = $"../InventoryComponent"
@export var grid: Node2D

func _ready():
	refresh_ui()
# 刷新背包界面
func refresh_ui():
	var slots = inventory._slots
	for i in range(slots.size()):
		var slot = slots[i]
		var inventory_grid = grid.get_child(i)

		if slot.IsEmpty:
			inventory_grid.get_node("CardName").text = "-"
		else:
			inventory_grid.get_node("CardName").text = "%s x%d" % [slot.Item.CardName, slot.Amount]

# 点击按钮时尝试移动物品
func _on_slot_button_pressed(index):
	# 例如把点击的格子移到第0格
	inventory.MoveItem(index, 0)
	refresh_ui()


func _on_add_button_pressed() -> void:
	add_item("2",4)
	add_item("1",5)
	
func _on_remove_button_pressed() -> void:
	remove_item("2",5)
	
func add_item(cardid: StringName, cnt: int):
	var item: ItemData = ItemsControl.get_item(cardid)
		
	if item:
		var overflow_item: int = 0
		overflow_item = inventory.AddItem(item, cnt)
		if overflow_item > 0:
			print("仓库放不下 ",item.CardName," 了,溢出了",overflow_item,"个")
		refresh_ui()
	else:
		print("item不存在")
	
func remove_item(cardid: StringName, cnt: int):
	var item: ItemData = ItemsControl.get_item(cardid)
		
	if item:
		if inventory.HasItem(item, cnt):
			inventory.RemoveItem(item, cnt)
		else:
			print("仓库的 ",item.CardName," 不够！还差",cnt - inventory.ItemCnt(item),"个")
		refresh_ui()
	else:
		print("item不存在")
		
