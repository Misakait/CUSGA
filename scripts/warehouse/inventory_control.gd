extends Control

# 引用 InventoryComponent
@onready var inventory = $"../InventoryComponent"
@export var inventory_grid: Node2D
@export var null_texture: Texture
@export var page_label: Label
#每页的格子数
@export var page_cnt: int = 27
#仓库的页数
@export var page_mag: int = 1
#玩家所处的页数
var now_page: int = 1

func _ready():
	refresh_ui()
# 刷新背包界面
func refresh_ui():
	page_label.text = "%d / %d" % [now_page , page_mag]

	var now_index: int = page_cnt * (now_page-1)
	for i in range(now_index, now_index + page_cnt):
		var slot = inventory.GetStackAt(i)
		var grid = inventory_grid.get_child(i%27)

		if slot.IsEmpty:
			grid.my_card_name.text = "-"
			grid.item_data = null
			grid.item_cnt = 0
			grid.sp2d.get_child(0).texture = null
		else:
			grid.my_card_name.text = "%s x%d" % [slot.Item.CardName, slot.Amount]
			#print(i," 原本: ",inventory_grid.item_data," 与 ",inventory_grid.item_cnt,"\n 之后: ", slot.Item," 与 ",slot.Amount)
			grid.item_data = slot.Item
			grid.item_cnt = slot.Amount
			grid.sp2d.get_child(0).texture = slot.Item.CardIcon

	for i in range(1,6):
		var usercard_path: NodePath = "usercard_%d" % i
		var grid = inventory_grid.get_node(usercard_path)
		if grid != null and grid.item_data != null :
			grid.sp2d.get_child(0).texture = grid.item_data.CardIcon
		if grid != null and grid.item_data == null:
			grid.sp2d.get_child(0).texture = null


# 点击按钮时尝试移动物品
func _on_slot_button_pressed(index):
	# 例如把点击的格子移到第0格
	inventory.MoveItem(index, 0)
	refresh_ui()

func _on_remove_button_pressed() -> void:
	remove_item_by_name("2",5)

func add_item_by_name(cardid: StringName, cnt: int):
	var item: ItemData = ItemsControl.get_item(cardid)

	if item:
		var overflow_item: int = 0
		overflow_item = inventory.AddItem(item, cnt)
		if overflow_item > 0:
			print("仓库放不下 ",item.CardName," 了,溢出了",overflow_item,"个")
		refresh_ui()
	else:
		print("item不存在")

func add_item_by_item(item: ItemData, cnt: int):
	if item:
		var overflow_item: int = 0
		overflow_item = inventory.AddItem(item, cnt)
		if overflow_item > 0:
			print("仓库放不下 ",item.CardName," 了,溢出了",overflow_item,"个")
		refresh_ui()
	else:
		print("item不存在")

func remove_item_by_name(cardid: StringName, cnt: int):
	var item: ItemData = ItemsControl.get_item(cardid)

	if item:
		if inventory.HasItem(item, cnt):
			inventory.RemoveItem(item, cnt)
		else:
			print("仓库的 ",item.CardName," 不够！还差",cnt - inventory.ItemCnt(item),"个")
		refresh_ui()
	else:
		print("item不存在")

func remove_item_by_item(item: ItemData, cnt: int):
	if item:
		if inventory.HasItem(item, cnt):
			inventory.RemoveItem(item, cnt)
		else:
			print("仓库的 ",item.CardName," 不够！还差",cnt - inventory.ItemCnt(item),"个")
		refresh_ui()
	else:
		print("item不存在")

func sort_by_card_name():
	inventory.SortByCardName()
	refresh_ui()

func _on_refresh_button_button_down() -> void:
	sort_by_card_name()


func _on_left_button_button_down() -> void:
	if now_page <= 1:
		return
	now_page = now_page - 1
	refresh_ui()


func _on_right_button_button_down() -> void:
	if now_page >= page_mag:
		return
	now_page = now_page + 1
	refresh_ui()


func _on_button_pressed() -> void:
	add_item_by_name("fish",4)
