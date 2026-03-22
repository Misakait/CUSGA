extends Node2D

@onready var card_manager = $"../CardManager"
@onready var deck_manager = $"../DeckManager"

const CARD_SCENE_PATH = "uid://ca8m4rlwkbbvq"
const CARD_WIDTH = 200 #卡牌宽度，影响卡牌间隔
const HAND_Y_POSITION = 580 #第一行卡牌的高度位置
const MAX_CARDS_PER_ROW = 6 # 每行最大卡牌数量
const ROW_SPACING_Y = 80   # 两行之间的Y轴垂直间距 (正数往下排，负数往上排)

var player_hand_card:Array[Node2D] = [] #玩家手牌。
var center_screen_x

func _ready() -> void:
	center_screen_x = get_viewport().size.x / 2

func draw_card_data(card_data):
	var card_scene = preload(CARD_SCENE_PATH)
	var new_card = card_scene.instantiate()
	new_card.init_card_data(card_data)
	card_manager.add_child(new_card)
	add_card_to_hand(new_card)

func add_card_to_hand(card):
	if card not in player_hand_card:
		player_hand_card.insert(0, card)
		update_hand_positions()
	else:
		animate_card_to_position(card, card.hand_position)

func remove_card_from_hand(card):
	if card in player_hand_card:
		print(card.data.name,"被移除了！")
		player_hand_card.erase(card)
		card.queue_free()
		update_hand_positions()

func update_hand_positions():
	for i in range(player_hand_card.size()):
		# 直接获取计算好的 Vector2 坐标
		var new_position = calculate_card_position(i)
		var card = player_hand_card[i]
		card.hand_position = new_position
		animate_card_to_position(card, new_position)

# 返回 Vector2，同时计算 X 和 Y
func calculate_card_position(index) -> Vector2:
	# 计算当前卡牌属于第几行 (0为第一行，1为第二行)
	var row = index / MAX_CARDS_PER_ROW
	# 计算当前卡牌在当前行是第几个 (0 到 MAX_CARDS_PER_ROW-1)
	var col = index % MAX_CARDS_PER_ROW
	
	# 计算当前行实际有多少张卡牌（为了让不满一行的卡牌也能居中）
	var cards_in_current_row = min(MAX_CARDS_PER_ROW, player_hand_card.size() - row * MAX_CARDS_PER_ROW)
	
	# 计算 X 坐标：使得当前行的卡牌整体居中
	var total_width = (cards_in_current_row - 1) * CARD_WIDTH
	var x_offset = center_screen_x + col * CARD_WIDTH - total_width / 2.0
	
	# 计算 Y 坐标：第一行是 HAND_Y_POSITION，第二行增加 ROW_SPACING_Y
	var y_offset = HAND_Y_POSITION + row * ROW_SPACING_Y
	
	return Vector2(x_offset, y_offset)

func animate_card_to_position(card, new_position):
	var tween = get_tree().create_tween()
	tween.tween_property(card, "position", new_position, 0.1)
