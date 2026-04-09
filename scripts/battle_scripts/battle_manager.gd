extends Node

@onready var deck_manager = $DeckManager
@onready var player_hand = $PlayerHand
@onready var control_lock = $ControlLock
@onready var player_manager = $PlayerManager
@onready var monster_manager = $MonsterManager

@export var starting_deck_data: Array[SkillCardData] ##初始携带的卡组的卡牌数据。
@export var starting_monster_data: Array[MonsterData] ##初始怪物的卡牌数据。
@export var card_scene: PackedScene

var turn_draw_count:int = 5 ##每回合摸牌数

func _ready():
	#初始化摸牌堆
	deck_manager.initialize_deck(starting_deck_data)
	#初始化怪物
	monster_manager.initialize_monsters(starting_monster_data)

	start_player_turn()

func start_player_turn():
	control_lock.unlock()
	print("--- 玩家回合开始 ---")
	deck_manager.draw_cards(turn_draw_count,false)

func end_player_turn():
	control_lock.lock()
	deck_manager.discard_hand()
	print("--- 玩家回合结束 ---")

	start_player_turn()

func _on_turn_end_pressed() -> void:
	if control_lock.is_lock:
		return
	end_player_turn()

func _on_draw_card_pressed() -> void:
	if control_lock.is_lock:
		return
	deck_manager.draw_cards(3)
