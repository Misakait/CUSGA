extends Node2D
@export var inventory_grid: Node2D
@export var inventory_component: Node2D
@export var inventory_control: Control
var target_snapper

func _ready() -> void:
	target_snapper = inventory_grid.binder.target_snapper

func _on_inventory_grid_card_be_snapper(node_name) -> void:
	#print("你传过来的是：",node_name,"  my_position: ",get_parent().name)

	#inventory_func(node_name)
	user_inventory_func(node_name)

func user_inventory_func(node_name):
	for card in target_snapper.snapped_cards.keys():
		if card != node_name and target_snapper.snapped_cards[card] == target_snapper.snapped_cards[node_name]:
			#print("它占据了",card)
			var card_name = get_name_from_name(card)
			if card_name != "usercard":
				return

			#print("node_name: ",node_name," card: ",card)
			var node_num: int = get_num_form_name(node_name)
			var card_num: int = get_num_form_name(card)
			var item_stack = inventory_component.GetStackAt(node_num-1)
			if item_stack:
				var item = item_stack.Item
				var item_cnt: int = item_stack.Amount
				#print("item:",item," item_cnt: ",item_cnt)

				inventory_component.ClearItem(node_num-1)
				#获取对应节点
				var card_node = inventory_grid.get_node(str(card.name))
				inventory_component.AddItem(card_node.item_data,card_node.item_cnt)
				card_node.item_data = item
				card_node.item_cnt = item_cnt
				if item:
					card_node.get_node("CardName").text = "%s x%d" % [item.CardName, item_cnt]
				else:
					card_node.get_node("CardName").text = "-"
				inventory_control.refresh_ui()

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
	var parts = name1.split("_")
	var node_name = parts[0]
	return node_name

func exchange_position(card,node_name):
	var ex_pos = inventory_grid.original_position[card]
	inventory_grid.original_position[card] = inventory_grid.original_position[node_name]
	target_snapper.snapped_cards[card] = inventory_grid.original_position[card]
	inventory_grid.original_position[node_name] = ex_pos
