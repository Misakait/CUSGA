extends Node2D

signal card_be_snapper(node_name)

@export var draggable: Draggable
@export var binder: SnapperBinder

const COLLISION_MASK_CARD = 1
const COLLISION_MASK_CARD_SLOT = 2

var original_position: Dictionary   # 记录卡牌原始位置
var card = null
var hovering_card = null

func _input(event):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			card = raycast_check_for_card()
			
			#这个是用来防止出现了两个mainmenucardmanager的情况，因为它共享同一个鼠标
			if !original_position.has(card):
				card = null
			
			if card:
				start_drag()
		else:
			finish_drag()
			
	if card:
		draggable.handle_event(event, card)
		
func start_drag():
	card.start_drag()
	var snapped := binder.target_snapper.snapped_cards.has(card)
	# 如果卡牌已经在 snapper 的 snapped_cards 里，直接释放它
	if binder and binder.target_snapper and binder.target_snapper.snapped_cards.has(card):
		binder.target_snapper.release_card(card)
	
func finish_drag():
	if card != null : 
		card.finish_drag()
		var snapped := false
		
		if !snapped and binder and binder.target_snapper:
			binder.target_snapper.snap_card(card)
			# 如果 snapper 成功吸附，会在 snapped_cards 里记录
			snapped = binder.target_snapper.snapped_cards.has(card)
		
		if binder and snapped:
			emit_signal("card_be_snapper", card.name)
		
		if binder and not snapped :
			# 没有吸附成功 → 回到原位
			var tween = card.create_tween()
			tween.tween_property(card, "global_position", original_position[card], 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	card = null

#光线投射，检查并获取鼠标下的卡牌
func raycast_check_for_card():
	var space_state = get_world_2d().direct_space_state
	var parameters = PhysicsPointQueryParameters2D.new()
	parameters.position = get_global_mouse_position()
	parameters.collide_with_areas = true
	parameters.collision_mask = COLLISION_MASK_CARD
	var result = space_state.intersect_point(parameters)
	if result.size() > 0:
		return get_card_with_highest_z_index(result)
	return null
	
#获取传入卡牌中z最高的牌
func get_card_with_highest_z_index(cards):
	var highest_z_card = cards[0].collider.get_parent()
	var highest_z_index = highest_z_card.z_index
	for i in range(1, cards.size()):
		var current_card = cards[i].collider.get_parent()
		if current_card.z_index > highest_z_index:
			highest_z_card = current_card
			highest_z_index = current_card.z_index
	return highest_z_card
	
func _on_hovering_card(that_card):
	hovering_card = raycast_check_for_card()
	
func _on_not_hovering_card(that_card):
	hovering_card = raycast_check_for_card()
	if hovering_card:
		hovering_card._on_area_2d_mouse_entered()
