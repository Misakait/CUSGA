extends Node

@onready var deck_manager = $DeckManager
@onready var player_hand = $PlayerHand

@export var starting_deck_data: Array[SkillCardData] ##初始携带的卡组的卡牌数据。
@export var card_scene: PackedScene 

const MAX_ENERGY: int = 100

var player_energy: int = 100
var turn_draw_count:int = 5 ##每回合摸牌数

func _ready():
	#初始化摸牌堆
	deck_manager.initialize_deck(starting_deck_data)
	
	start_player_turn()

func start_player_turn():
	print("--- 玩家回合开始 ---")
	deck_manager.draw_cards(turn_draw_count,false)

func end_player_turn():
	deck_manager.discard_hand()
	print("--- 玩家回合结束 ---")
	start_player_turn()

func _on_turn_end_pressed() -> void:
	end_player_turn()

func _on_draw_card_pressed() -> void:
	deck_manager.draw_cards(3)
