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
	#print(inventory_grid)
	#print(inventory_component)
	#print(inventory_control)

func _on_inventory_grid_card_be_snapper(node_name) -> void:
	#print("你传过来的是：",node_name,"  my_position: ",get_parent().name)
	
	#inventory_func(node_name)
	user_inventory_func(node_name)
	
func user_inventory_func(node_name):
	for card in target_snapper.snapped_cards.keys():
		if card != node_name and target_snapper.snapped_cards[card] == target_snapper.snapped_cards[node_name]:
			#print("它占据了",card)
			
			var node_num: int = get_num_form_name(node_name)
			var card_num: int = get_num_form_name(card)
			var item_stack = _slots[node_num-1]
			if item_stack:
				var item = item_stack.Item
				var item_cnt: int = item_stack.Amount
				if item and item_cnt:
					inventory_component.RemoveItem(item, item_cnt)
					inventory_control.refresh_ui()
					print(item.CardName," ",item_cnt)
					#获取对应节点
					var card_node = inventory_grid.get_node(get_name_from_name(card))
					print(card_node)
					card_node.get_node("CardName").text = "%s x%d" % [item.CardName, item_cnt]
					
func inventory_func(node_name):
	
	for card in target_snapper.snapped_cards.keys():
		if card != node_name and target_snapper.snapped_cards[card] == target_snapper.snapped_cards[node_name]:
			print("它占据了",card)
			
			var node_num: int = get_num_form_name(node_name)
			var card_num: int = get_num_form_name(card)
			inventory_component.MoveItem(node_num-1,card_num-1)
			inventory_control.refresh_ui()
			
			#exchange_position(card,node_name)
			#inventory_grid.card = card
			#inventory_grid.skip = true
			#inventory_grid.finish_drag()

func get_num_form_name(node):
	var name1 = node.name
	var parts = name1.split("_") 
	var num_str = parts[1].split(":")[0]
	var num = int(num_str)
	return num

func get_name_from_name(node):
	var name1 = node.name
	var parts = name1.split(":") 
	var node_name = parts[0]
	return node_name

func exchange_position(card,node_name):
	var ex_pos = inventory_grid.original_position[card]
	inventory_grid.original_position[card] = inventory_grid.original_position[node_name]
	target_snapper.snapped_cards[card] = inventory_grid.original_position[card]
	inventory_grid.original_position[node_name] = ex_pos
