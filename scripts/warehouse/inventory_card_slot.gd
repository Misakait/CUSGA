extends Node2D
var inventory_grid
var inventory_component
var inventory_control
var _slots
var target_snapper

func _ready() -> void:
	inventory_grid = get_tree().root.get_node("Warehouse").get_node("InventoryGrid")
	inventory_component = get_tree().root.get_node("Warehouse").get_node("InventoryComponent")
	inventory_control = get_tree().root.get_node("Warehouse").get_node("InventoryControl")
	target_snapper = inventory_grid.binder.target_snapper
	_slots = inventory_component._slots
	#print(inventory_component)
	#print(inventory_control)

func _on_inventory_grid_card_be_snapper(node) -> void:
	for card in target_snapper.snapped_cards.keys():
		if card != node and target_snapper.snapped_cards[card] == target_snapper.snapped_cards[node]:
			var node_name = get_name_from_name(node)
			var card_name = get_name_from_name(card)
			#print("node_name: ",node_name,"  card_name: ",card_name)
			
			if node_name == "card" and card_name == "card":
				inventory_inventory_func(node,card)
				inventory_control.refresh_ui()
			
			elif node_name == "card" and card_name == "usercard":
				inventory_user_func(node,card)
				inventory_control.refresh_ui()
				
			elif node_name == "usercard" and card_name == "card":
				inventory_user_func(card,node)
				inventory_control.refresh_ui()
				
			elif node_name == "usercard" and card_name == "usercard":
				user_user_func(node,card)
				inventory_control.refresh_ui()
			
			else:
				print("你进行交互的两张牌有问题，去inventory_card_slot看看吧")

#仓库槽位之间的交互
func inventory_inventory_func(node,card):
	var node_num: int = get_num_form_name(node)
	var card_num: int = get_num_form_name(card)
	print("之前的node: ",_slots[node_num-1].Amount,"  之前的card: ",_slots[card_num-1].Amount)
	inventory_component.MoveItem(node_num-1,card_num-1)
	print("之后的node: ",_slots[node_num-1].Amount,"  之后的card: ",_slots[card_num-1].Amount)

#仓库槽位与“能够将卡牌带入游戏的卡槽”之间的交互
func inventory_user_func(node,card):
	var node_num: int = get_num_form_name(node)
	var card_num: int = get_num_form_name(card)
	var item_stack = _slots[node_num-1]
	
	var item: ItemData = null
	var item_cnt: int = 0
	if item_stack:
		item = item_stack.Item
		item_cnt = item_stack.Amount
	#设置node
	var card_node = inventory_grid.get_node(str(card.name))
	inventory_component.ReplaceItem(node_num-1,card_node.item_data,card_node.item_cnt)
	#设置card
	card_node.item_data = item
	card_node.item_cnt = item_cnt
	if item:
		card_node.get_node("CardName").text = "%s x%d" % [item.CardName, item_cnt]
	else:
		card_node.get_node("CardName").text = "-"

#“能够将卡牌带入游戏的卡槽”之间的交互
func user_user_func(node,card):
	var node_node = inventory_grid.get_node(str(node.name))
	var card_node = inventory_grid.get_node(str(card.name))
	var ex_item = node_node.item_data
	var ex_cnt = node_node.item_cnt
	node_node.item_data = card_node.item_data
	node_node.item_cnt = card_node.item_cnt
	card_node.item_data = ex_item
	card_node.item_cnt = ex_cnt
	if node_node.item_data:
		node_node.get_node("CardName").text = "%s x%d" % [node_node.item_data.CardName, node_node.item_cnt]
	else:
		node_node.get_node("CardName").text = "-"
	if card_node.item_data:
		card_node.get_node("CardName").text = "%s x%d" % [card_node.item_data.CardName, card_node.item_cnt]
	else:
		card_node.get_node("CardName").text = "-"
	

func get_name_from_name(node):
	var name1 = node.name
	var parts = name1.split("_") 
	var node_name = parts[0]
	return node_name

func get_num_form_name(node):
	var name1 = node.name
	var parts = name1.split("_") 
	var num_str = parts[1].split(":")[0]
	var num = int(num_str)
	return num

func exchange_position(card,node_name):
	var ex_pos = inventory_grid.original_position[card]
	inventory_grid.original_position[card] = inventory_grid.original_position[node_name]
	target_snapper.snapped_cards[card] = inventory_grid.original_position[card]
	inventory_grid.original_position[node_name] = ex_pos
