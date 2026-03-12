extends Node
class_name DeckManager

var draw_pile: Array[CardData] = []
var hand: Array[CardData] = []
var discard_pile: Array[CardData] = []

# 初始化牌库
func initialize_deck(starting_deck: Array[CardData]):
	draw_pile = starting_deck.duplicate()
	draw_pile.shuffle()
	
	# 你的规则：卡牌数少于 10 张（每回合5张*2），补充低级卡
	if draw_pile.size() < 10:
		fill_with_basic_cards(10 - draw_pile.size())

# 抽牌
func draw_cards(amount: int):
	for i in range(amount):
		if draw_pile.is_empty():
			if discard_pile.is_empty():
				print("没有牌可以抽了！")
				break
			else:
				reshuffle_discard_into_draw()
		
		var card = draw_pile.pop_back()
		hand.append(card)
	print("抽了牌。当前手牌数：", hand.size())

# 打出卡牌
func play_card(card: CardData, target):
	if not card in hand: return
	
	# 执行卡牌效果
	card.apply_effect(target)
	
	# 从手牌移除，进入弃牌堆
	hand.erase(card)
	discard_pile.append(card)

# 丢弃所有手牌
func discard_hand():
	discard_pile.append_array(hand)
	hand.clear()
	print("回合结束，手牌已清空进入弃牌堆。")
	#print("弃牌堆:",discard_pile)
	#print("手牌:",hand)
	#print("摸牌堆:",draw_pile)

# 洗牌逻辑
func reshuffle_discard_into_draw():
	print("抽牌堆为空，洗切弃牌堆...")
	draw_pile = discard_pile.duplicate()
	discard_pile.clear()
	draw_pile.shuffle()

# 补充基础卡牌（你的特殊规则）
func fill_with_basic_cards(amount: int):
	for i in range(amount):
		var basic_card = CardData.new()
		basic_card.card_name = "填充卡牌测试001" # 这里最好加载你预设的基础卡 Resource
		basic_card.energy_cost = 10
		draw_pile.append(basic_card)
