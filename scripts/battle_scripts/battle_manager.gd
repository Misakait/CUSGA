extends Node

@onready var deck_manager = $DeckManager
@onready var hand_ui = $HandUI

@export var starting_deck: Array[SkillCardData] ##初始携带的卡组
@export var card_scene: PackedScene 

var player_energy: int = 100
const MAX_ENERGY: int = 100

func _ready():
	#初始化卡牌
	deck_manager.initialize_deck(starting_deck)
	
	start_player_turn()

func start_player_turn():
	print("--- 玩家回合开始 ---")
	player_energy = MAX_ENERGY
	deck_manager.draw_cards(5)
	
	update_hand_ui() # 抽完牌后更新UI
	
	# 模拟 AI 自动打出第一张手牌测试逻辑
	#if deck_manager.hand.size() > 0:
		#var card_to_play = deck_manager.hand[0]
		#if player_energy >= card_to_play.energy_cost:
			#print("打出卡牌：", card_to_play.card_name)
			#player_energy -= card_to_play.energy_cost
			## deck_manager.play_card(card_to_play, null) # 暂无目标
			#
	end_player_turn()

func end_player_turn():
	deck_manager.discard_hand()
	print("--- 玩家回合结束 ---")
	# 然后可以调用 start_enemy_turn() 等等

#刷新UI
func update_hand_ui():
	return
	## 1. 先清空当前手牌区已有的UI节点
	#for child in hand_ui.get_children():
		#child.queue_free()
		#
	## 2. 根据DeckManager里的实际手牌，生成新的UI
	#for card_data in deck_manager.hand:
		## 实例化卡牌UI场景
		#var card_instance = card_scene.instantiate() as Card
		## 把它加到HBoxContainer里
		#hand_ui.add_child(card_instance)
		## 把数据传进去，让UI显示对应名字和数值
		#card_instance.setup(card_data)
