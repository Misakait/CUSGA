extends Node

@onready var deck_manager = $DeckManager
@onready var player_hand = $PlayerHand

@export var starting_deck_data: Array[SkillCardData] ##初始携带的卡组的卡牌数据。
@export var card_scene: PackedScene 

var player_energy: int = 100
const MAX_ENERGY: int = 100

func _ready():
	#初始化摸牌堆
	deck_manager.initialize_deck(starting_deck_data)
	
	start_player_turn()

func start_player_turn():
	print("--- 玩家回合开始 ---")
	deck_manager.draw_cards(5)

	end_player_turn()

func end_player_turn():
	deck_manager.discard_hand()
	print("--- 玩家回合结束 ---")
	# 然后可以调用 start_enemy_turn() 等等
