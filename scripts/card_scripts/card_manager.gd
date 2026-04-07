extends Node2D

@onready var deck_manager = $"../DeckManager"
@onready var control_lock = $"../ControlLock"
@onready var player_manager = $"../PlayerManager"

const COLLISION_MASK_CARD = 1
const COLLISION_MASK_CARD_SLOT = 2

var screen_size
var card_being_dragged:Node2D
var is_hovering_on_card:bool
var player_hand_referencd #玩家手牌引用
var drag_offset: Vector2 # 用于记录拖拽偏移量

func _ready() -> void:
	screen_size = get_viewport_rect().size
	player_hand_referencd = $"../PlayerHand"

func _process(delta: float) -> void:
	if card_being_dragged:
		var mouse_pos = get_global_mouse_position()
		# 将偏移量应用到目标位置上
		var target_pos = mouse_pos + drag_offset 
		card_being_dragged.position = Vector2(
			clamp(target_pos.x, 0, screen_size.x),
			clamp(target_pos.y, 0, screen_size.y)
		)
	check_cards_energy()

func check_cards_energy():
	if control_lock.is_lock:
		return
	var pm = player_manager
	for card in player_hand_referencd.player_hand_card:
		if pm.energy < card.data.cost:
			card.lock()
		else:
			card.unlock()

func _input(event):
	if control_lock.is_lock:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var card = raycast_check_for_card()
			if card:
				start_drag(card)
		else:
			if card_being_dragged:
				finish_drag()

func start_drag(card):
	if player_manager.energy < card.data.cost:
		return
	card_being_dragged = card
	# 记录鼠标点击位置与卡牌原点之间的差值
	drag_offset = card.position - get_global_mouse_position()
	card.scale = Vector2(1, 1)

func finish_drag():
	card_being_dragged.scale = Vector2(1.05, 1.05)
	var card_slot_found = raycast_check_for_card_slot()
	if card_slot_found:
		$"../PlayerManager".consume_energy(card_being_dragged.data.cost)
		deck_manager.play_card(card_being_dragged,card_slot_found.get_parent())
		player_hand_referencd.remove_card_from_hand(card_being_dragged)
		#card_being_dragged.position = card_slot_found.position
	else:#如果拖动后没进入卡槽，则回到玩家手中
		player_hand_referencd.add_card_to_hand(card_being_dragged)
		
	card_being_dragged = null

func connect_card_signals(card):
	card.connect("hovered", on_hovered_over_card)
	card.connect("hovered_off", on_hovered_off_card)

func on_hovered_over_card(card):
	if !is_hovering_on_card:
		is_hovering_on_card = true
		highlight_card(card, true)

func on_hovered_off_card(card):
	if !card_being_dragged:
		highlight_card(card, false)
		# Check if hovered off card straight on to another card
		var new_card_hovered = raycast_check_for_card()
		if new_card_hovered:
			highlight_card(new_card_hovered, true)
		else:
			is_hovering_on_card = false

func highlight_card(card, hovered):
	if hovered:
		card.scale = Vector2(1.05, 1.05)
		card.z_index = 2
	else:
		card.scale = Vector2(1, 1)
		card.z_index = 1

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
	
#复用上方代码，检测卡牌槽
func raycast_check_for_card_slot():
	var space_state = get_world_2d().direct_space_state
	var parameters = PhysicsPointQueryParameters2D.new()
	
	#将鼠标改为卡牌中心，即卡牌中心进入框内即可放入卡槽
	parameters.position = card_being_dragged.global_position 
	#parameters.position = get_global_mouse_position()
	
	parameters.collide_with_areas = true
	parameters.collision_mask = COLLISION_MASK_CARD_SLOT
	var result = space_state.intersect_point(parameters)
	if result.size() > 0:
		return result[0].collider.get_parent()
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
