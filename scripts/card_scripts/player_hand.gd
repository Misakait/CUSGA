extends Node2D

const HAND_COUNT = 10 #生成的手牌数量
const CARD_SCENE_PATH = "uid://b3l5aai61f7g6"
const CARD_WIDTH = 110 #卡牌宽度，影响卡牌间隔
const HAND_Y_POSITION = 600 #卡牌在屏幕上的高度位置

var player_hand = [] #玩家手牌
var center_screen_x

func _ready() -> void:
	center_screen_x = get_viewport().size.x / 2

	var card_scene = preload(CARD_SCENE_PATH)
	for i in range(HAND_COUNT):
		var new_card = card_scene.instantiate()
		$"../CardManager".add_child(new_card)
		new_card.name = "Card" #方便调试
		add_card_to_hand(new_card)

func add_card_to_hand(card):
	if card not in player_hand:
		player_hand.insert(0, card)
		update_hand_positions()
	else:
		animate_card_to_position(card,card.hand_position)

func update_hand_positions():
	for i in range(player_hand.size()):
		# 根据索引获取卡牌的新位置
		var new_position = Vector2(calculate_card_position(i), HAND_Y_POSITION)
		var card = player_hand[i]
		card.hand_position = new_position
		animate_card_to_position(card, new_position)

func calculate_card_position(index):
	var total_width = (player_hand.size() - 1) * CARD_WIDTH
	var x_offset = center_screen_x + index * CARD_WIDTH - total_width / 2.0
	return x_offset

func animate_card_to_position(card, new_position):
	var tween = get_tree().create_tween()
	tween.tween_property(card, "position", new_position, 0.1)

func remove_card_from_hand(card):
	if card in player_hand:
		player_hand.erase(card)
		update_hand_positions()
